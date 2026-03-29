import tempfile
import unittest
from pathlib import Path

from src.pos.auth import AuthService
from src.pos.exporter import InvoiceExporter
from src.pos.service import POSService
from src.pos.store import Store


class TestPOSService(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        db_path = Path(self.tmpdir.name) / "test_data.db"
        self.store = Store(str(db_path))
        self.pos = POSService(self.store)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_checkout_with_promotion_and_multi_payment(self):
        self.pos.add_to_cart("T100", 2)
        receipt = self.pos.checkout(
            promo_code="PROMO10",
            cashier="cashier",
            payments=[{"method": "cash", "amount": 10}, {"method": "card", "amount": 10}],
        )
        self.assertEqual(receipt["subtotal"], 13.0)
        self.assertEqual(receipt["promo_discount"], 1.3)
        self.assertEqual(receipt["grand_total"], 11.7)
        self.assertEqual(receipt["total_paid"], 20.0)
        self.assertEqual(receipt["change_due"], 8.3)

    def test_customer_crud(self):
        customer = self.pos.create_customer(
            "Mg Mg",
            "091234567",
            "mg@example.com",
            "",
            "ရန်ကုန်",
            "အမှတ် ၁၂၃, ဗိုလ်ချုပ်လမ်း",
        )
        self.assertEqual(customer["name"], "Mg Mg")
        self.assertEqual(customer["township"], "ရန်ကုန်")
        self.assertEqual(customer["team_code"], next(team["code"] for team in self.pos.list_teams() if team["township"] == "ရန်ကုန်"))

        updated = self.pos.update_customer(customer["id"], {"name": "Aung Aung", "township": "သထုံ"})
        self.assertEqual(updated["name"], "Aung Aung")
        self.assertEqual(updated["team_code"], next(team["code"] for team in self.pos.list_teams() if team["township"] == "သထုံ"))

        self.pos.delete_customer(customer["id"])
        self.assertEqual(len(self.pos.list_customers()), 0)

    def test_shift_tracking(self):
        shift = self.pos.start_shift("cashier")
        self.assertEqual(shift["username"], "cashier")
        self.pos.add_to_cart("T100", 1)
        self.pos.checkout(cashier="cashier", payments=[{"method": "cash", "amount": 10}])
        ended = self.pos.end_shift("cashier")
        self.assertTrue(ended["end"])

    def test_team_crud_updates_customer_mapping(self):
        created = self.pos.create_team("Sale Team - 4 (BGO)", "Ko Bago", "Sales Man", "095555555", "ပဲခူး")
        self.assertEqual(created["name"], "Sale Team - 4 (BGO)")
        self.assertTrue(created["code"].startswith("TEAM"))

        customer = self.pos.create_customer("Ma Ma", "099999999", "", "", "ပဲခူး", "ဗဟိုလမ်း")
        self.assertEqual(customer["team_code"], created["code"])

        updated = self.pos.update_team(created["id"], {"name": "Sale Team - 4 (BGO2)", "sales_man_name": "Ko Updated", "township": "ပဲခူး"})
        self.assertEqual(updated["name"], "Sale Team - 4 (BGO2)")

        remapped_customer = next(c for c in self.pos.list_customers() if c["id"] == customer["id"])
        self.assertEqual(remapped_customer["team_code"], created["code"])

        self.pos.delete_team(created["id"])
        detached_customer = next(c for c in self.pos.list_customers() if c["id"] == customer["id"])
        self.assertEqual(detached_customer["team_code"], "")

    def test_reports(self):
        self.pos.add_to_cart("T100", 2)
        self.pos.checkout(cashier="cashier", payments=[{"method": "cash", "amount": 20}])
        sales = self.pos.sales_report("daily")
        inventory = self.pos.inventory_report()
        pnl = self.pos.profit_and_loss_report("daily")
        employee = self.pos.employee_sales_report()

        self.assertGreaterEqual(sales["transactions"], 1)
        self.assertGreaterEqual(inventory["total_products"], 1)
        self.assertGreaterEqual(pnl["revenue"], 0)
        self.assertIn("cashier", employee["employees"])

    def test_update_and_delete_product(self):
        self.pos.update_product("T100", {"name": "သူဌေးမင်း စားသုံးဆီ 50 သား အသစ်", "price": 7.0})
        updated = next(p for p in self.pos.list_products() if p["sku"] == "T100")
        self.assertEqual(updated["name"], "သူဌေးမင်း စားသုံးဆီ 50 သား အသစ်")
        self.assertEqual(updated["price"], 7.0)

        self.pos.add_product("T700", "စမ်းသပ် ပစ္စည်း", 1.5, 0, "လူသုံးကုန်", "ဗူး", 5, 1.0)
        self.pos.delete_product("T700")
        product_ids = [p["sku"] for p in self.pos.list_products()]
        self.assertNotIn("T700", product_ids)

    def test_tax_invoice_checkout(self):
        self.pos.add_to_cart("T100", 1)
        receipt = self.pos.checkout(
            cashier="cashier",
            payments=[{"method": "cash", "amount": 10}],
            generate_tax_invoice=True,
            tax_rate=5,
            tax_tin="MM-TAX-001",
        )
        self.assertEqual(receipt["tax_invoice"]["enabled"], True)
        self.assertEqual(receipt["tax_invoice"]["tax_rate"], 5.0)
        self.assertGreater(receipt["invoice_total"], receipt["grand_total"])


class TestAuthAndExport(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        base = Path(self.tmpdir.name)
        self.store = Store(str(base / "test_data.db"))
        self.pos = POSService(self.store)
        self.auth = AuthService(self.store)
        self.exporter = InvoiceExporter(str(base / "exports"))

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_login_roles(self):
        admin = self.auth.login("admin", "admin123", device_id="POS-TERMINAL-01")
        cashier = self.auth.login("cashier", "cashier123", device_id="POS-TERMINAL-01")
        storekeeper = self.auth.login("storekeeper", "store123", device_id="POS-TERMINAL-01")
        sales_staff = self.auth.login("salestaff", "sales123", device_id="POS-TERMINAL-01")
        self.assertTrue(self.auth.has_role(admin, "admin"))
        self.assertTrue(self.auth.has_role(cashier, "cashier"))
        self.assertTrue(self.auth.has_role(storekeeper, "storekeeper"))
        self.assertTrue(self.auth.has_role(sales_staff, "sales_staff"))

    def test_export_csv_and_pdf(self):
        self.pos.add_to_cart("T100", 1)
        receipt = self.pos.checkout(cashier="cashier", payments=[{"method": "cash", "amount": 10}])
        csv_path = self.exporter.export_csv(receipt)
        pdf_path = self.exporter.export_pdf(receipt)
        self.assertTrue(Path(csv_path).exists())
        self.assertTrue(Path(pdf_path).exists())


if __name__ == "__main__":
    unittest.main()
