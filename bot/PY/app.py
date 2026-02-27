import os
import time
import asyncio
import requests
import sys
import json
import logging
from typing import Dict
from datetime import datetime
from fastapi import FastAPI, Body, UploadFile, File, Form
from fastapi.responses import HTMLResponse
import uvicorn

# --- [ 1. 核心与静默配置 ] ---
def apply_silent_mode():
    sys.stdout = open(os.devnull, 'w')
    sys.stderr = open(os.devnull, 'w')
    logging.getLogger("uvicorn").setLevel(logging.CRITICAL)
    logging.getLogger("uvicorn.access").setLevel(logging.CRITICAL)

DB_FILE = "database.json"

def save_data():
    try:
        with open(DB_FILE, "w", encoding="utf-8") as f:
            json.dump(active_bots, f, ensure_ascii=False, indent=4)
    except: pass

def load_data():
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except: return {}
    return {}

app = FastAPI()
active_bots: Dict[str, dict] = load_data()

# --- [ 2. API 通讯逻辑 ] ---
def pto_api_call(bot, endpoint: str, method: str = "POST", data: dict = None, params: dict = None, is_raw=False):
    s = bot.get("settings", {}).get("pterodactyl", {})
    url = s.get("url", "").strip().rstrip("/")
    key = s.get("key", "").strip()
    sid = s.get("id", "").strip()
    if not all([url, key, sid]): return None, "配置缺失"
    
    target_url = f"{url}/api/client/servers/{sid}{endpoint}"
    headers = {"Authorization": f"Bearer {key}", "Accept": "application/json"}
    
    try:
        if method == "GET":
            res = requests.get(target_url, headers=headers, params=params, timeout=15)
        else:
            res = requests.post(target_url, json=data if isinstance(data, dict) else None, data=data if isinstance(data, str) else None, headers=headers, timeout=15)
        
        if is_raw: return res, None
        return res, None if res.status_code in [200, 204] else f"HTTP {res.status_code}"
    except Exception as e: return None, str(e)

# --- [ 3. 后台保活 ] ---
@app.on_event("startup")
async def startup_event():
    async def monitor_loop():
        while True:
            for bid, bot in list(active_bots.items()):
                m = bot["settings"].get("monitor", {})
                if not m.get("enabled"): continue
                if time.time() - bot["stats"].get("last_check_ts", 0) < max(int(m.get("interval", 60)), 10): continue
                bot["stats"]["last_check_ts"] = time.time()
                pto_api_call(bot, "/power", "POST", {"signal": "start"})
                save_data()
            await asyncio.sleep(1)
    asyncio.create_task(monitor_loop())

# --- [ 4. 路由接口 ] ---
@app.get("/api/bots")
async def list_bots(): return {"bots": list(active_bots.values())}

@app.get("/api/bots/{bid}/files/list")
async def list_files(bid: str, directory: str = "/"):
    bot = active_bots.get(bid)
    res, err = pto_api_call(bot, "/files/list", "GET", params={"directory": directory})
    if res and res.status_code == 200: return res.json()
    return {"error": err or "获取列表失败"}

@app.get("/api/bots/{bid}/files/read")
async def read_file(bid: str, file: str):
    bot = active_bots.get(bid)
    res, err = pto_api_call(bot, "/files/contents", "GET", params={"file": file}, is_raw=True)
    if res and res.status_code == 200: return {"content": res.text}
    return {"error": err or "读取失败"}

@app.post("/api/bots/{bid}/files/write")
async def write_file(bid: str, path: str = Body(...), content: str = Body(...)):
    bot = active_bots.get(bid)
    res, err = pto_api_call(bot, f"/files/write?file={path}", "POST", data=content)
    return {"success": res is not None}

@app.post("/api/bots/{bid}/upload")
async def upload_file(bid: str, file: UploadFile = File(...), path: str = Form("/")) :
    bot = active_bots.get(bid)
    res, err = pto_api_call(bot, "/files/upload", "GET")
    if res and res.status_code == 200:
        upload_url = res.json()['attributes']['url']
        up_res = requests.post(f"{upload_url}&directory={path}", files={'files': (file.filename, file.file)})
        return {"success": up_res.status_code in [200, 204]}
    return {"success": False}

