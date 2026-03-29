from __future__ import annotations

from pathlib import Path

from .auth import AuthService
from .exporter import InvoiceExporter
from .service import POSService
from .store import Store


def print_menu(role: str) -> None:
    print("\n=== POS System Management ===")
    print("1. List Products")
    if role == "admin":
        print("2. Add Product")
        print("3. Update Stock")
    print("4. Add To Cart")
    print("5. Remove From Cart")
    print("6. View Cart")
    print("7. Checkout")
    if role == "admin":
        print("8. Sales Report")
    print("9. Exit")


def format_money(value: float) -> str:
    return f"${value:.2f}"


def run() -> None:
    root = Path(__file__).resolve().parents[2]
    store = Store(str(root / "data" / "pos_data.db"))
    pos = POSService(store)
    auth = AuthService(store)
    exporter = InvoiceExporter(str(root / "exports"))

    user = None
    for _ in range(3):
        username = input("Username: ").strip()
        password = input("Password: ").strip()
        try:
            user = auth.login(username, password)
            break
        except ValueError:
            print("Invalid credentials")
    if not user:
        print("Too many failed login attempts")
        return

    role = user["role"]
    print(f"Login successful: {user['username']} ({role})")

    while True:
        print_menu(role)
        choice = input("Select option: ").strip()

        try:
            if choice == "1":
                for p in pos.list_products():
                    print(
                        f"{p['sku']} | {p['name']} | {format_money(p['price'])} | stock={p['stock']}"
                    )

            elif choice == "2":
                if role != "admin":
                    print("Permission denied: admin only")
                    continue
                sku = input("SKU: ").strip().upper()
                name = input("Name: ").strip()
                price = float(input("Price: ").strip())
                stock = int(input("Stock: ").strip())
                pos.add_product(sku, name, price, stock)
                print("Product added")

            elif choice == "3":
                if role != "admin":
                    print("Permission denied: admin only")
                    continue
                sku = input("SKU: ").strip().upper()
                delta = int(input("Stock change (+/-): ").strip())
                pos.update_stock(sku, delta)
                print("Stock updated")

            elif choice == "4":
                sku = input("SKU: ").strip().upper()
                qty = int(input("Quantity: ").strip())
                pos.add_to_cart(sku, qty)
                print("Added to cart")

            elif choice == "5":
                sku = input("SKU: ").strip().upper()
                qty = int(input("Quantity to remove: ").strip())
                pos.remove_from_cart(sku, qty)
                print("Removed from cart")

            elif choice == "6":
                items = pos.view_cart()
                if not items:
                    print("Cart is empty")
                else:
                    for item in items:
                        print(
                            f"{item.sku} | {item.name} | qty={item.quantity} | line={format_money(item.line_total)}"
                        )
                    print(f"Total: {format_money(pos.cart_total())}")

            elif choice == "7":
                discount = float(input("Discount % (0-100): ").strip() or "0")
                receipt = pos.checkout(discount, cashier=user["username"])
                csv_path = exporter.export_csv(receipt)
                pdf_path = exporter.export_pdf(receipt)
                print("\n--- Receipt ---")
                print(f"Invoice ID: {receipt['invoice_id']}")
                for item in receipt["items"]:
                    print(
                        f"{item['name']} x{item['quantity']} = {format_money(item['line_total'])}"
                    )
                print(f"Subtotal: {format_money(receipt['subtotal'])}")
                print(f"Discount: {format_money(receipt['discount'])}")
                print(f"Grand Total: {format_money(receipt['grand_total'])}")
                print(f"Exported CSV: {csv_path}")
                print(f"Exported PDF: {pdf_path}")

            elif choice == "8":
                if role != "admin":
                    print("Permission denied: admin only")
                    continue
                report = pos.sales_report()
                print(f"Transactions: {report['transactions']}")
                print(f"Total Sales: {format_money(report['total_sales'])}")
                print("Top Items:")
                for name, qty in report["top_items"][:5]:
                    print(f"- {name}: {qty}")

            elif choice == "9":
                print("Goodbye")
                break

            else:
                print("Invalid option")

        except ValueError as e:
            print(f"Error: {e}")


if __name__ == "__main__":
    run()
