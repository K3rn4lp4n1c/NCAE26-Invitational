from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from jose import jwt # type: ignore
import urllib.request
import urllib.parse
import socket
import ipaddress
import os

router = APIRouter()

class LinkAccountRequest(BaseModel):
    bank_url: str

def get_user_from_token(authorization: str):
    token = authorization.replace("Bearer ", "")
    return jwt.decode(token, os.getenv("JWT_SECRET"), algorithms=["HS256"])

@router.post("/link")
def link_external_account(req: LinkAccountRequest, authorization: str = Header(...)):
    user = get_user_from_token(authorization)
    parsed = urllib.parse.urlparse(req.bank_url)
    host = parsed.hostname or ""
    if parsed.scheme not in {"http", "https"}:
        raise HTTPException(status_code=400, detail="Unsupported URL scheme")
    if host in {"localhost"} or host.endswith(".local") or "." not in host:
        raise HTTPException(status_code=400, detail="Blocked destination")
    try:
        infos = socket.getaddrinfo(host, None)
        for info in infos:
            ip = ipaddress.ip_address(info[4][0])
            if (
                ip.is_loopback
                or ip.is_private
                or ip.is_link_local
                or ip.is_multicast
                or ip.is_reserved
            ):
                raise HTTPException(status_code=400, detail="Blocked destination")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid destination")

    try:
        with urllib.request.urlopen(req.bank_url, timeout=5) as resp:
            content = resp.read().decode(errors="replace")
            return {"status": "fetched", "content": content}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
