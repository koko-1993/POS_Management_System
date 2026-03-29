import copy
import json
import secrets
import sqlite3
from pathlib import Path
from typing import Any

from .backup import BackupManager
from .security import decrypt_text, encrypt_text, generate_2fa_secret, hash_password

DEFAULT_TEAMS = [
    {
        "id": 1,
        "code": "TEAM001",
        "name": "Sale Team - 3 (THM)",
        "sales_man_name": "Ko THM",
        "position": "Sales Man",
        "phone": "091111111",
        "township": "သထုံ",
        "townships": ["သထုံ"],
        "item_targets": [],
    },
    {
        "id": 2,
        "code": "TEAM002",
        "name": "Sale Team - 3 (AHT)",
        "sales_man_name": "Ko AHT",
        "position": "Sales Man",
        "phone": "092222222",
        "township": "အောင်သာယာ",
        "townships": ["အောင်သာယာ"],
        "item_targets": [],
    },
    {
        "id": 3,
        "code": "TEAM003",
        "name": "Sale Team - 1 (YGN)",
        "sales_man_name": "Ko YGN",
        "position": "Sales Man",
        "phone": "093333333",
        "township": "ရန်ကုန်",
        "townships": ["ရန်ကုန်"],
        "item_targets": [],
    },
    {
        "id": 4,
        "code": "TEAM004",
        "name": "Sale Team - 2 (MLM)",
        "sales_man_name": "Ko MLM",
        "position": "Sales Man",
        "phone": "094444444",
        "township": "မော်လမြိုင်",
        "townships": ["မော်လမြိုင်"],
        "item_targets": [],
    },
]

YANGON_REGION_TOWNSHIPS = [
    "Ahlon Township",
    "Bahan Township",
    "Botataung Township",
    "Dagon Seikkan Township",
    "Dagon Township",
    "Dala Township",
    "Dawbon Township",
    "East Dagon Township",
    "Hlaing Township",
    "Hlaingthaya East Township",
    "Hlaingthaya Township",
    "Insein Township",
    "Kamayut Township",
    "Kyauktada Township",
    "Kyimyindaing Township",
    "Lanmadaw Township",
    "Latha Township",
    "Mayangon Township",
    "Mingala Taungnyunt Township",
    "Mingaladon Township",
    "North Dagon Township",
    "North Okkalapa Township",
    "Pabedan Township",
    "Pazundaung Township",
    "Sanchaung Township",
    "Seikkan Township",
    "Seikkyi Kanaungto Township",
    "Shwepyitha Township",
    "South Dagon Township",
    "South Okkalapa Township",
    "Tamwe Township",
    "Thaketa Township",
    "Thingangyun Township",
    "Yankin Township",
]

