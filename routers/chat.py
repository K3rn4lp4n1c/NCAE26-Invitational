import asyncio
from collections import defaultdict
from typing import Dict, List

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

router = APIRouter()

# room_id -> list of connected Websocket clients
rooms: Dict[str, List[WebSocket]] = defaultdict(list)

# Stored message history
message_history: Dict[str, List[str]] = defaultdict(list)

### Helpers ###
async def broadcast(room_id: str, message: str, exclude: WebSocket = None):
    dead = []
    for ws in rooms[room_id]:
        if ws is exclude:
            continue
        try:
            await ws.send_text(message)
        except Exception:
            dead.append(ws)

    for ws in dead:
        rooms[room_id].remove(ws)


@router.websocket("/ws/chat/{room_id}")
async def chat_room(websocket: WebSocket, room_id: str):
    await websocket.accept()

    rooms[room_id].append(websocket)

    for old_msg in message_history[room_id]:
        await websocket.send_text(old_msg)

    try:
        while True:
            data = await websocket.receive_text()

            message_history[room_id].append(data)
            await broadcast(room_id, data)

    except WebSocketDisconnect:
        rooms[room_id].remove(websocket)
        await broadcast(room_id, f"[system] A user left room {room_id}")

@router.websocket("/ws/admin/diag")
async def admin_diag(websocket: WebSocket):
    await websocket.accept()
    await websocket.send_text("[diag] disabled for security")
    await websocket.close()