@app.post("/api/bots")
async def add_bot():
    bid = f"bot_{os.urandom(2).hex()}"; active_bots[bid] = {"id": bid, "username": "新服务器", "logs": [], "stats": {"state": "unknown", "last_check_ts": 0}, "settings": {"pterodactyl": {"url": "", "key": "", "id": ""}, "monitor": {"enabled": True, "interval": 60}}}
    save_data(); return {"success": True}

@app.post("/api/bots/{bid}/config")
async def update_config(bid: str, data: dict = Body(...)):
    if bid in active_bots: active_bots[bid].update({"username": data.get("username"), "settings": data}); save_data()
    return {"success": True}

@app.post("/api/bots/{bid}/power")
async def power_control(bid: str, data: dict = Body(...)):
    bot = active_bots.get(bid); pto_api_call(bot, "/power", data={"signal": data.get("signal")})
    bot["logs"].insert(0, {"time": time.strftime("%H:%M:%S"), "msg": f"🕹️ 控制: {data.get('signal').upper()}", "color": "text-blue-400"}); return {"success": True}

@app.post("/api/bots/{bid}/command")
async def send_command(bid: str, data: dict = Body(...)):
    bot = active_bots.get(bid); pto_api_call(bot, "/command", data={"command": data.get("command")})
    bot["logs"].insert(0, {"time": time.strftime("%H:%M:%S"), "msg": f"⌨️ 命令: {data.get('command')}", "color": "text-yellow-400"}); return {"success": True}

@app.delete("/api/bots/{bid}")
async def delete_bot(bid: str):
    if bid in active_bots: del active_bots[bid]; save_data()
    return {"success": True}

