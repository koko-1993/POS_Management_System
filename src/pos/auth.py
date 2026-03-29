from __future__ import annotations

from typing import Any

from .security import generate_2fa_secret, hash_password, validate_password_strength, verify_2fa, verify_password
from .store import Store


class AuthService:
    def __init__(self, store: Store):
        self.store = store

    def login(
        self,
        username: str,
        password: str,
        otp_code: str = "",
        device_id: str = "",
    ) -> dict[str, Any]:
        data = self.store.get_data()
        user = next((u for u in data["users"] if u["username"] == username), None)
        if not user:
            raise ValueError("Invalid username or password")

        if not user.get("active", True):
            raise ValueError("Account is inactive")

        if not verify_password(password, user.get("password_hash", "")):
            raise ValueError("Invalid username or password")

        allowed_devices = user.get("allowed_devices", [])
        if allowed_devices and device_id not in allowed_devices:
            raise ValueError("Unauthorized POS device")

        if user.get("require_2fa"):
            if not otp_code:
                raise ValueError("2FA code required")
            if not verify_2fa(user.get("otp_secret", ""), otp_code):
                raise ValueError("Invalid 2FA code")

        return user

    @staticmethod
    def _normalize_username(username: str) -> str:
        return str(username).strip()

    @staticmethod
    def _serialize_user(user: dict[str, Any]) -> dict[str, Any]:
        return {
            "username": user.get("username", ""),
            "full_name": user.get("full_name", ""),
            "role": user.get("role", ""),
            "team_code": user.get("team_code", ""),
            "active": bool(user.get("active", True)),
            "require_2fa": bool(user.get("require_2fa", False)),
            "allowed_devices": [str(item).strip() for item in user.get("allowed_devices", []) if str(item).strip()],
        }

    def list_users(self) -> list[dict[str, Any]]:
        data = self.store.get_data()
        return [self._serialize_user(user) for user in data.get("users", [])]

    def _validate_team_code(self, data: dict[str, Any], role: str, team_code: str) -> str:
        normalized = str(team_code).strip().upper()
        if role != "sales_staff":
            return ""
        if not normalized:
            raise ValueError("Sales account must be assigned to a sale team")
        available_codes = {
            str(team.get("code", "")).strip().upper()
            for team in data.get("teams", [])
            if str(team.get("code", "")).strip()
        }
        if normalized not in available_codes:
            raise ValueError(f"Unknown sale team: {normalized}")
        return normalized

    @staticmethod
    def _normalize_allowed_devices(allowed_devices: Any) -> list[str]:
        if not isinstance(allowed_devices, list):
            return []
        result: list[str] = []
        seen: set[str] = set()
        for item in allowed_devices:
            device = str(item).strip().upper()
            if device and device not in seen:
                result.append(device)
                seen.add(device)
        return result

    def create_user(
        self,
        username: str,
        password: str,
        role: str,
        full_name: str = "",
        team_code: str = "",
        allowed_devices: Any = None,
        active: bool = True,
    ) -> dict[str, Any]:
        if role != "sales_staff":
            raise ValueError("Only sales accounts can be created here")
        self.validate_new_password(password)
        data = self.store.get_data()
        normalized_username = self._normalize_username(username)
        if not normalized_username:
            raise ValueError("Username is required")
        if any(self._normalize_username(user.get("username", "")) == normalized_username for user in data.get("users", [])):
            raise ValueError("Username already exists")
        normalized_team_code = self._validate_team_code(data, role, team_code)
        user = {
            "username": normalized_username,
            "full_name": str(full_name).strip() or normalized_username,
            "role": role,
            "password_hash": hash_password(password),
            "must_change_password": True,
            "require_2fa": False,
            "allowed_devices": self._normalize_allowed_devices(allowed_devices),
            "team_code": normalized_team_code,
            "active": bool(active),
        }
        data["users"].append(user)
        self.store.save_data(data)
        return self._serialize_user(user)

    def update_user(self, username: str, payload: dict[str, Any]) -> dict[str, Any]:
        data = self.store.get_data()
        normalized_username = self._normalize_username(username)
        user = next((item for item in data.get("users", []) if self._normalize_username(item.get("username", "")) == normalized_username), None)
        if not user:
            raise ValueError("User not found")
        if user.get("role") != "sales_staff":
            raise ValueError("Only sales accounts can be managed here")

        if "full_name" in payload:
            user["full_name"] = str(payload.get("full_name", "")).strip() or normalized_username
        if "team_code" in payload:
            user["team_code"] = self._validate_team_code(data, user.get("role", ""), payload.get("team_code", ""))
        if "allowed_devices" in payload:
            user["allowed_devices"] = self._normalize_allowed_devices(payload.get("allowed_devices"))
        if "active" in payload:
            user["active"] = bool(payload.get("active"))
        if "password" in payload and str(payload.get("password", "")):
            self.validate_new_password(str(payload.get("password", "")))
            user["password_hash"] = hash_password(str(payload.get("password", "")))
            user["must_change_password"] = True

        self.store.save_data(data)
        return self._serialize_user(user)

    def delete_user(self, username: str) -> None:
        data = self.store.get_data()
        normalized_username = self._normalize_username(username)
        index = next(
            (
                idx
                for idx, user in enumerate(data.get("users", []))
                if self._normalize_username(user.get("username", "")) == normalized_username
            ),
            None,
        )
        if index is None:
            raise ValueError("User not found")
        if data["users"][index].get("role") != "sales_staff":
            raise ValueError("Only sales accounts can be deleted here")
        data["users"].pop(index)
        self.store.save_data(data)

    @staticmethod
    def has_role(user: dict[str, Any], role: str) -> bool:
        return user.get("role") == role

    @staticmethod
    def validate_new_password(password: str) -> None:
        ok, reason = validate_password_strength(password)
        if not ok:
            raise ValueError(reason)

    def change_password(self, username: str, current_password: str, new_password: str) -> None:
        self.validate_new_password(new_password)
        data = self.store.get_data()
        user = next((u for u in data["users"] if u["username"] == username), None)
        if not user:
            raise ValueError("User not found")
        if not verify_password(current_password, user.get("password_hash", "")):
            raise ValueError("Current password is incorrect")
        user["password_hash"] = hash_password(new_password)
        user["must_change_password"] = False
        self.store.save_data(data)
