import os
import time
import asyncio
import requests
import sys
import json
from typing import Dict
from datetime import datetime
from fastapi import FastAPI, Body
from fastapi.responses import HTMLResponse
import uvicorn

# --- [ 1. 静默与持久化配置 ] ---
DB_FILE = "database.json"

def apply_silent_mode():
    """彻底关闭终端输出，保持后台静默"""
    sys.stdout = open(os.devnull, 'w')
    sys.stderr = open(os.devnull, 'w')

def save_data():
    """将内存中的数据保存到 JSON 文件"""
    try:
        with open(DB_FILE, "w", encoding="utf-8") as f:
            json.dump(active_bots, f, ensure_ascii=False, indent=4)
    except:
        pass

def load_data():
    """从文件加载历史数据"""
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except:
            return {}
    return {}

app = FastAPI()
# [cite_start]初始化时载入数据 [cite: 1]
active_bots: Dict[str, dict] = load_data()

# --- [ 2. API 通讯核心 ] ---
def pto_api_call(bot, endpoint: str, method: str = "POST", data: dict = None):
    s = bot.get("settings", {}).get("pterodactyl", {})
    url = s.get("url", "").strip().rstrip("/")
    key = s.get("key", "").strip()
    sid = s.get("id", "").strip()

    if not all([url, key, sid]): return None, "配置不完整"

    target_url = f"{url}/api/client/servers/{sid}{endpoint}"
    headers = {
        "Authorization": f"Bearer {key}",
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": f"{url}/"
    }

    try:
        if method == "GET":
            response = requests.get(target_url, headers=headers, timeout=15)
        else:
            response = requests.post(target_url, json=data or {}, headers=headers, timeout=15)
        
        if response.status_code in [200, 204]:
            return response, None
        return None, f"API 错误: {response.status_code}"
    except Exception as e:
        return None, f"连接失败: {str(e)[:20]}"

# --- [ 3. 异步监控循环 ] ---
async def monitor_loop():
    while True:
        now_dt = datetime.now()
        now_str = now_dt.strftime("%H:%M:%S")
        now_hm = now_dt.strftime("%H:%M")
        has_changed = False

        for bid, bot in list(active_bots.items()):
            s = bot["settings"].get("pterodactyl", {})
            m = bot["settings"].get("monitor", {})

            if not all([s.get("url"), s.get("key"), s.get("id")]): continue
            if not m.get("enabled"): continue

            interval = max(int(m.get("interval", 10)), 5)
            if time.time() - bot["stats"].get("last_check_ts", 0) < interval: continue

            res, err = pto_api_call(bot, "/resources", "GET")
            bot["stats"]["last_check"] = now_str
            bot["stats"]["last_check_ts"] = time.time()
            has_changed = True

            if res:
                attr = res.json().get("attributes", {})
                current_state = attr.get("current_state", "unknown")
                bot["stats"]["state"] = current_state
                bot["stats"]["last_err"] = ""

                if current_state == "offline":
                    bot["logs"].insert(0, {"time": now_str, "msg": "🚨 离线触发自动启动...", "color": "text-red-400 font-bold"})
                    p_res, _ = pto_api_call(bot, "/power", "POST", {"signal": "start"})
                    if p_res:
                        bot["stats"]["restarts"] += 1
                        bot["logs"].insert(0, {"time": now_str, "msg": "✅ 自动启动成功", "color": "text-emerald-400"})

                sched_time = m.get("sched_restart")
                if sched_time == now_hm and not bot["stats"].get("did_sched_today"):
                    bot["logs"].insert(0, {"time": now_str, "msg": f"⏰ 定时重启触发", "color": "text-purple-400"})
                    pto_api_call(bot, "/power", "POST", {"signal": "restart"})
                    bot["stats"]["did_sched_today"] = True
                elif sched_time != now_hm:
                    bot["stats"]["did_sched_today"] = False
            else:
                bot["stats"]["state"] = "error"
                if bot["stats"].get("last_err") != err:
                    bot["logs"].insert(0, {"time": now_str, "msg": f"⚠️ {err}", "color": "text-yellow-500"})
                    bot["stats"]["last_err"] = err
            
            bot["logs"] = bot["logs"][:15] # 限制日志长度

        if has_changed:
            save_data()
        await asyncio.sleep(1)

