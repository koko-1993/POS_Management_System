from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import re
import secrets
import struct
import time
from urllib.parse import quote
from typing import Any

_SECRET = os.getenv("POS_SECRET_KEY", "shwe-htoo-thit-default-secret-change-me").encode("utf-8")


def admin_2fa_enabled() -> bool:
    return os.getenv("POS_ENABLE_ADMIN_2FA", "0").strip().lower() in {"1", "true", "yes", "on"}


def _derive_key(context: bytes = b"") -> bytes:
    return hashlib.sha256(_SECRET + context).digest()


def hash_password(password: str, iterations: int = 120_000) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return f"pbkdf2_sha256${iterations}${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def verify_password(password: str, password_hash: str) -> bool:
    try:
        algo, raw_iter, raw_salt, raw_digest = password_hash.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        iterations = int(raw_iter)
        salt = base64.urlsafe_b64decode(raw_salt.encode())
        expected = base64.urlsafe_b64decode(raw_digest.encode())
    except Exception:
        return False

    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected)


def validate_password_strength(password: str) -> tuple[bool, str]:
    if len(password) < 10:
        return False, "Password must be at least 10 characters"
    if not re.search(r"[A-Z]", password):
        return False, "Password must include an uppercase letter"
    if not re.search(r"[a-z]", password):
        return False, "Password must include a lowercase letter"
    if not re.search(r"\d", password):
        return False, "Password must include a number"
    if not re.search(r"[^A-Za-z0-9]", password):
        return False, "Password must include a special character"
    return True, "ok"


def generate_2fa_secret() -> str:
    return base64.b32encode(secrets.token_bytes(10)).decode("utf-8").rstrip("=")


def _totp(secret: str, for_time: int | None = None, step: int = 30, digits: int = 6) -> str:
    if for_time is None:
        for_time = int(time.time())
    counter = int(for_time // step)
    key = base64.b32decode(secret.upper() + "=" * ((8 - len(secret) % 8) % 8))
    msg = struct.pack(">Q", counter)
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % (10**digits)
    return str(code).zfill(digits)


def verify_2fa(secret: str, otp_code: str, window: int = 1) -> bool:
    now = int(time.time())
    for delta in range(-window, window + 1):
        if _totp(secret, now + (delta * 30)) == str(otp_code).strip():
            return True
    return False


def current_2fa_code(secret: str) -> str:
    return _totp(secret)


def build_otpauth_uri(secret: str, account_name: str, issuer: str = "Shwe Htoo Thit POS") -> str:
    label = quote(f"{issuer}:{account_name}")
    issuer_param = quote(issuer)
    secret_param = quote(secret)
    return f"otpauth://totp/{label}?secret={secret_param}&issuer={issuer_param}&algorithm=SHA1&digits=6&period=30"


def encrypt_text(value: str) -> str:
    if value == "":
        return value
    if str(value).startswith("enc:v1:"):
        return value

    plain = str(value).encode("utf-8")
    nonce = secrets.token_bytes(12)
    key = _derive_key(nonce)
    cipher = bytes(b ^ key[i % len(key)] for i, b in enumerate(plain))
    mac = hmac.new(_derive_key(b"mac"), nonce + cipher, hashlib.sha256).digest()[:16]
    payload = base64.urlsafe_b64encode(nonce + cipher + mac).decode("utf-8")
    return f"enc:v1:{payload}"


def decrypt_text(value: str) -> str:
    text = str(value)
    if not text.startswith("enc:v1:"):
        return text

    raw = base64.urlsafe_b64decode(text.split(":", 2)[2].encode("utf-8"))
    nonce = raw[:12]
    body = raw[12:-16]
    mac = raw[-16:]

    expected = hmac.new(_derive_key(b"mac"), nonce + body, hashlib.sha256).digest()[:16]
    if not hmac.compare_digest(mac, expected):
        raise ValueError("Encrypted field integrity check failed")

    key = _derive_key(nonce)
    plain = bytes(b ^ key[i % len(key)] for i, b in enumerate(body))
    return plain.decode("utf-8")


def stable_hash(payload: Any) -> str:
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def chained_record_hash(previous_hash: str, payload: Any) -> str:
    message = f"{previous_hash}|{stable_hash(payload)}".encode("utf-8")
    return hmac.new(_derive_key(b"chain"), message, hashlib.sha256).hexdigest()
