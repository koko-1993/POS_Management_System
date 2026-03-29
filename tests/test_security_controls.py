import tempfile
import unittest
import json
import sqlite3
import os
from pathlib import Path
from unittest.mock import patch

from src.pos.auth import AuthService
from src.pos.security import build_otpauth_uri, current_2fa_code
from src.pos.service import POSService
from src.pos.store import Store


class TestSecurityControls(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmpdir.name) / "test_data.db"
        self.store = Store(str(self.db_path))
        self.pos = POSService(self.store)
        self.auth = AuthService(self.store)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_admin_login_skips_otp_while_2fa_is_disabled(self):
        user = self.auth.login("admin", "admin123", device_id="POS-TERMINAL-01")
        self.assertEqual(user["role"], "admin")

    def test_admin_requires_2fa_when_env_flag_is_enabled(self):
        with patch.dict(os.environ, {"POS_ENABLE_ADMIN_2FA": "1"}):
            with self.assertRaises(ValueError):
                self.auth.login("admin", "admin123", device_id="POS-TERMINAL-01")

            data = self.store.get_data()
            admin_row = next(u for u in data["users"] if u["username"] == "admin")
            otp = current_2fa_code(admin_row["otp_secret"])
            user = self.auth.login("admin", "admin123", otp_code=otp, device_id="POS-TERMINAL-01")
            self.assertEqual(user["role"], "admin")

    def test_device_restriction(self):
        with self.assertRaises(ValueError):
            self.auth.login("cashier", "cashier123", device_id="UNREGISTERED-DEVICE")

    def test_sensitive_fields_encrypted_at_rest(self):
        self.pos.create_customer("Mg Mg", "091234567", "mg@example.com", "YGN-1234")

        with sqlite3.connect(self.db_path) as conn:
            row = conn.execute("SELECT payload FROM app_state WHERE state_key = 'main'").fetchone()
        raw = row[0]
        self.assertNotIn("Mg Mg", raw)
        self.assertNotIn("091234567", raw)
        self.assertIn("enc:v1:", raw)

    def test_prevent_accidental_duplicate_checkout(self):
        self.pos.add_to_cart("T100", 1)
        first = self.pos.checkout(cashier="cashier", payments=[{"method": "cash", "amount": 10}])

        self.pos.add_to_cart("T100", 1)
        second = self.pos.checkout(cashier="cashier", payments=[{"method": "cash", "amount": 10}])

        self.assertEqual(first["invoice_id"], second["invoice_id"])
        data = self.store.get_data()
        self.assertEqual(len(data.get("sales", [])), 1)

    def test_google_authenticator_uri_contains_expected_fields(self):
        data = self.store.get_data()
        admin_row = next(u for u in data["users"] if u["username"] == "admin")
        uri = build_otpauth_uri(admin_row["otp_secret"], "admin")

        self.assertTrue(uri.startswith("otpauth://totp/"))
        self.assertIn("secret=", uri)
        self.assertIn("issuer=Shwe%20Htoo%20Thit%20POS", uri)
        self.assertIn("digits=6", uri)

    def test_missing_default_users_are_restored_on_load(self):
        with sqlite3.connect(self.db_path) as conn:
            row = conn.execute("SELECT payload FROM app_state WHERE state_key = 'main'").fetchone()
        raw = json.loads(row[0])
        raw["users"] = raw["users"][:2]
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                "UPDATE app_state SET payload = ? WHERE state_key = 'main'",
                (json.dumps(raw, ensure_ascii=False, indent=2),),
            )
            conn.commit()

        restored = self.store.get_data()
        usernames = {user["username"] for user in restored["users"]}

        self.assertIn("storekeeper", usernames)
        self.assertIn("salestaff", usernames)

    def test_sales_staff_can_login_after_mobile_device_authorization(self):
        mobile_id = "MOBILE-SALES-01"

        with self.assertRaises(ValueError):
            self.auth.login("salestaff", "sales123", device_id=mobile_id)

        data = self.store.get_data()
        user = next(u for u in data["users"] if u["username"] == "salestaff")
        user.setdefault("allowed_devices", []).append(mobile_id)
        self.store.save_data(data)

        logged_in = self.auth.login("salestaff", "sales123", device_id=mobile_id)
        self.assertEqual(logged_in["role"], "sales_staff")

    def test_admin_can_manage_sales_accounts(self):
        created = self.auth.create_user(
            "sales.thm",
            "SalesPass#2026",
            "sales_staff",
            full_name="Sales THM",
            team_code="TEAM001",
        )
        self.assertEqual(created["username"], "sales.thm")
        self.assertEqual(created["team_code"], "TEAM001")
        self.assertTrue(created["active"])

        logged_in = self.auth.login("sales.thm", "SalesPass#2026", device_id="ANY-PHONE")
        self.assertEqual(logged_in["role"], "sales_staff")
        self.assertEqual(logged_in["team_code"], "TEAM001")

        updated = self.auth.update_user(
            "sales.thm",
            {
                "full_name": "Sales THM Updated",
                "team_code": "TEAM002",
                "active": False,
                "password": "UpdatedPass#2026",
            },
        )
        self.assertEqual(updated["full_name"], "Sales THM Updated")
        self.assertEqual(updated["team_code"], "TEAM002")
        self.assertFalse(updated["active"])

        with self.assertRaises(ValueError):
            self.auth.login("sales.thm", "UpdatedPass#2026", device_id="ANY-PHONE")

        self.auth.delete_user("sales.thm")
        usernames = {user["username"] for user in self.auth.list_users()}
        self.assertNotIn("sales.thm", usernames)


if __name__ == "__main__":
    unittest.main()