# --- [ 4. FastAPI 路由 ] ---
@app.on_event("startup")
async def startup_event():
    asyncio.create_task(monitor_loop())

@app.get("/api/bots")
async def list_bots():
    return {"bots": list(active_bots.values())}

@app.post("/api/bots")
async def add_bot(data: dict = Body(...)):
    bid = f"bot_{os.urandom(2).hex()}"
    active_bots[bid] = {
        "id": bid, "username": data.get('username', '新实例'), "host": data.get('host', '未知'),
        "logs": [], 
        "stats": {"state": "unknown", "restarts": 0, "last_check": "从未", "last_check_ts": 0, "last_err": ""},
        "settings": {
            "pterodactyl": {"url": "", "key": "", "id": ""},
            "monitor": {"enabled": True, "interval": 10, "sched_restart": ""}
        }
    }
    save_data()
    return {"success": True}

@app.post("/api/bots/{bid}/config")
async def update_config(bid: str, data: dict = Body(...)):
    if bid in active_bots:
        active_bots[bid]["settings"] = data
        save_data()
        return {"success": True}
    return {"success": False}

@app.post("/api/bots/{bid}/power")
async def power_control(bid: str, data: dict = Body(...)):
    bot = active_bots.get(bid)
    if bot:
        sig = data.get("signal")
        pto_api_call(bot, "/power", "POST", data={"signal": sig})
        bot["logs"].insert(0, {"time": time.strftime("%H:%M:%S"), "msg": f"🕹️ 手动指令: {sig.upper()}", "color": "text-blue-400"})
        save_data()
    return {"success": True}

@app.delete("/api/bots/{bid}")
async def delete_bot(bid: str):
    if bid in active_bots:
        del active_bots[bid]
        save_data()
        return {"success": True}
    return {"success": False}

