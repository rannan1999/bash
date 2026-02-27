import os
import time
import asyncio
import requests
import sys
import json
import logging
from typing import Dict
from datetime import datetime
from fastapi import FastAPI, Body
from fastapi.responses import HTMLResponse
import uvicorn

# --- [ 1. 静默配置 ] ---
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

# --- [ 2. API 通讯 ] ---
def pto_api_call(bot, endpoint: str, method: str = "POST", data: dict = None):
    s = bot.get("settings", {}).get("pterodactyl", {})
    url = s.get("url", "").strip().rstrip("/")
    key = s.get("key", "").strip()
    sid = s.get("id", "").strip()
    if not all([url, key, sid]): return None, "配置缺失"
    target_url = f"{url}/api/client/servers/{sid}{endpoint}"
    headers = {"Authorization": f"Bearer {key}", "Accept": "application/json", "Content-Type": "application/json"}
    try:
        if method == "GET": res = requests.get(target_url, headers=headers, timeout=12)
        else: res = requests.post(target_url, json=data or {}, headers=headers, timeout=12)
        if res.status_code in [200, 204]: return res, None
        return None, f"HTTP {res.status_code}"
    except: return None, "超时"

# --- [ 3. 后台保活 ] ---
async def monitor_loop():
    while True:
        now_str = datetime.now().strftime("%H:%M:%S")
        for bid, bot in list(active_bots.items()):
            m = bot["settings"].get("monitor", {})
            if not m.get("enabled"): continue
            if time.time() - bot["stats"].get("last_check_ts", 0) < max(int(m.get("interval", 60)), 10): continue
            bot["stats"]["last_check_ts"] = time.time()
            res, err = pto_api_call(bot, "/power", "POST", {"signal": "start"})
            if res:
                if bot["stats"].get("state") != "active":
                    bot["logs"].insert(0, {"time": now_str, "msg": "🟢 实例已进入自动监控状态", "color": "text-emerald-400"})
                bot["stats"]["state"] = "active"
                bot["stats"]["last_err"] = ""
            else:
                bot["stats"]["state"] = "error"
                if bot["stats"].get("last_err") != err:
                    bot["logs"].insert(0, {"time": now_str, "msg": f"⚠️ 唤醒失败: {err}", "color": "text-red-500"})
                    bot["stats"]["last_err"] = err
            bot["logs"] = bot["logs"][:15]
            save_data()
        await asyncio.sleep(1)

# --- [ 4. 路由逻辑 ] ---
@app.on_event("startup")
async def startup_event(): asyncio.create_task(monitor_loop())
@app.get("/api/bots")
async def list_bots(): return {"bots": list(active_bots.values())}
@app.post("/api/bots")
async def add_bot(data: dict = Body(...)):
    bid = f"bot_{os.urandom(2).hex()}"
    active_bots[bid] = {"id": bid, "username": "新实例", "host": "待配置", "logs": [], "stats": {"state": "unknown", "last_check_ts": 0, "last_err": ""}, "settings": {"pterodactyl": {"url": "", "key": "", "id": ""}, "monitor": {"enabled": True, "interval": 60}}}
    save_data(); return {"success": True}
@app.post("/api/bots/{bid}/config")
async def update_config(bid: str, data: dict = Body(...)):
    if bid in active_bots:
        active_bots[bid].update({"username": data.get("username"), "host": data.get("host")})
        active_bots[bid]["settings"] = data
        save_data(); return {"success": True}
    return {"success": False}
@app.post("/api/bots/{bid}/power")
async def power_control(bid: str, data: dict = Body(...)):
    bot = active_bots.get(bid)
    if bot:
        res, err = pto_api_call(bot, "/power", data={"signal": data.get("signal")})
        bot["logs"].insert(0, {"time": time.strftime("%H:%M:%S"), "msg": f"🕹️ 手动: {data.get('signal').upper()}" if res else f"❌ 失败: {err}", "color": "text-blue-400" if res else "text-red-500"})
        save_data()
    return {"success": True}
@app.post("/api/bots/{bid}/command")
async def send_command(bid: str, data: dict = Body(...)):
    bot = active_bots.get(bid)
    if bot:
        res, err = pto_api_call(bot, "/command", data={"command": data.get("command")})
        bot["logs"].insert(0, {"time": time.strftime("%H:%M:%S"), "msg": f"⌨️ 命令: {data.get('command')}" if res else f"❌ 失败: {err}", "color": "text-yellow-400" if res else "text-red-500"})
        save_data()
    return {"success": True}
@app.delete("/api/bots/{bid}")
async def delete_bot(bid: str):
    if bid in active_bots: del active_bots[bid]; save_data(); return {"success": True}
    return {"success": False}

