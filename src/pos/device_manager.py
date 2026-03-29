from __future__ import annotations

import argparse
from pathlib import Path

from .store import Store


def _load_store() -> Store:
    root = Path(__file__).resolve().parents[2]
    return Store(str(root / "data" / "pos_data.db"))


def authorize_device(username: str, device_id: str) -> None:
    store = _load_store()
    data = store.get_data()
    user = next((row for row in data["users"] if row["username"] == username), None)
    if not user:
        raise SystemExit(f"User not found: {username}")

    allowed = user.setdefault("allowed_devices", [])
    if device_id not in allowed:
        allowed.append(device_id)
        store.save_data(data)

    print(f"Authorized device '{device_id}' for '{username}'")
    print("Allowed devices:")
    for item in user["allowed_devices"]:
        print(f"- {item}")


def list_devices(username: str) -> None:
    store = _load_store()
    data = store.get_data()
    user = next((row for row in data["users"] if row["username"] == username), None)
    if not user:
        raise SystemExit(f"User not found: {username}")

    print(f"Allowed devices for '{username}':")
    for item in user.get("allowed_devices", []):
        print(f"- {item}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage allowed POS devices for users.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    authorize_parser = subparsers.add_parser("authorize", help="Authorize a new device for a user")
    authorize_parser.add_argument("username")
    authorize_parser.add_argument("device_id")

    list_parser = subparsers.add_parser("list", help="List allowed devices for a user")
    list_parser.add_argument("username")

    args = parser.parse_args()

    if args.command == "authorize":
        authorize_device(args.username, args.device_id)
        return

    if args.command == "list":
        list_devices(args.username)


if __name__ == "__main__":
    main()
