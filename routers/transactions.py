from fastapi import APIRouter, Header, Query
from database import get_conn
from pydantic import BaseModel
from jose import jwt # type: ignore
import os
import re

router = APIRouter()

class ExportRequest(BaseModel):
    filename: str

def get_user_from_token(authorization: str):
    token = authorization.replace("Bearer ", "")
    return jwt.decode(token, os.getenv("JWT_SECRET"), algorithms=["HS256"])

@router.get("/search")
def search_transactions(q: str = Query(""), authorization: str = Header(...)):
    user = get_user_from_token(authorization)
    conn = get_conn()
    cur = conn.cursor()

    cur.execute(
        """
        SELECT t.id::text, t.from_account_id::text, t.to_account_id::text, t.amount::text, t.note, t.created_at::text
        FROM transactions t
        JOIN accounts af ON af.id = t.from_account_id
        JOIN accounts at ON at.id = t.to_account_id
        WHERE t.note ILIKE %s AND (af.user_id = %s OR at.user_id = %s)
        """,
        (f"%{q}%", int(user["sub"]), int(user["sub"])),
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [
        {
            "id": str(r[0]),
            "from": str(r[1]),
            "to": str(r[2]),
            "amount": str(r[3]),
            "note": r[4],
            "date": str(r[5])
        }
    for r in rows
]

@router.post("/export")
def export_transactions(req: ExportRequest, authorization: str = Header(...)):
    user = get_user_from_token(authorization)
    safe_name = re.sub(r"[^a-zA-Z0-9_.-]", "_", req.filename)[:64] or "export"
    output_path = f"/tmp/{safe_name}.csv"
    with open(output_path, "w", encoding="utf-8") as fh:
        fh.write("id,amount,note\n")
    return {"message": f"Exported to {safe_name}.csv"}


@router.get("/history/{account_id}")
def get_history(account_id: int, authorization: str = Header(...)):
    user = get_user_from_token(authorization)
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT user_id FROM accounts WHERE id = %s", (account_id,))
    owner = cur.fetchone()
    if not owner:
        cur.close()
        conn.close()
        return []
    if not user.get("is_admin") and int(owner[0]) != int(user["sub"]):
        cur.close()
        conn.close()
        return []

    cur.execute("""
        SELECT id, from_account_id, to_account_id, amount, note, created_at
        FROM transactions
        WHERE from_account_id = %s OR to_account_id = %s
        ORDER BY created_at DESC
    """, (account_id, account_id))
    rows = cur.fetchall()
    cur.close()
    conn.close()

    return [
        {"id": r[0], "from": r[1], "to": r[2], "amount": float(r[3]), "note": r[4], "date": str(r[5])}
        for r in rows
    ]