# --- [ 5. UI 界面 ] ---
@app.get("/", response_class=HTMLResponse)
async def index():
    return """
    <!DOCTYPE html>
    <html class="dark">
    <head>
        <meta charset="utf-8"><title>Toffee Pro</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            body { background: #020617; color: #f8fafc; font-family: system-ui, sans-serif; }
            .glass { background: #0f172a; border: 1px solid rgba(255,255,255,0.05); border-radius: 20px; padding: 24px; margin-bottom: 24px; }
            .log-box { background: #000; border-radius: 12px; height: 160px; overflow-y: auto; font-family: monospace; font-size: 11px; padding: 12px; border: 1px solid #1e293b; }
            input { background: #020617; border: 1px solid #1e293b; padding: 8px 12px; border-radius: 10px; font-size: 12px; color: white; outline: none; }
            input:focus { border-color: #3b82f6; }
        </style>
    </head>
    <body class="p-8" onload="startSync()">
        <div class="max-w-4xl mx-auto">
            <header class="flex justify-between items-center mb-10">
                <h1 class="text-4xl font-black italic text-blue-500">TOFFEE PRO</h1>
                <button onclick="addBot()" class="bg-blue-600 px-6 py-2 rounded-xl font-bold text-xs">新增监控</button>
            </header>
            <div id="list"></div>
        </div>
        <script>
            let editingId = null;
            let isTyping = false; // [新增] 判断用户是否正在输入

            function startSync() { 
                updateUI(); 
                setInterval(() => { 
                    // [新增] 只有在没有编辑、且没有输入命令时才刷新UI
                    if (!editingId && !isTyping) updateUI(); 
                }, 3000); 
            }

            async function addBot() { await fetch('/api/bots', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({})}); updateUI(); }
            
            async function toggleEdit(id) {
                if (editingId === id) { 
                    await saveConf(id); 
                    editingId = null; 
                    updateUI(); 
                } else { 
                    editingId = id; 
                    document.getElementById('btn-'+id).innerText = "💾 保存配置";
                    document.querySelectorAll('.in-'+id).forEach(i => i.classList.remove('opacity-40','pointer-events-none')); 
                }
            }

            async function saveConf(id) {
                const data = {
                    username: document.getElementById('n-'+id).value, host: document.getElementById('h-'+id).value,
                    pterodactyl: { url: document.getElementById('u-'+id).value, id: document.getElementById('s-'+id).value, key: document.getElementById('k-'+id).value },
                    monitor: { enabled: document.getElementById('m-'+id).checked, interval: document.getElementById('i-'+id).value }
                };
                await fetch('/api/bots/'+id+'/config', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
            }

            async function updateUI() {
                const r = await fetch('/api/bots'); const d = await r.json();
                document.getElementById('list').innerHTML = d.bots.map(b => `
                    <div class="glass border border-white/5">
                        <div class="flex justify-between items-start mb-6">
                            <div>
                                <input id="n-${b.id}" value="${b.username}" class="in-${b.id} opacity-40 pointer-events-none bg-transparent text-xl font-black italic border-none h-auto w-40 p-0">
                                <br><input id="h-${b.id}" value="${b.host}" class="in-${b.id} opacity-40 pointer-events-none bg-transparent text-[10px] text-slate-500 border-none h-auto w-40 p-0">
                            </div>
                            <button id="btn-${b.id}" onclick="toggleEdit('${b.id}')" class="text-xs bg-slate-800 px-4 py-1 rounded-lg">配置</button>
                        </div>
                        <div class="grid grid-cols-2 gap-3 mb-4">
                             <input id="u-${b.id}" value="${b.settings.pterodactyl.url}" class="in-${b.id} opacity-40 pointer-events-none" placeholder="面板URL">
                             <input id="s-${b.id}" value="${b.settings.pterodactyl.id}" class="in-${b.id} opacity-40 pointer-events-none" placeholder="ID">
                             <input id="k-${b.id}" type="password" value="${b.settings.pterodactyl.key}" class="in-${b.id} opacity-40 pointer-events-none col-span-2" placeholder="API Key">
                        </div>
                        <div class="flex items-center gap-4 mb-4 p-3 bg-blue-500/5 rounded-xl text-xs font-bold">
                            <label class="flex items-center gap-2"><input type="checkbox" id="m-${b.id}" ${b.settings.monitor.enabled?'checked':''} class="in-${b.id} opacity-40 pointer-events-none">自动保活</label>
                            <input id="i-${b.id}" type="number" value="${b.settings.monitor.interval}" class="w-16 h-8 in-${b.id} opacity-40 pointer-events-none text-center">秒
                        </div>
                        <div class="flex gap-2 mb-4">
                             <input id="cmd-${b.id}" class="flex-1" placeholder="发送控制台命令..." 
                                    onfocus="isTyping=true" onblur="isTyping=false">
                             <button onclick="sendCmd('${b.id}')" class="bg-slate-800 px-4 rounded-xl text-xs font-bold hover:bg-slate-700">发送</button>
                        </div>
                        <div class="log-box mb-6">${b.logs.map(l => `<div class="mb-1 border-b border-white/5 pb-1"><span class="opacity-30 mr-2">${l.time}</span><span class="${l.color}">${l.msg}</span></div>`).join('')}</div>
                        <div class="flex gap-3">
                             <button onclick="pwr('${b.id}','start')" class="flex-1 bg-emerald-600/20 text-emerald-400 py-3 rounded-xl font-bold hover:bg-emerald-600 hover:text-white transition">开机</button>
                             <button onclick="pwr('${b.id}','restart')" class="flex-1 bg-blue-600/20 text-blue-400 py-3 rounded-xl font-bold hover:bg-blue-600 hover:text-white transition">重启</button>
                             <button onclick="deleteBot('${b.id}')" class="bg-red-900/10 text-red-500/50 px-4 py-3 rounded-xl font-bold hover:bg-red-600 hover:text-white">删除</button>
                        </div>
                    </div>
                `).join('');
            }

            async function pwr(id, signal) { await fetch('/api/bots/'+id+'/power', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({signal})}); updateUI(); }
            
            async function sendCmd(id) { 
                const cmd = document.getElementById('cmd-'+id).value; 
                if(!cmd) return; 
                isTyping = false; // 发送后允许刷新
                await fetch('/api/bots/'+id+'/command', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({command:cmd})}); 
                updateUI(); 
            }

            async function deleteBot(bid) { if(confirm('删除监控？')) { await fetch('/api/bots/'+bid, {method:'DELETE'}); updateUI(); } }
        </script>
    </body>
    </html>
    """

if __name__ == "__main__":
    apply_silent_mode()
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("SERVER_PORT", 10297)), log_level="critical", access_log=False)