DEFAULT_DATA = {
    "products": [
        {
            "sku": "T100",
            "name": "သူဌေးမင်း စားသုံးဆီ 50 သား",
            "price": 6.5,
            "cost_price": 5.2,
            "stock": 120,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 10,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 6.5},
                {"min_qty": 10, "unit_price": 6.3},
                {"min_qty": 20, "unit_price": 6.1},
            ],
        },
        {
            "sku": "T200",
            "name": "သူဌေးမင်း စားသုံးဆီ 25 ကျပ်သား",
            "price": 3.4,
            "cost_price": 2.7,
            "stock": 120,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 10,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 3.4},
                {"min_qty": 12, "unit_price": 3.25},
                {"min_qty": 24, "unit_price": 3.1},
            ],
        },
        {
            "sku": "T300",
            "name": "သူဌေးမင်း စားသုံးဆီ 15 ကျပ်သား",
            "price": 2.2,
            "cost_price": 1.7,
            "stock": 120,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 10,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 2.2},
                {"min_qty": 12, "unit_price": 2.08},
                {"min_qty": 24, "unit_price": 1.95},
            ],
        },
        {
            "sku": "T400",
            "name": "သူဌေးမင်း စားသုံးဆီ 3 ပိဿ",
            "price": 18.0,
            "cost_price": 14.8,
            "stock": 60,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 5,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 18.0},
                {"min_qty": 6, "unit_price": 17.2},
                {"min_qty": 12, "unit_price": 16.7},
            ],
        },
        {
            "sku": "T500",
            "name": "သူဌေးမင်း စားသုံးဆီ 5 ပိဿ",
            "price": 28.0,
            "cost_price": 23.0,
            "stock": 60,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 5,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 28.0},
                {"min_qty": 6, "unit_price": 27.1},
                {"min_qty": 12, "unit_price": 26.5},
            ],
        },
        {
            "sku": "T600",
            "name": "သူဌေးမင်း စားသုံးဆီ 10 ပိဿ",
            "price": 54.0,
            "cost_price": 45.0,
            "stock": 40,
            "category": "စားသုံးဆီ",
            "unit": "ဗူး",
            "low_stock_threshold": 3,
            "price_tiers": [
                {"min_qty": 1, "unit_price": 54.0},
                {"min_qty": 4, "unit_price": 52.8},
                {"min_qty": 8, "unit_price": 51.5},
            ],
        },
    ],
    "sales": [],
    "users": [
        {
            "username": "admin",
            "password": "admin123",
            "role": "admin",
            "require_2fa": True,
            "allowed_devices": ["POS-TERMINAL-01"],
        },
        {
            "username": "cashier",
            "password": "cashier123",
            "role": "cashier",
            "require_2fa": False,
            "allowed_devices": ["POS-TERMINAL-01"],
        },
        {
            "username": "storekeeper",
            "password": "store123",
            "role": "storekeeper",
            "require_2fa": False,
            "allowed_devices": ["POS-TERMINAL-01"],
        },
        {
            "username": "salestaff",
            "password": "sales123",
            "role": "sales_staff",
            "require_2fa": False,
            "allowed_devices": ["POS-TERMINAL-01"],
        },
    ],
    "customers": [],
    "teams": copy.deepcopy(DEFAULT_TEAMS),
    "shifts": [],
    "employee_daily_sales": {},
    "promotions": [
        {
            "code": "PROMO10",
            "type": "percentage",
            "value": 10,
            "active": True,
            "min_subtotal": 0,
            "category": "",
            "description": "10% off total",
        },
        {
            "code": "ADDI15",
            "type": "percentage",
            "value": 15,
            "active": True,
            "min_subtotal": 0,
            "category": "Additives",
            "description": "15% off additives",
        },
    ],
    "audit_logs": [],
    "idempotency_keys": {},
    "sales_targets": {
        "salestaff": {"daily_target": 60000.0, "commission_rate": 0.03},
        "cashier": {"daily_target": 30000.0, "commission_rate": 0.01},
    },
}

