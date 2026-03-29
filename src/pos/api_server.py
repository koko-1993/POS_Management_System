from __future__ import annotations

import argparse
import json
import secrets
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .auth import AuthService
from .exporter import InvoiceExporter
from .service import POSService
from .store import Store


ROOT = Path(__file__).resolve().parents[2]
WEB_DIR = ROOT / "web"
store = Store(str(ROOT / "data" / "pos_data.db"))
pos = POSService(store)
auth = AuthService(store)
exporter = InvoiceExporter(str(ROOT / "exports"))
TOKENS: dict[str, dict[str, str]] = {}


def _json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _parse_body(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(length) if length > 0 else b"{}"
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        raise ValueError("Invalid JSON payload")


def _get_user_from_token(handler: BaseHTTPRequestHandler) -> dict[str, str]:
    auth_header = handler.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise PermissionError("Missing bearer token")
    token = auth_header.split(" ", 1)[1]
    user = TOKENS.get(token)
    if not user:
        raise PermissionError("Invalid token")
    return user


def _get_device_id(handler: BaseHTTPRequestHandler) -> str:
    return handler.headers.get("X-Device-ID", "").strip()


def _require_roles(user: dict[str, str], allowed: set[str]) -> None:
    if user.get("role") not in allowed:
        raise PermissionError(f"Role {user.get('role')} not allowed")


class POSApiHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/":
            return self._serve_file(WEB_DIR / "index.html", "text/html; charset=utf-8")
        if parsed.path == "/mobile":
            return self._serve_file(WEB_DIR / "mobile.html", "text/html; charset=utf-8")
        if parsed.path == "/office":
            return self._serve_file(WEB_DIR / "office.html", "text/html; charset=utf-8")
        if parsed.path == "/app.js":
            return self._serve_file(WEB_DIR / "app.js", "text/javascript; charset=utf-8")
        if parsed.path == "/mobile.js":
            return self._serve_file(WEB_DIR / "mobile.js", "text/javascript; charset=utf-8")
        if parsed.path == "/office.js":
            return self._serve_file(WEB_DIR / "office.js", "text/javascript; charset=utf-8")
        if parsed.path == "/styles.css":
            return self._serve_file(WEB_DIR / "styles.css", "text/css; charset=utf-8")
        if parsed.path == "/mobile.css":
            return self._serve_file(WEB_DIR / "mobile.css", "text/css; charset=utf-8")

        if parsed.path.startswith("/api/customers/") and parsed.path.endswith("/insights"):
            customer_id = parsed.path.split("/")[3]
            return self._handle_customer_insights(customer_id)

        route_map = {
            "/api/health": self._handle_health,
            "/api/roles": self._handle_roles,
            "/api/users": self._handle_get_users,
            "/api/products": self._handle_get_products,
            "/api/categories": self._handle_get_categories,
            "/api/promotions": self._handle_get_promotions,
            "/api/payment-options": self._handle_get_payment_options,
            "/api/cart": self._handle_get_cart,
            "/api/teams": self._handle_get_teams,
            "/api/customers": self._handle_get_customers,
            "/api/route-plan": self._handle_route_plan,
            "/api/mobile/dashboard": self._handle_mobile_dashboard,
            "/api/field-force": self._handle_field_force_dashboard,
            "/api/alerts/low-stock": self._handle_get_low_stock_alerts,
            "/api/reports/sales": self._handle_sales_report,
            "/api/reports/inventory": self._handle_inventory_report,
            "/api/reports/profit-loss": self._handle_profit_loss_report,
            "/api/reports/employee-sales": self._handle_employee_sales_report,
            "/api/report": self._handle_sales_report,
            "/api/shifts": self._handle_get_shifts,
            "/api/receipts": self._handle_get_receipts,
            "/api/sync/status": self._handle_sync_status,
            "/api/audit-logs": self._handle_audit_logs,
        }

        handler = route_map.get(parsed.path)
        if handler:
            return handler(parsed)

        _json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)

        route_map = {
            "/api/login": self._handle_login,
            "/api/auth/change-password": self._handle_change_password,
            "/api/users": self._handle_create_user,
            "/api/products": self._handle_add_product,
            "/api/promotions": self._handle_add_promotion,
            "/api/cart/add": self._handle_cart_add,
            "/api/cart/remove": self._handle_cart_remove,
            "/api/checkout": self._handle_checkout,
            "/api/teams": self._handle_create_team,
            "/api/customers": self._handle_create_customer,
            "/api/shifts/start": self._handle_shift_start,
            "/api/shifts/end": self._handle_shift_end,
            "/api/sync/replay": self._handle_sync_replay,
        }

        handler = route_map.get(parsed.path)
        if handler:
            return handler(parsed)

        _json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_PATCH(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path.startswith("/api/products/") and parsed.path.endswith("/stock"):
            sku = parsed.path.split("/")[3]
            return self._handle_update_stock(sku)

        if parsed.path.startswith("/api/customers/"):
            customer_id = parsed.path.split("/")[3]
            return self._handle_update_customer(customer_id)

        if parsed.path.startswith("/api/teams/"):
            team_id = parsed.path.split("/")[3]
            return self._handle_update_team(team_id)

        if parsed.path.startswith("/api/users/"):
            username = parsed.path.split("/")[3]
            return self._handle_update_user(username)

        if parsed.path.startswith("/api/products/"):
            sku = parsed.path.split("/")[3]
            return self._handle_update_product(sku)

        _json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/customers/"):
            customer_id = parsed.path.split("/")[3]
            return self._handle_delete_customer(customer_id)
        if parsed.path.startswith("/api/teams/"):
            team_id = parsed.path.split("/")[3]
            return self._handle_delete_team(team_id)
        if parsed.path.startswith("/api/users/"):
            username = parsed.path.split("/")[3]
            return self._handle_delete_user(username)
        if parsed.path.startswith("/api/products/"):
            sku = parsed.path.split("/")[3]
            return self._handle_delete_product(sku)
        _json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def _serve_file(self, path: Path, content_type: str) -> None:
        if not path.exists():
            _json_response(self, HTTPStatus.NOT_FOUND, {"error": "File not found"})
            return
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> dict[str, str]:
        user = _get_user_from_token(self)
        device_id = _get_device_id(self)
        expected = user.get("device_id", "")
        if expected and device_id != expected:
            raise PermissionError("Device mismatch for active token")
        return user

    def _handle_health(self, _parsed) -> None:
        _json_response(self, HTTPStatus.OK, {"status": "ok"})

    def _handle_roles(self, _parsed) -> None:
        _json_response(
            self,
            HTTPStatus.OK,
            {"roles": ["admin", "cashier", "storekeeper", "sales_staff"]},
        )

    def _handle_login(self, _parsed) -> None:
        try:
            payload = _parse_body(self)
            device_id = _get_device_id(self)
            user = auth.login(
                payload.get("username", ""),
                payload.get("password", ""),
                payload.get("otp_code", ""),
                device_id,
            )
            token = secrets.token_hex(24)
            user_data = {
                "username": user["username"],
                "full_name": user.get("full_name", user["username"]),
                "role": user["role"],
                "device_id": device_id,
                "team_code": user.get("team_code", ""),
            }
            TOKENS[token] = user_data
            _json_response(self, HTTPStatus.OK, {"token": token, "user": user_data})
        except ValueError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_get_users(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            _json_response(self, HTTPStatus.OK, {"users": auth.list_users()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_create_user(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            payload = _parse_body(self)
            created = auth.create_user(
                payload.get("username", ""),
                payload.get("password", ""),
                payload.get("role", "sales_staff"),
                full_name=payload.get("full_name", ""),
                team_code=payload.get("team_code", ""),
                allowed_devices=payload.get("allowed_devices", []),
                active=bool(payload.get("active", True)),
            )
            _json_response(self, HTTPStatus.CREATED, {"user": created})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_update_user(self, username: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            payload = _parse_body(self)
            updated = auth.update_user(username, payload)
            _json_response(self, HTTPStatus.OK, {"user": updated})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_delete_user(self, username: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            auth.delete_user(username)
            _json_response(self, HTTPStatus.OK, {"message": "User deleted"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_change_password(self, _parsed) -> None:
        try:
            user = self._authorized()
            payload = _parse_body(self)
            auth.change_password(
                user["username"],
                payload.get("current_password", ""),
                payload.get("new_password", ""),
            )
            _json_response(self, HTTPStatus.OK, {"message": "Password updated"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_get_products(self, _parsed) -> None:
        try:
            self._authorized()
            _json_response(self, HTTPStatus.OK, {"products": pos.list_products()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_get_categories(self, _parsed) -> None:
        try:
            self._authorized()
            _json_response(self, HTTPStatus.OK, {"categories": pos.list_categories()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_get_promotions(self, _parsed) -> None:
        try:
            self._authorized()
            _json_response(self, HTTPStatus.OK, {"promotions": pos.list_promotions(active_only=True)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_add_promotion(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            payload = _parse_body(self)
            pos.add_promotion(
                payload["code"],
                payload["type"],
                float(payload["value"]),
                float(payload.get("min_subtotal", 0)),
                payload.get("category", ""),
                payload.get("description", ""),
            )
            _json_response(self, HTTPStatus.CREATED, {"message": "Promotion added"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except (ValueError, KeyError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_get_payment_options(self, _parsed) -> None:
        try:
            self._authorized()
            _json_response(self, HTTPStatus.OK, {"payment_options": POSService.PAYMENT_OPTIONS})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_get_cart(self, _parsed) -> None:
        try:
            self._authorized()
            items = [
                {
                    "sku": i.sku,
                    "name": i.name,
                    "unit_price": i.unit_price,
                    "quantity": i.quantity,
                    "line_total": i.line_total,
                }
                for i in pos.view_cart()
            ]
            _json_response(self, HTTPStatus.OK, {"items": items, "total": pos.cart_total()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})

    def _handle_cart_add(self, _parsed) -> None:
        try:
            self._authorized()
            payload = _parse_body(self)
            pos.add_to_cart(payload["sku"].strip().upper(), int(payload["qty"]))
            _json_response(self, HTTPStatus.OK, {"message": "Added to cart"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})
        except (KeyError, ValueError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_cart_remove(self, _parsed) -> None:
        try:
            self._authorized()
            payload = _parse_body(self)
            pos.remove_from_cart(payload["sku"].strip().upper(), int(payload["qty"]))
            _json_response(self, HTTPStatus.OK, {"message": "Removed from cart"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})
        except (KeyError, ValueError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_checkout(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"cashier", "sales_staff"})
            payload = _parse_body(self)
            idempotency_key = self.headers.get("Idempotency-Key", "").strip()
            receipt = pos.checkout(
                discount_pct=float(payload.get("discount_pct", 0)),
                cashier=user["username"],
                promo_code=str(payload.get("promo_code", "")).strip(),
                payments=payload.get("payments", []),
                items_payload=payload.get("items", []),
                customer_id=payload.get("customer_id"),
                idempotency_key=idempotency_key or str(payload.get("client_order_id", "")).strip(),
                device_id=_get_device_id(self),
                location=payload.get("location"),
                visit_note=str(payload.get("visit_note", "")).strip(),
                generate_tax_invoice=bool(payload.get("generate_tax_invoice", False)),
                tax_rate=float(payload.get("tax_rate", 0)),
                tax_tin=str(payload.get("tax_tin", "")),
            )
            csv_path = exporter.export_csv(receipt)
            pdf_path = exporter.export_pdf(receipt)
            _json_response(
                self,
                HTTPStatus.OK,
                {
                    "receipt": receipt,
                    "exports": {
                        "csv": str(Path(csv_path).name),
                        "pdf": str(Path(pdf_path).name),
                    },
                },
            )
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_add_product(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            payload = _parse_body(self)
            pos.add_product(
                payload["sku"].strip().upper(),
                payload["name"].strip(),
                float(payload["price"]),
                int(payload["stock"]),
                payload.get("category", "General"),
                payload.get("unit", "item"),
                int(payload.get("low_stock_threshold", 10)),
                float(payload["cost_price"]) if "cost_price" in payload else None,
            )
            _json_response(self, HTTPStatus.CREATED, {"message": "Product added"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except (ValueError, KeyError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_update_stock(self, sku: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            payload = _parse_body(self)
            pos.update_stock(sku.strip().upper(), int(payload["delta"]))
            _json_response(self, HTTPStatus.OK, {"message": "Stock updated"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except (ValueError, KeyError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_update_product(self, sku: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            payload = _parse_body(self)
            product = pos.update_product(sku.strip().upper(), payload)
            _json_response(self, HTTPStatus.OK, {"product": product})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_delete_product(self, sku: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            pos.delete_product(sku.strip().upper())
            _json_response(self, HTTPStatus.OK, {"message": "Product deleted"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_get_customers(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            _json_response(self, HTTPStatus.OK, {"customers": pos.list_customers()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_route_plan(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            team_code = parse_qs(parsed.query).get("team_code", [""])[0]
            _json_response(self, HTTPStatus.OK, {"stops": pos.route_plan(team_code)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_customer_insights(self, customer_id: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            _json_response(self, HTTPStatus.OK, {"insights": pos.customer_insights(int(customer_id))})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_mobile_dashboard(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"cashier", "sales_staff"})
            _json_response(self, HTTPStatus.OK, {"dashboard": pos.sales_staff_dashboard(user["username"])})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_field_force_dashboard(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            _json_response(self, HTTPStatus.OK, {"staff": pos.field_force_dashboard(), "receipts": pos.recent_receipts(20)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_get_teams(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            _json_response(self, HTTPStatus.OK, {"teams": pos.list_teams()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_create_team(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            payload = _parse_body(self)
            team = pos.create_team(
                payload["name"],
                payload.get("sales_man_name", ""),
                payload.get("position", ""),
                payload.get("phone", ""),
                payload.get("township", ""),
                payload.get("townships", []),
                payload.get("item_targets", []),
            )
            _json_response(self, HTTPStatus.CREATED, {"team": team})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except (ValueError, KeyError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_create_customer(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            payload = _parse_body(self)
            customer = pos.create_customer(
                payload["name"],
                payload["phone"],
                payload.get("email", ""),
                payload.get("vehicle_no", ""),
                payload.get("township", ""),
                payload.get("address", ""),
                payload.get("notes", ""),
                float(payload.get("credit_balance", 0)),
                int(payload.get("route_order", 0)),
                payload.get("preferred_visit_time", ""),
            )
            _json_response(self, HTTPStatus.CREATED, {"customer": customer})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except (ValueError, KeyError) as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_update_customer(self, customer_id: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            payload = _parse_body(self)
            customer = pos.update_customer(int(customer_id), payload)
            _json_response(self, HTTPStatus.OK, {"customer": customer})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_update_team(self, team_id: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            payload = _parse_body(self)
            team = pos.update_team(int(team_id), payload)
            _json_response(self, HTTPStatus.OK, {"team": team})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_delete_customer(self, customer_id: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            pos.delete_customer(int(customer_id))
            _json_response(self, HTTPStatus.OK, {"message": "Customer deleted"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_delete_team(self, team_id: str) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            pos.delete_team(int(team_id))
            _json_response(self, HTTPStatus.OK, {"message": "Team deleted"})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_shift_start(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "sales_staff", "storekeeper"})
            shift = pos.start_shift(user["username"])
            _json_response(self, HTTPStatus.OK, {"shift": shift})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_shift_end(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "sales_staff", "storekeeper"})
            shift = pos.end_shift(user["username"])
            _json_response(self, HTTPStatus.OK, {"shift": shift})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_get_shifts(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "sales_staff", "storekeeper"})
            query = parse_qs(parsed.query)
            for_date = query.get("date", [""])[0]
            _json_response(self, HTTPStatus.OK, {"shifts": pos.list_shifts(for_date)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_sales_report(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
            period = parse_qs(parsed.query).get("period", ["daily"])[0]
            _json_response(self, HTTPStatus.OK, {"report": pos.sales_report(period)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_inventory_report(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            _json_response(self, HTTPStatus.OK, {"report": pos.inventory_report()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_profit_loss_report(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            period = parse_qs(parsed.query).get("period", ["monthly"])[0]
            _json_response(self, HTTPStatus.OK, {"report": pos.profit_and_loss_report(period)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_employee_sales_report(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "cashier", "sales_staff"})
            for_date = parse_qs(parsed.query).get("date", [""])[0]
            _json_response(self, HTTPStatus.OK, {"report": pos.employee_sales_report(for_date)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_get_low_stock_alerts(self, _parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin", "storekeeper"})
            _json_response(self, HTTPStatus.OK, {"alerts": pos.get_low_stock_alerts()})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})

    def _handle_get_receipts(self, parsed) -> None:
        try:
            self._authorized()
            limit = int(parse_qs(parsed.query).get("limit", ["20"])[0])
            _json_response(self, HTTPStatus.OK, {"receipts": pos.recent_receipts(limit)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.UNAUTHORIZED, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_sync_status(self, _parsed) -> None:
        _json_response(
            self,
            HTTPStatus.OK,
            {
                "online": True,
                "server_time": datetime.now().isoformat(timespec="seconds"),
                "note": "Client should replay queued operations when online.",
            },
        )

    def _handle_audit_logs(self, parsed) -> None:
        try:
            user = self._authorized()
            _require_roles(user, {"admin"})
            limit = int(parse_qs(parsed.query).get("limit", ["100"])[0])
            _json_response(self, HTTPStatus.OK, {"logs": pos.list_audit_logs(limit)})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})
        except ValueError as e:
            _json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(e)})

    def _handle_sync_replay(self, _parsed) -> None:
        try:
            user = self._authorized()
            payload = _parse_body(self)
            actions = payload.get("actions", [])
            results: list[dict[str, Any]] = []

            for action in actions:
                kind = action.get("kind")
                data = action.get("data", {})
                try:
                    if kind == "create_customer":
                        _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
                        customer = pos.create_customer(
                            data["name"],
                            data["phone"],
                            data.get("email", ""),
                            data.get("vehicle_no", ""),
                            data.get("township", ""),
                            data.get("address", ""),
                            data.get("notes", ""),
                            float(data.get("credit_balance", 0)),
                            int(data.get("route_order", 0)),
                            data.get("preferred_visit_time", ""),
                        )
                        results.append({"kind": kind, "ok": True, "result": customer})
                    elif kind == "update_customer":
                        _require_roles(user, {"admin", "cashier", "storekeeper", "sales_staff"})
                        customer = pos.update_customer(int(data["id"]), data)
                        results.append({"kind": kind, "ok": True, "result": customer})
                    else:
                        results.append({"kind": kind, "ok": False, "error": "Unsupported action"})
                except Exception as ex:
                    results.append({"kind": kind, "ok": False, "error": str(ex)})

            _json_response(self, HTTPStatus.OK, {"results": results})
        except PermissionError as e:
            _json_response(self, HTTPStatus.FORBIDDEN, {"error": str(e)})


def run_server(host: str = "127.0.0.1", port: int = 8000) -> None:
    server = ThreadingHTTPServer((host, port), POSApiHandler)
    print(f"POS Web UI running at http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run the POS API server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()
    run_server(host=args.host, port=args.port)
