from __future__ import annotations

import argparse
from pathlib import Path

from .security import admin_2fa_enabled, build_otpauth_uri, current_2fa_code
from .store import Store


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Show Google Authenticator setup details for a POS user."
    )
    parser.add_argument("username", nargs="?", default="admin", help="Username to inspect")
    parser.add_argument(
        "--issuer",
        default="Shwe Htoo Thit POS",
        help="Issuer label shown in authenticator apps",
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    store = Store(str(root / "data" / "pos_data.db"))
    data = store.get_data()
    user = next((row for row in data["users"] if row["username"] == args.username), None)

    if not user:
        raise SystemExit(f"User not found: {args.username}")

    if not user.get("require_2fa"):
        raise SystemExit(f"2FA is not enabled for user: {args.username}")

    if not admin_2fa_enabled():
        print("Note: admin 2FA is currently disabled by POS_ENABLE_ADMIN_2FA.")
        print("Set POS_ENABLE_ADMIN_2FA=1 in production before using this OTP setup.")

    secret = user.get("otp_secret", "")
    if not secret:
        raise SystemExit(f"OTP secret not found for user: {args.username}")

    print(f"Username: {user['username']}")
    print(f"Issuer: {args.issuer}")
    print(f"Secret: {secret}")
    print(f"otpauth URI: {build_otpauth_uri(secret, user['username'], args.issuer)}")
    print(f"Current code: {current_2fa_code(secret)}")


if __name__ == "__main__":
    main()