class Store:
    def __init__(self, path: str):
        raw_path = Path(path)
        self.path = raw_path.with_suffix(".db")
        self.legacy_json_path = raw_path if raw_path.suffix == ".json" else raw_path.with_suffix(".json")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.backup_manager = BackupManager(str(self.path.parent.parent / "backups"))
        self._init_db()
        if not self._has_state():
            if self.legacy_json_path.exists():
                with self.legacy_json_path.open("r", encoding="utf-8") as f:
                    self._write(json.load(f))
            else:
                self._write(DEFAULT_DATA)

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS app_state (
                    state_key TEXT PRIMARY KEY,
                    payload TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def _has_state(self) -> bool:
        with self._connect() as conn:
            row = conn.execute("SELECT payload FROM app_state WHERE state_key = 'main'").fetchone()
            return row is not None

    def _read(self) -> dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT payload FROM app_state WHERE state_key = 'main'").fetchone()
        if not row:
            return copy.deepcopy(DEFAULT_DATA)
        return json.loads(row["payload"])

    def _write(self, data: dict[str, Any]) -> None:
        payload = json.dumps(data, ensure_ascii=False, indent=2)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO app_state(state_key, payload) VALUES('main', ?) ON CONFLICT(state_key) DO UPDATE SET payload=excluded.payload",
                (payload,),
            )
            conn.commit()

    @staticmethod
    def _normalize_product(product: dict[str, Any]) -> dict[str, Any]:
        normalized = dict(product)
        normalized.setdefault("category", "General")
        normalized.setdefault("unit", "pcs")
        normalized.setdefault("low_stock_threshold", 10)
        normalized.setdefault("cost_price", round(float(normalized.get("price", 0)) * 0.75, 2))
        normalized.setdefault("price_tiers", [{"min_qty": 1, "unit_price": round(float(normalized.get("price", 0)), 2)}])
        normalized["category"] = str(normalized["category"])
        normalized["unit"] = "pcs"
        normalized["low_stock_threshold"] = int(normalized["low_stock_threshold"])
        normalized["cost_price"] = round(float(normalized["cost_price"]), 2)
        normalized["price_tiers"] = sorted(
            [
                {
                    "min_qty": max(1, int(tier.get("min_qty", 1))),
                    "unit_price": round(float(tier.get("unit_price", normalized.get("price", 0))), 2),
                }
                for tier in normalized.get("price_tiers", [])
            ],
            key=lambda tier: tier["min_qty"],
        )
        return normalized

    @staticmethod
    def _normalize_team(team: dict[str, Any]) -> dict[str, Any]:
        normalized = dict(team)
        normalized.setdefault("id", 0)
        normalized.setdefault("code", "")
        normalized.setdefault("name", "")
        normalized.setdefault("sales_man_name", "")
        normalized.setdefault("position", "")
        normalized.setdefault("phone", "")
        normalized.setdefault("township", "")
        normalized.setdefault("townships", [])
        normalized.setdefault("item_targets", [])
        normalized["id"] = int(normalized["id"])
        normalized["code"] = str(normalized["code"]).strip().upper()
        normalized["name"] = str(normalized["name"]).strip()
        normalized["sales_man_name"] = str(normalized["sales_man_name"]).strip()
        normalized["position"] = str(normalized["position"]).strip()
        normalized["phone"] = str(normalized["phone"]).strip()
        townships = normalized.get("townships", [])
        if not isinstance(townships, list):
            townships = []
        if not townships and str(normalized.get("township", "")).strip():
            townships = [str(normalized.get("township", "")).strip()]
        cleaned_townships: list[str] = []
        seen_townships: set[str] = set()
        for township in townships:
            label = str(township).strip()
            if label and label not in seen_townships:
                cleaned_townships.append(label)
                seen_townships.add(label)
        normalized["townships"] = cleaned_townships
        normalized["township"] = cleaned_townships[0] if cleaned_townships else str(normalized["township"]).strip()
        cleaned_targets: list[dict[str, Any]] = []
        for target in normalized.get("item_targets", []):
            sku = str(target.get("sku", "")).strip().upper()
            if not sku:
                continue
            cleaned_targets.append(
                {
                    "sku": sku,
                    "name": str(target.get("name", "")).strip(),
                    "quantity": max(0, int(target.get("quantity", 0))),
                }
            )
        normalized["item_targets"] = cleaned_targets
        return normalized

    @staticmethod
    def _team_map(teams: list[dict[str, Any]]) -> dict[str, str]:
        mapping: dict[str, str] = {}
        for team in teams:
            code = str(team.get("code", "")).strip().upper()
            if not code:
                continue
            townships = team.get("townships", [])
            if not isinstance(townships, list):
                townships = []
            if not townships and str(team.get("township", "")).strip():
                townships = [str(team.get("township", "")).strip()]
            for township in townships:
                label = str(township).strip()
                if label:
                    mapping[label] = code
        return mapping

    @staticmethod
    def _normalize_customer(customer: dict[str, Any], team_by_township: dict[str, str]) -> dict[str, Any]:
        normalized = dict(customer)
        normalized.setdefault("email", "")
        normalized.setdefault("vehicle_no", "")
        normalized.setdefault("township", "")
        normalized.setdefault("address", "")
        normalized.setdefault("notes", "")
        normalized.setdefault("team_code", "")
        normalized.setdefault("loyalty_points", 0)
        normalized.setdefault("credit_balance", 0.0)
        normalized.setdefault("route_order", 0)
        normalized.setdefault("preferred_visit_time", "")
        normalized.setdefault("last_visit_at", "")
        normalized.setdefault("last_latitude", None)
        normalized.setdefault("last_longitude", None)
        normalized["email"] = str(normalized["email"])
        normalized["vehicle_no"] = str(normalized["vehicle_no"])
        normalized["township"] = str(normalized["township"])
        normalized["address"] = str(normalized["address"])
        normalized["notes"] = str(normalized["notes"])
        normalized["team_code"] = str(normalized["team_code"]).upper()
        normalized["loyalty_points"] = int(normalized["loyalty_points"])
        normalized["credit_balance"] = round(float(normalized["credit_balance"]), 2)
        normalized["route_order"] = int(normalized["route_order"])
        normalized["preferred_visit_time"] = str(normalized["preferred_visit_time"])
        normalized["last_visit_at"] = str(normalized["last_visit_at"])
        normalized["last_latitude"] = None if normalized["last_latitude"] in (None, "") else float(normalized["last_latitude"])
        normalized["last_longitude"] = None if normalized["last_longitude"] in (None, "") else float(normalized["last_longitude"])
        if normalized["township"] and not normalized["team_code"]:
            normalized["team_code"] = team_by_township.get(normalized["township"], "")
        return normalized

    def _decrypt_sensitive(self, data: dict[str, Any]) -> dict[str, Any]:
        clone = copy.deepcopy(data)

        for customer in clone.get("customers", []):
            for field in ["name", "phone", "email", "vehicle_no", "township", "address", "notes"]:
                if field in customer:
                    customer[field] = decrypt_text(customer[field])

        for sale in clone.get("sales", []):
            if "customer_enc" in sale and "customer" not in sale:
                sale["customer"] = json.loads(decrypt_text(sale["customer_enc"]))
            if "payments_enc" in sale and "payments" not in sale:
                sale["payments"] = json.loads(decrypt_text(sale["payments_enc"]))

        return clone

    def _encrypt_sensitive(self, data: dict[str, Any]) -> dict[str, Any]:
        clone = copy.deepcopy(data)

        for customer in clone.get("customers", []):
            for field in ["name", "phone", "email", "vehicle_no", "township", "address", "notes"]:
                if field in customer:
                    customer[field] = encrypt_text(str(customer[field]))

        for sale in clone.get("sales", []):
            if "customer" in sale and sale["customer"] is not None:
                sale["customer_enc"] = encrypt_text(json.dumps(sale["customer"], ensure_ascii=False))
                del sale["customer"]
            if "payments" in sale:
                sale["payments_enc"] = encrypt_text(json.dumps(sale["payments"], ensure_ascii=False))
                del sale["payments"]

        return clone

    def _migrate_users(self, users: list[dict[str, Any]]) -> bool:
        changed = False
        for user in users:
            user["username"] = str(user.get("username", "")).strip()

            if "password_hash" not in user:
                plain = user.pop("password", "")
                if not plain:
                    plain = secrets.token_urlsafe(16)
                user["password_hash"] = hash_password(plain)
                user["must_change_password"] = True
                changed = True

            if "password" in user:
                user.pop("password", None)
                changed = True

            if "require_2fa" not in user:
                user["require_2fa"] = user.get("role") == "admin"
                changed = True

            if user.get("require_2fa") and not user.get("otp_secret"):
                user["otp_secret"] = generate_2fa_secret()
                changed = True

            if "allowed_devices" not in user or not isinstance(user.get("allowed_devices"), list):
                user["allowed_devices"] = [] if user.get("role") == "sales_staff" else ["POS-TERMINAL-01"]
                changed = True

            if "full_name" not in user:
                user["full_name"] = user.get("username", "")
                changed = True

            if "team_code" not in user:
                user["team_code"] = ""
                changed = True

            if "active" not in user:
                user["active"] = True
                changed = True

            if user.get("role") != "sales_staff" and user.get("team_code"):
                user["team_code"] = ""
                changed = True

        return changed

    @staticmethod
    def _merge_default_users(users: list[dict[str, Any]]) -> bool:
        changed = False
        existing_usernames = {str(user.get("username", "")).strip() for user in users}
        for default_user in DEFAULT_DATA["users"]:
            username = str(default_user.get("username", "")).strip()
            if username and username not in existing_usernames:
                users.append(copy.deepcopy(default_user))
                existing_usernames.add(username)
                changed = True
        return changed

    def get_data(self) -> dict[str, Any]:
        raw_data = self._read()
        data = self._decrypt_sensitive(raw_data)
        changed = False

        for key, value in DEFAULT_DATA.items():
            if key not in data:
                data[key] = copy.deepcopy(value)
                changed = True

        legacy_names = {str(p.get("name", "")).strip().lower() for p in data.get("products", [])}
        legacy_skus = {str(p.get("sku", "")).strip().upper() for p in data.get("products", [])}
        if {"coffee", "tea", "sandwich"}.issubset(legacy_names):
            data["products"] = copy.deepcopy(DEFAULT_DATA["products"])
            changed = True

        if {"F100", "F200", "A100", "L100", "P100"}.intersection(legacy_skus):
            data["products"] = copy.deepcopy(DEFAULT_DATA["products"])
            changed = True

        normalized_products = [self._normalize_product(p) for p in data.get("products", [])]
        if normalized_products != data.get("products", []):
            data["products"] = normalized_products
            changed = True

        normalized_teams = [self._normalize_team(t) for t in data.get("teams", [])]
        if normalized_teams != data.get("teams", []):
            data["teams"] = normalized_teams
            changed = True

        team_by_township = self._team_map(data.get("teams", []))

        normalized_customers = [self._normalize_customer(c, team_by_township) for c in data.get("customers", [])]
        if normalized_customers != data.get("customers", []):
            data["customers"] = normalized_customers
            changed = True

        if self._merge_default_users(data.get("users", [])):
            changed = True

        if self._migrate_users(data.get("users", [])):
            changed = True

        if changed:
            self.save_data(data)
        return data

    def save_data(self, data: dict[str, Any]) -> None:
        encrypted = self._encrypt_sensitive(data)
        self._write(encrypted)
        self.backup_manager.daily_backup(str(self.path))
