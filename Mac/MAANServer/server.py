#!/usr/bin/env python3
"""MAAN Mac transport server.

Local transport: WebSocket :8765
Popup/UI control: newline-delimited JSON TCP :8766
Discovery beacon: UDP :8767 and Bonjour _maan._tcp.

This server deliberately keeps the LAN transport separate from the UI socket.
A production internet deployment should put a mutually authenticated relay in
front of the WebSocket endpoint rather than exposing port 8765 directly.
"""
import asyncio, base64, json, os, re, socket, subprocess, time, uuid
from pathlib import Path
import websockets

ROOT = Path(__file__).resolve().parents[1]
UI_HOST, UI_PORT = "127.0.0.1", 8766
WS_PORT, BEACON_PORT = 8765, 8767
SERVICE_TYPE = "_maan._tcp."
BEACON_MAGIC = "MAAN_BEACON_V1"
DOWNLOAD_DIR = Path.home() / "Downloads" / "MAAN"
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

android_clients = set()
android_control = None
ui_clients = set()
pending_calls = []
active_call = None
transfers = {}
TRUST_FILE = Path.home() / ".maan_trusted_devices.json"
trusted = json.loads(TRUST_FILE.read_text()) if TRUST_FILE.exists() else {}
pair_requests = {}
authorized_sockets = set()


def log(msg): print(f"[MAAN] {msg}", flush=True)

def save_trusted():
    TRUST_FILE.write_text(json.dumps(trusted, indent=2))

async def ui_send(payload):
    dead = []
    data = (json.dumps(payload, ensure_ascii=False) + "\n").encode()
    for w in list(ui_clients):
        try:
            w.write(data); await w.drain()
        except Exception: dead.append(w)
    for w in dead:
        ui_clients.discard(w)

async def android_send(payload):
    global android_control
    if android_control is None:
        return False
    try:
        await android_control.send(json.dumps(payload, ensure_ascii=False))
        return True
    except Exception:
        android_control = None
        return False

async def handle_android(ws):
    global android_control, active_call
    android_clients.add(ws)
    peer = ws.remote_address
    log(f"Android connected: {peer}")
    authorized = False
    device_id = None
    try:
        async for raw in ws:
            try: data = json.loads(raw)
            except Exception: continue
            kind = data.get("type")
            if kind == "hello":
                device_id = data.get("device") or str(peer)
                token = data.get("token")
                if token and trusted.get(device_id) == token:
                    authorized = True
                    await ws.send(json.dumps({"type":"hello_response","app":"MAAN","version":2,"trusted":True}))
                else:
                    code = f"{__import__('random').randint(0,999999):06d}"
                    pair_requests[code] = {"ws": ws, "device": device_id, "created": time.time()}
                    await ws.send(json.dumps({"type":"pair_request","code":code,"device":device_id}))
                    await ui_send({"type":"pair_request","code":code,"device":device_id})
                continue
            if kind == "pair_confirm":
                code = str(data.get("code") or "")
                req = pair_requests.pop(code, None)
                if req and time.time() - req["created"] < 300:
                    token = uuid.uuid4().hex
                    trusted[req["device"]] = token; save_trusted()
                    target = req["ws"]
                    message = json.dumps({"type":"pair_complete","token":token})
                    try: await target.send(message)
                    except Exception: pass
                    if ws is not target:
                        try: await ws.send(message)
                        except Exception: pass
                    authorized = True
                    authorized_sockets.add(target)
                    global android_control
                    android_control = target
                    if target in android_clients:
                        # target is the long-lived socket; it can now be used immediately.
                        pass
                continue
            if not authorized and ws not in authorized_sockets:
                continue
            if kind == "register_control":
                android_control = ws
                await ws.send(json.dumps({"type":"control_registered"}))
            elif kind == "incoming_call":
                active_call = {"call_id": data.get("call_id") or f"call-{int(time.time()*1000)}", "name": data.get("name") or "Unknown Caller", "number": data.get("number") or "Unknown Number"}
                await ui_send({"type":"incoming_call", **active_call})
            elif kind == "call_state":
                state = data.get("state", "ENDED")
                await ui_send({"type":"call_state", "call_id": data.get("call_id"), "state": state})
                if state in {"ANSWERED", "REJECTED", "ENDED", "MISSED"}: active_call = None
            elif kind == "call_control_result":
                await ui_send(data)
            elif kind == "screen_frame":
                await ui_send(data)
            elif kind in {"file_drag_candidate", "file_drag_result", "file_drag_chunk", "file_drag_end"}:
                await ui_send(data)
            elif kind == "file_chunk":
                await receive_file_chunk(data)
            elif kind == "file_end":
                await finish_file(data)
            elif kind in {"clipboard_text", "clipboard_image"}:
                await ui_send(data)
    finally:
        authorized_sockets.discard(ws)
        android_clients.discard(ws)
        if android_control is ws: android_control = None
        log(f"Android disconnected: {peer}")