# --- [ 5. UI 界面 ] ---
@app.get("/", response_class=HTMLResponse)
async def index():
    return """
    <!DOCTYPE html>
    <html class="dark">
    <head>
        <meta charset="utf-8"><title>Toffee Pro - 监控管理面板</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            body { background: #020617; color: #f8fafc; font-family: system-ui, sans-serif; }
            .glass { background: #0f172a; border: 1px solid rgba(255,255,255,0.05); border-radius: 20px; transition: 0.3s; }
            .log-box { background: #000; border-radius: 12px; height: 160px; overflow-y: auto; font-family: monospace; font-size: 11px; padding: 12px; border: 1px solid #1e293b; }
            input { background: #020617; border: 1px solid #1e293b; padding: 6px 10px; border-radius: 8px; font-size: 12px; color: white; }
            .status-tag { padding: 2px 8px; border-radius: 6px; font-size: 10px; font-weight: bold; text-transform: uppercase; }
            .state-running { background: rgba(16, 185, 129, 0.2); color: #10b981; }
            .state-offline { background: rgba(239, 68, 68, 0.2); color: #ef4444; }
            .state-error { background: rgba(245, 158, 11, 0.2); color: #f59e0b; }
            .locked { opacity: 0.5; pointer-events: none; }
        </style>
    </head>
    <body class="p-6" onload="startSync()">
        <div class="max-w-5xl mx-auto">
            <header class="flex justify-between items-center mb-8">
                <div>
                    <h1 class="text-3xl font-black italic text-blue-500">TOFFEE PRO</h1>
                    <p class="text-[10px] text-slate-500 uppercase tracking-widest mt-1">持久化存储已启用</p>
                </div>
                <div class="glass p-3 flex gap-2">
                    <input id="new_h" placeholder="面板地址" class="w-32">
                    <input id="new_u" placeholder="项目名称" class="w-28">
                    <button onclick="addBot()" class="bg-blue-600 hover:bg-blue-500 px-4 py-2 rounded-xl font-bold text-xs transition">新增监控</button>
                </div>
            </header>
            <div id="list" class="grid grid-cols-1 md:grid-cols-2 gap-8"></div>
        </div>
        <script>
            let editingId = null; 
            function startSync() { updateUI(); setInterval(() => { if (!editingId) updateUI(); }, 3000); }
            async function addBot() {
                const h = document.getElementById('new_h').value;
                const u = document.getElementById('new_u').value;
                if(!h || !u) return;
                await fetch('/api/bots', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({host:h, username:u})});
                updateUI();
            }
            async function toggleEdit(id) {
                const btn = document.getElementById('btn-'+id);
                const inputs = document.querySelectorAll('.in-'+id);
                if (editingId === id) {
                    await saveConf(id); editingId = null; updateUI();
                } else {
                    editingId = id; btn.innerText = "💾 保存配置"; btn.className = "bg-blue-600 px-3 py-1 rounded text-[10px] font-bold";
                    inputs.forEach(i => i.classList.remove('locked'));
                }
            }
            async function saveConf(id) {
                const data = {
                    pterodactyl: { 
                        url: document.getElementById('u-'+id).value, 
                        id: document.getElementById('s-'+id).value, 
                        key: document.getElementById('k-'+id).value 
                    },
                    monitor: { 
                        enabled: document.getElementById('m-'+id).checked, 
                        interval: document.getElementById('i-'+id).value, 
                        sched_restart: document.getElementById('t-'+id).value 
                    }
                };
                await fetch('/api/bots/'+id+'/config', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data)});
            }
            async function updateUI() {
                const r = await fetch('/api/bots'); const d = await r.json();
                document.getElementById('list').innerHTML = d.bots.map(b => `
                    <div class="glass p-6 relative border border-white/5">
                        <div class="flex justify-between items-start mb-4">
                            <div><h2 class="text-xl font-bold">${b.username}</h2><p class="text-[10px] text-slate-500">${b.host}</p></div>
                            <div class="flex flex-col items-end gap-2">
                                <span class="status-tag state-${b.stats.state}">${b.stats.state}</span>
                                <button id="btn-${b.id}" onclick="toggleEdit('${b.id}')" class="text-[10px] bg-slate-800 px-3 py-1 rounded">配置参数</button>
                            </div>
                        </div>
                        <div class="grid grid-cols-2 gap-2 mb-4">
                             <input id="u-${b.id}" value="${b.settings.pterodactyl.url}" class="in-${b.id} locked" placeholder="面板URL">
                             <input id="s-${b.id}" value="${b.settings.pterodactyl.id}" class="in-${b.id} locked" placeholder="服务器ID">
                             <input id="k-${b.id}" type="password" value="${b.settings.pterodactyl.key}" class="in-${b.id} locked col-span-2" placeholder="API Key">
                        </div>
                        <div class="flex items-center gap-4 mb-4 p-2 bg-blue-500/5 rounded-lg border border-blue-500/10">
                            <label class="flex items-center gap-1 cursor-pointer"><input type="checkbox" id="m-${b.id}" ${b.settings.monitor.enabled?'checked':''} class="in-${b.id} locked"><span class="text-[10px] font-bold">自动保活</span></label>
                            <input id="i-${b.id}" type="number" value="${b.settings.monitor.interval}" class="w-12 h-6 in-${b.id} locked !p-1 text-center font-bold">
                            <input id="t-${b.id}" type="text" placeholder="定时重启(04:00)" value="${b.settings.monitor.sched_restart || ''}" class="w-24 h-6 in-${b.id} locked !p-1 text-center font-bold">
                        </div>
                        <div class="log-box mb-4">${b.logs.map(l => `<div class="mb-1 border-b border-white/5 pb-1"><span class="opacity-30 mr-2">${l.time}</span><span class="${l.color}">${l.msg}</span></div>`).join('')}</div>
                        <div class="flex gap-2">
                             <button onclick="pwr('${b.id}','start')" class="flex-1 bg-emerald-600/20 text-emerald-400 py-2 rounded-xl text-xs font-bold hover:bg-emerald-500/40">启动</button>
                             <button onclick="pwr('${b.id}','restart')" class="flex-1 bg-blue-600/20 text-blue-400 py-2 rounded-xl text-xs font-bold hover:bg-blue-500/40">重启</button>
                             <button onclick="deleteBot('${b.id}')" class="bg-slate-800 text-slate-500 px-3 py-2 rounded-xl text-xs font-bold">移除</button>
                        </div>
                    </div>
                `).join('');
            }
            async function pwr(id, signal) { await fetch('/api/bots/'+id+'/power', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({signal})}); updateUI(); }
            async function deleteBot(bid) { if(confirm('确定永久移除监控？')) { await fetch('/api/bots/'+bid, {method:'DELETE'}); updateUI(); } }
        </script>
    </body>
    </html>
    """

if __name__ == "__main__":
    apply_silent_mode()
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("SERVER_PORT", 4681)), log_level="critical")