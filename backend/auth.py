"""Email+password auth: pbkdf2 hashing (stdlib) + an opaque bearer token stored
on the user row. ponytail: backend-issued token, no JWT lib, one session per
user. The Firebase drop-in point is `current_user` — swap the DB token lookup
for Firebase ID-token verification (verify the ID token, upsert the user by uid)
and no endpoint changes. Add a sessions table if multi-device login matters.
"""
import hashlib
import hmac
import secrets

from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from db import get_db
from models import User

_ITER = 200_000  # ponytail: pbkdf2 rounds; bump as hardware gets faster.


def hash_password(pw: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, _ITER)
    return f"{salt.hex()}:{dk.hex()}"


def verify_password(pw: str, stored: str) -> bool:
    try:
        salt_hex, dk_hex = stored.split(":")
    except ValueError:
        return False
    dk = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt_hex), _ITER)
    return hmac.compare_digest(dk.hex(), dk_hex)  # constant-time compare


def new_token() -> str:
    return secrets.token_urlsafe(32)


def current_user(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> User:
    """FastAPI dependency: resolve the request's user from `Authorization: Bearer`.
    401 on missing/invalid token."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    user = db.scalar(select(User).where(User.token == authorization[7:]))
    if not user:
        raise HTTPException(401, "invalid token")
    return user


if __name__ == "__main__":
    h = hash_password("hunter2")
    assert verify_password("hunter2", h)
    assert not verify_password("wrong", h)
    assert not verify_password("hunter2", "garbage")  # malformed stored hash
    assert h != hash_password("hunter2")  # unique salt per call
    assert len(new_token()) >= 20
    print("auth self-check ok")