async def receive_file_chunk(data):
    tid = data.get("transfer_id")
    if not tid: return
    name = os.path.basename(data.get("name") or "file.bin")
    target = DOWNLOAD_DIR / name
    state = transfers.get(tid)
    if state is None:
        state = {"path": target, "size": 0}
        transfers[tid] = state
        target.write_bytes(b"")
    chunk = base64.b64decode(data.get("data", ""))
    with target.open("r+b") as f:
        f.seek(int(data.get("offset", state["size"])))
        f.write(chunk)
    state["size"] = max(state["size"], int(data.get("offset", state["size"])) + len(chunk))
    await ui_send({"type":"file_progress","transfer_id":tid,"name":name,"bytes":state["size"]})

async def finish_file(data):
    tid = data.get("transfer_id")
    state = transfers.pop(tid, None)
    if state: await ui_send({"type":"file_received","transfer_id":tid,"name":state["path"].name,"path":str(state["path"]),"bytes":state["size"]})

async def approve_pair(code):
    req = pair_requests.pop(str(code), None)
    if not req or time.time() - req["created"] >= 300:
        await ui_send({"type":"pair_result", "success":False, "message":"Pairing code expired or invalid"})
        return
    token = uuid.uuid4().hex
    trusted[req["device"]] = token
    save_trusted()
    target = req["ws"]
    try:
        await target.send(json.dumps({"type":"pair_complete","token":token}))
    except Exception:
        pass
    authorized_sockets.add(target)
    global android_control
    android_control = target
    await ui_send({"type":"pair_result","success":True,"device":req["device"]})

async def handle_ui(reader, writer):
    ui_clients.add(writer)
    try:
        writer.write((json.dumps({"type":"ready","app":"MAAN"})+"\n").encode()); await writer.drain()
        if active_call: await ui_send({"type":"incoming_call", **active_call})
        while True:
            line = await reader.readline()
            if not line: break
            try: data=json.loads(line)
            except Exception: continue
            kind=data.get("type")
            if kind == "pair_approve":
                await approve_pair(data.get("code", ""))
            elif kind == "notifier_action":
                action=data.get("action")
                if action in {"answer_call","reject_call"}:
                    await android_send({"type":action,"call_id":data.get("call_id") or (active_call or {}).get("call_id","")})
                elif action == "dismiss_call":
                    await ui_send({"type":"dismiss_call","call_id":data.get("call_id")})
            elif kind == "input_tap":
                await android_send(data)
            elif kind == "input_swipe":
                await android_send(data)
            elif kind in {"file_drag_probe", "file_drag_commit", "file_drag_pull", "open_file_bridge"}:
                await android_send(data)
            elif kind in {"clipboard_text", "clipboard_image", "file_chunk", "file_end"}:
                await android_send(data)
    finally:
        ui_clients.discard(writer); writer.close(); await writer.wait_closed()

async def beacon_loop():
    payload=f"{BEACON_MAGIC}|{WS_PORT}|version=2".encode()
    sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM,socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1); sock.setblocking(False)
    try:
        while True:
            for b in broadcast_addresses():
                try: sock.sendto(payload,(b,BEACON_PORT))
                except OSError: pass
            await asyncio.sleep(1)
    finally: sock.close()

def broadcast_addresses():
    out={"255.255.255.255"}
    try: text=subprocess.check_output(["ifconfig"],text=True,stderr=subprocess.DEVNULL)
    except Exception: return out
    for line in text.splitlines():
        m=re.search(r"\binet (\d+\.\d+\.\d+\.\d+).*?broadcast (\d+\.\d+\.\d+\.\d+)",line)
        if m and not m.group(1).startswith(("127.","169.254.")): out.add(m.group(2))
    return out

def advertise():
    try:
        return subprocess.Popen(["dns-sd","-R","MAAN","_maan._tcp.","local.",str(WS_PORT),"version=2"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    except Exception: return None

async def main():
    bonjour=advertise()
    ws_server=await websockets.serve(handle_android,"0.0.0.0",WS_PORT,max_size=16*1024*1024,ping_interval=20,ping_timeout=20)
    ui_server=await asyncio.start_server(handle_ui,UI_HOST,UI_PORT)
    log(f"WebSocket :{WS_PORT}; UI :{UI_PORT}; beacon :{BEACON_PORT}")
    try:
        await beacon_loop()
    finally:
        ws_server.close(); await ws_server.wait_closed(); ui_server.close(); await ui_server.wait_closed()
        if bonjour:
            bonjour.terminate()

if __name__ == "__main__":
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