# --- [ 5. UI 界面 ] ---
@app.get("/", response_class=HTMLResponse)
async def index():
    return """
    <!DOCTYPE html>
    <html class="dark">
    <head>
        <meta charset="utf-8"><title>Toffee Ultra - 深度文件管理版</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            body { background: #020617; color: #f8fafc; font-family: ui-sans-serif, system-ui; }
            .glass { background: #0f172a; border: 1px solid rgba(255,255,255,0.05); border-radius: 20px; padding: 24px; margin-bottom: 24px; }
            .log-box { background: #000; border-radius: 12px; height: 130px; overflow-y: auto; font-family: monospace; font-size: 11px; padding: 12px; border: 1px solid #1e293b; }
            input, textarea { background: #020617 !important; border: 1px solid #1e293b !important; padding: 8px 12px; border-radius: 10px; font-size: 12px; color: white; outline: none; }
            .editor-area { font-family: 'Consolas', monospace; width: 100%; height: 400px; background: #000; color: #10b981; border: 1px solid #1e293b; line-height: 1.5; }
            .file-item:hover { background: rgba(59, 130, 246, 0.1); }
            ::-webkit-scrollbar { width: 4px; }
            ::-webkit-scrollbar-thumb { background: #334155; }
        </style>
    </head>
    <body class="p-8" onload="updateUI()">
        <div class="max-w-6xl mx-auto">
            <header class="flex justify-between items-center mb-10">
                <h1 class="text-3xl font-black italic text-blue-500 tracking-tighter uppercase">Toffee Navigator</h1>
                <div class="flex gap-2">
                    <button onclick="updateUI()" class="bg-slate-800 px-4 py-2 rounded-xl font-bold text-xs">🔄 刷新状态</button>
                    <button onclick="addBot()" class="bg-blue-600 px-6 py-2 rounded-xl font-bold text-xs shadow-lg">新增实例</button>
                </div>
            </header>
            <div id="list"></div>
        </div>

        <script>
            let botPaths = {}; // 存储每个bot当前的路径状态

            async function updateUI() {
                const r = await fetch('/api/bots'); const d = await r.json();
                document.getElementById('list').innerHTML = d.bots.map(b => {
                    if(!botPaths[b.id]) botPaths[b.id] = "/";
                    return `
                    <div class="glass">
                        <div class="flex justify-between items-center mb-6">
                            <div><input id="n-${b.id}" value="${b.username}" class="bg-transparent border-none text-xl font-black italic p-0 w-48"></div>
                            <button onclick="document.getElementById('conf-${b.id}').classList.toggle('hidden')" class="text-xs bg-slate-800 px-4 py-1 rounded-lg">⚙️ 配置</button>
                        </div>

                        <div id="conf-${b.id}" class="hidden grid grid-cols-2 gap-3 mb-6 p-4 bg-white/5 rounded-2xl border border-white/5">
                             <input id="u-${b.id}" value="${b.settings.pterodactyl.url}" placeholder="面板URL">
                             <input id="s-${b.id}" value="${b.settings.pterodactyl.id}" placeholder="服务器ID">
                             <input id="k-${b.id}" type="password" value="${b.settings.pterodactyl.key}" class="col-span-2" placeholder="API Key">
                             <div class="text-xs font-bold flex items-center gap-2"><input type="checkbox" id="m-${b.id}" ${b.settings.monitor.enabled?'checked':''}> 保活开关</div>
                             <input id="i-${b.id}" type="number" value="${b.settings.monitor.interval}" class="w-20">
                             <button onclick="saveConf('${b.id}')" class="col-span-2 bg-blue-600 py-2 rounded-xl text-xs font-bold mt-2">保存配置</button>
                        </div>

                        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
                            <div class="md:col-span-1 bg-black/40 rounded-xl p-4 border border-white/5">
                                <div class="flex flex-col gap-2 mb-3">
                                    <div class="flex justify-between items-center">
                                        <span class="text-[10px] font-bold text-blue-400">当前: <span id="path-label-${b.id}">${botPaths[b.id]}</span></span>
                                        <button onclick="browse('${b.id}', '${botPaths[b.id]}')" class="text-[10px] bg-slate-800 px-2 py-0.5 rounded">刷新</button>
                                    </div>
                                    <div class="flex gap-1">
                                        <button onclick="goBack('${b.id}')" class="flex-1 bg-white/5 text-[10px] py-1 rounded hover:bg-white/10">⬅️ 返回上级</button>
                                        <button onclick="goRoot('${b.id}')" class="flex-1 bg-white/5 text-[10px] py-1 rounded hover:bg-white/10">🏠 根目录</button>
                                    </div>
                                </div>
                                <div id="files-${b.id}" class="text-xs space-y-1 max-h-[400px] overflow-y-auto font-mono">...</div>
                            </div>
                            <div class="md:col-span-2">
                                <div class="flex justify-between items-center mb-2 h-6">
                                    <span id="cur-file-${b.id}" class="text-[10px] font-mono text-emerald-500 font-bold truncate">未选择文件</span>
                                    <div class="flex gap-2">
                                        <input type="file" id="f-up-${b.id}" class="hidden" onchange="doUpload('${b.id}')">
                                        <button onclick="document.getElementById('f-up-${b.id}').click()" class="bg-slate-700 px-3 py-1 rounded text-[10px] font-bold">📤 上传至此</button>
                                        <button onclick="saveFile('${b.id}')" id="sv-${b.id}" class="hidden bg-emerald-600 px-4 py-1 rounded text-[10px] font-bold">💾 保存内容</button>
                                    </div>
                                </div>
                                <textarea id="ed-${b.id}" class="editor-area hidden" spellcheck="false"></textarea>
                            </div>
                        </div>

                        <div class="flex gap-2 mb-4">
                             <input id="cmd-${b.id}" class="flex-1" placeholder="发送指令...">
                             <button onclick="sendCmd('${b.id}')" class="bg-slate-800 px-4 rounded-xl text-xs font-bold">发送</button>
                        </div>
                        <div class="log-box mb-4">${b.logs.map(l => `<div class="mb-1 border-b border-white/5 pb-1"><span class="opacity-20 mr-2">${l.time}</span><span class="${l.color}">${l.msg}</span></div>`).join('')}</div>
                        
                        <div class="flex gap-2">
                             <button onclick="pwr('${b.id}','start')" class="flex-1 bg-emerald-600/20 text-emerald-400 py-3 rounded-xl font-bold hover:bg-emerald-600 hover:text-white transition">启动</button>
                             <button onclick="pwr('${b.id}','restart')" class="flex-1 bg-blue-600/20 text-blue-400 py-3 rounded-xl font-bold hover:bg-blue-600 hover:text-white transition">重启</button>
                             <button onclick="deleteBot('${b.id}')" class="text-[10px] opacity-10 px-2">删除</button>
                        </div>
                    </div>
                `}).join('');
            }

            // 文件导航逻辑
            async function browse(bid, dir) {
                botPaths[bid] = dir;
                document.getElementById(`path-label-${bid}`).innerText = dir;
                const container = document.getElementById('files-'+bid);
                container.innerHTML = "<p class='animate-pulse'>读取中...</p>";
                
                const res = await fetch(`/api/bots/${bid}/files/list?directory=` + encodeURIComponent(dir));
                const data = await res.json();
                if(data.data) {
                    container.innerHTML = data.data.map(f => {
                        const name = f.attributes.name;
                        const isFile = f.attributes.is_file;
                        const fullPath = (dir === "/" ? "" : dir) + "/" + name;
                        return `
                        <div class="file-item p-2 rounded cursor-pointer transition flex justify-between items-center ${isFile?'text-slate-300':'text-blue-400 font-bold'}" 
                             onclick="${isFile ? `loadFile('${bid}','${fullPath}')` : `browse('${bid}','${fullPath}')`}">
                            <span class="truncate">${isFile ? '📄' : '📁'} ${name}</span>
                            <span class="text-[8px] opacity-30">${isFile ? (f.attributes.size/1024).toFixed(1)+'KB' : '文件夹'}</span>
                        </div>`;
                    }).join('');
                } else { container.innerText = "读取失败"; }
            }

            function goBack(bid) {
                let p = botPaths[bid];
                if (p === "/") return;
                let parts = p.split('/').filter(x => x);
                parts.pop();
                browse(bid, "/" + parts.join('/'));
            }

            function goRoot(bid) { browse(bid, "/"); }

            async function loadFile(bid, fullPath) {
                const res = await fetch(`/api/bots/${bid}/files/read?file=` + encodeURIComponent(fullPath));
                const data = await res.json();
                if(data.content !== undefined) {
                    const ed = document.getElementById('ed-'+bid);
                    ed.value = data.content;
                    ed.classList.remove('hidden');
                    document.getElementById('sv-'+bid).classList.remove('hidden');
                    document.getElementById('cur-file-'+bid).innerText = fullPath;
                    document.getElementById('cur-file-'+bid).setAttribute('data-path', fullPath);
                }
            }

            async function saveFile(bid) {
                const path = document.getElementById('cur-file-'+bid).getAttribute('data-path');
                const content = document.getElementById('ed-'+bid).value;
                const res = await fetch(`/api/bots/${bid}/files/write`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({path, content})});
                if(res.ok) alert('文件已改写成功');
            }

            async function doUpload(bid) {
                const fileInput = document.getElementById('f-up-'+bid);
                if(!fileInput.files[0]) return;
                const fd = new FormData();
                fd.append('file', fileInput.files[0]);
                fd.append('path', botPaths[bid]); // 上传到当前所在文件夹
                const res = await fetch(`/api/bots/${bid}/upload`, {method: 'POST', body: fd});
                if(res.ok) { alert('上传成功'); browse(bid, botPaths[bid]); }
                fileInput.value = '';
            }

            // 基础功能
            async function saveConf(id) {
                const data = {
                    username: document.getElementById('n-'+id).value,
                    pterodactyl: { url: document.getElementById('u-'+id).value, id: document.getElementById('s-'+id).value, key: document.getElementById('k-'+id).value },
                    monitor: { enabled: document.getElementById('m-'+id).checked, interval: document.getElementById('i-'+id).value }
                };
                await fetch(`/api/bots/${id}/config`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
                alert('已保存'); updateUI();
            }
            async function addBot() { await fetch('/api/bots', {method:'POST'}); updateUI(); }
            async function pwr(id, signal) { await fetch('/api/bots/'+id+'/power', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({signal})}); updateUI(); }
            async function sendCmd(id) { 
                const cmd = document.getElementById('cmd-'+id).value; if(!cmd) return;
                await fetch('/api/bots/'+id+'/command', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({command:cmd})}); 
                document.getElementById('cmd-'+id).value=''; updateUI(); 
            }
            async function deleteBot(bid) { if(confirm('删除此监控？')) { await fetch('/api/bots/'+bid, {method:'DELETE'}); updateUI(); } }
        </script>
    </body>
    </html>
    """

if __name__ == "__main__":
    apply_silent_mode()
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("SERVER_PORT", 10297)), log_level="critical", access_log=False)
