import asyncio, json, subprocess, sys, time
from pathlib import Path
import websockets

async def main():
    root = Path(__file__).resolve().parent
    proc=subprocess.Popen([sys.executable,'MAANServer/server.py'], cwd=str(root), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    await asyncio.sleep(1)
    ui=await asyncio.open_connection('127.0.0.1',8766)
    ui_r,ui_w=ui
    ws=await websockets.connect('ws://127.0.0.1:8765')
    await ws.send(json.dumps({'type':'hello','app':'MAAN','version':2,'device':'TEST_DEVICE'}))
    pair=json.loads(await ws.recv()); assert pair['type']=='pair_request'
    code=pair['code']
    ws2=await websockets.connect('ws://127.0.0.1:8765')
    await ws2.send(json.dumps({'type':'pair_confirm','code':code,'device':'TEST_DEVICE'}))
    complete=json.loads(await ws2.recv()); assert complete['type']=='pair_complete'
    # target socket gets token and can register
    complete2=json.loads(await ws.recv()); assert complete2['type']=='pair_complete'
    await ws.send(json.dumps({'type':'register_control'}))
    await ws.send(json.dumps({'type':'incoming_call','call_id':'c1','name':'Test','number':'+91 1'}))
    line=await ui_r.readline();
    while line and json.loads(line)['type']!='incoming_call': line=await ui_r.readline()
    assert json.loads(line)['call_id']=='c1'
    ui_w.write((json.dumps({'type':'notifier_action','action':'answer_call','call_id':'c1'})+'\n').encode()); await ui_w.drain()
    cmd=json.loads(await ws.recv())
    if cmd.get('type') == 'control_registered': cmd=json.loads(await ws.recv())
    assert cmd['type']=='answer_call'
    print('PROTOCOL TEST PASSED')
    ui_w.close(); await ui_w.wait_closed(); await ws.close(); await ws2.close(); proc.terminate(); proc.wait(timeout=3)

asyncio.run(main())
