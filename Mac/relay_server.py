#!/usr/bin/env python3
"""Optional MAAN internet relay.

Deploy this on a server with a public WSS endpoint. Both the Mac companion and
Android client can be extended to connect to /relay/<trusted-token>. This file
is intentionally separate from the LAN server so the LAN path remains simple.
It does not store call contents; it only forwards frames between two peers.
"""
import asyncio, sys
import websockets

peers = {}
async def relay(ws):
    path = ws.request.path
    token = path.rsplit('/',1)[-1]
    if not token or len(token) < 16:
        await ws.close(code=1008, reason='invalid token'); return
    bucket = peers.setdefault(token, set()); bucket.add(ws)
    try:
        async for message in ws:
            for peer in list(bucket):
                if peer is not ws:
                    try: await peer.send(message)
                    except Exception: bucket.discard(peer)
    finally:
        bucket.discard(ws)
        if not bucket: peers.pop(token, None)

async def main():
    port=int(sys.argv[1]) if len(sys.argv)>1 else 4433
    async with websockets.serve(relay,'0.0.0.0',port,max_size=16*1024*1024):
        print(f'MAAN relay listening on {port}',flush=True)
        await asyncio.Future()

asyncio.run(main())
