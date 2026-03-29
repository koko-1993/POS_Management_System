from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from .models import CartItem
from .security import chained_record_hash, stable_hash
from .store import Store


class POSService:
    PAYMENT_OPTIONS = ["cash", "card", "mobile_wallet", "bank_transfer"]
    LOW_STOCK_ALERT_AT = 50

    def __init__(self, store: Store):
        self.store = store
        self.cart: dict[str, CartItem] = {}

    def list_products(self) -> list[dict[str, Any]]:
        products = self.store.get_data()["products"]
        result = []
        for p in products:
            item = dict(p)
            item["low_stock"] = item["stock"] <= self.LOW_STOCK_ALERT_AT
            result.append(item)
        return result

    @staticmethod
    def _unit_price_for_quantity(product: dict[str, Any], qty: int) -> float:
        tiers = sorted(
            product.get("price_tiers", [{"min_qty": 1, "unit_price": product.get("price", 0)}]),
            key=lambda row: int(row.get("min_qty", 1)),
        )
        selected = round(float(product.get("price", 0)), 2)
        for tier in tiers:
            if qty >= int(tier.get("min_qty", 1)):
                selected = round(float(tier.get("unit_price", product.get("price", 0))), 2)
        return selected

    def list_categories(self) -> list[str]:
        return sorted({p.get("category", "General") for p in self.store.get_data()["products"]})

    def list_promotions(self, active_only: bool = True) -> list[dict[str, Any]]:
        promotions = self.store.get_data().get("promotions", [])
        if active_only:
            promotions = [p for p in promotions if p.get("active", False)]
        return promotions

    def add_promotion(
        self,
        code: str,
        promo_type: str,
        value: float,
        min_subtotal: float = 0,
        category: str = "",
        description: str = "",
    ) -> None:
        data = self.store.get_data()
        normalized_code = code.strip().upper()
        if any(p["code"] == normalized_code for p in data.get("promotions", [])):
            raise ValueError(f"Promotion already exists: {normalized_code}")
        if promo_type not in {"percentage", "fixed"}:
            raise ValueError("Promotion type must be percentage or fixed")
        if value <= 0:
            raise ValueError("Promotion value must be > 0")

        data["promotions"].append(
            {
                "code": normalized_code,
                "type": promo_type,
                "value": round(float(value), 2),
                "active": True,
                "min_subtotal": round(float(min_subtotal), 2),
                "category": category.strip(),
                "description": description.strip(),
            }
        )
        self.store.save_data(data)

    def add_product(
        self,
        sku: str,
        name: str,
        price: float,
        stock: int,
        category: str = "General",
        unit: str = "item",
        low_stock_threshold: int = 10,
        cost_price: float | None = None,
    ) -> None:
        data = self.store.get_data()
        normalized_sku = sku.strip().upper()
        if any(p["sku"] == normalized_sku for p in data["products"]):
            raise ValueError(f"SKU already exists: {normalized_sku}")

        if low_stock_threshold < 0:
            raise ValueError("Low stock threshold cannot be negative")
        if cost_price is None:
            cost_price = round(float(price) * 0.75, 2)

        data["products"].append(
            {
                "sku": normalized_sku,
                "name": name.strip(),
                "price": round(float(price), 2),
                "cost_price": round(float(cost_price), 2),
                "stock": int(stock),
                "category": category.strip() or "General",
                "unit": unit.strip() or "item",
                "low_stock_threshold": int(low_stock_threshold),
            }
        )
        self.store.save_data(data)

    def update_stock(self, sku: str, delta: int) -> None:
        data = self.store.get_data()
        for p in data["products"]:
            if p["sku"] == sku:
                next_stock = p["stock"] + int(delta)
                if next_stock < 0:
                    raise ValueError("Stock cannot be negative")
                p["stock"] = next_stock
                self.store.save_data(data)
                return
        raise ValueError(f"SKU not found: {sku}")

    def update_product(self, sku: str, payload: dict[str, Any]) -> dict[str, Any]:
        data = self.store.get_data()
        product = next((p for p in data["products"] if p["sku"] == sku), None)
        if not product:
            raise ValueError(f"SKU not found: {sku}")

        for field in ["name", "category", "unit"]:
            if field in payload:
                product[field] = str(payload[field]).strip()

        for field in ["price", "cost_price"]:
            if field in payload:
                product[field] = round(float(payload[field]), 2)

        if "low_stock_threshold" in payload:
            threshold = int(payload["low_stock_threshold"])
            if threshold < 0:
                raise ValueError("Low stock threshold cannot be negative")
            product["low_stock_threshold"] = threshold

        self.store.save_data(data)
        return product

    def delete_product(self, sku: str) -> None:
        data = self.store.get_data()
        products = data["products"]
        idx = next((i for i, p in enumerate(products) if p["sku"] == sku), None)
        if idx is None:
            raise ValueError(f"SKU not found: {sku}")
        products.pop(idx)
        self.store.save_data(data)

    def inventory_report(self) -> dict[str, Any]:
        products = self.list_products()
        total_stock_units = sum(int(p["stock"]) for p in products)
        inventory_cost_value = round(sum(float(p["cost_price"]) * int(p["stock"]) for p in products), 2)
        inventory_sale_value = round(sum(float(p["price"]) * int(p["stock"]) for p in products), 2)
        category_counts: dict[str, int] = {}
        for p in products:
            category_counts[p["category"]] = category_counts.get(p["category"], 0) + 1

        return {
            "total_products": len(products),
            "total_stock_units": total_stock_units,
            "inventory_cost_value": inventory_cost_value,
            "inventory_sale_value": inventory_sale_value,
            "category_counts": category_counts,
            "low_stock_alerts": self.get_low_stock_alerts(),
            "products": products,
        }

    def get_low_stock_alerts(self) -> list[dict[str, Any]]:
        alerts: list[dict[str, Any]] = []
        for p in self.store.get_data()["products"]:
            if p["stock"] <= self.LOW_STOCK_ALERT_AT:
                alerts.append(
                    {
                        "sku": p["sku"],
                        "name": p["name"],
                        "category": p.get("category", "General"),
                        "stock": p["stock"],
                        "threshold": self.LOW_STOCK_ALERT_AT,
                        "severity": "critical" if p["stock"] <= 10 else "warning",
                    }
                )
        return alerts

    def list_customers(self) -> list[dict[str, Any]]:
        return self.store.get_data().get("customers", [])

    def list_teams(self) -> list[dict[str, Any]]:
        return self.store.get_data().get("teams", [])

    def team_code_for_township(self, township: str) -> str:
        normalized_township = str(township).strip()
        for team in self.store.get_data().get("teams", []):
            townships = team.get("townships", [])
            if not isinstance(townships, list):
                townships = []
            if not townships and str(team.get("township", "")).strip():
                townships = [str(team.get("township", "")).strip()]
            if normalized_township in {str(label).strip() for label in townships}:
                return str(team.get("code", "")).strip().upper()
        return ""

    def _sync_customer_team_codes(self, data: dict[str, Any]) -> None:
        township_to_code: dict[str, str] = {}
        for team in data.get("teams", []):
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
                    township_to_code[label] = code
        for customer in data.get("customers", []):
            customer["team_code"] = township_to_code.get(str(customer.get("township", "")).strip(), "")

    @staticmethod
    def _next_team_code(teams: list[dict[str, Any]]) -> str:
        return f"TEAM{((max((int(team['id']) for team in teams), default=0) + 1) if teams else 1):03d}"

    @staticmethod
    def _normalized_team_townships(payload: dict[str, Any]) -> list[str]:
        raw_townships = payload.get("townships", [])
        if not isinstance(raw_townships, list):
            raw_townships = []
        if not raw_townships and str(payload.get("township", "")).strip():
            raw_townships = [str(payload.get("township", "")).strip()]
        cleaned: list[str] = []
        seen: set[str] = set()
        for township in raw_townships:
            label = str(township).strip()
            if label and label not in seen:
                cleaned.append(label)
                seen.add(label)
        return cleaned

    def _normalized_item_targets(self, targets: Any) -> list[dict[str, Any]]:
        if not isinstance(targets, list):
            return []
        products = {
            str(product.get("sku", "")).strip().upper(): product
            for product in self.store.get_data().get("products", [])
        }
        cleaned: list[dict[str, Any]] = []
        seen: set[str] = set()
        for target in targets:
            sku = str(target.get("sku", "")).strip().upper()
            if not sku or sku in seen:
                continue
            product = products.get(sku)
            if not product:
                raise ValueError(f"Unknown product SKU for team target: {sku}")
            cleaned.append(
                {
                    "sku": sku,
                    "name": str(product.get("name", "")).strip(),
                    "quantity": max(0, int(target.get("quantity", 0))),
                }
            )
            seen.add(sku)
        return cleaned

    def _validate_team_townships(
        self,
        teams: list[dict[str, Any]],
        townships: list[str],
        current_team_id: int | None = None,
    ) -> None:
        assigned: dict[str, str] = {}
        for row in teams:
            if current_team_id is not None and int(row.get("id", 0)) == int(current_team_id):
                continue
            row_townships = row.get("townships", [])
            if not isinstance(row_townships, list):
                row_townships = []
            if not row_townships and str(row.get("township", "")).strip():
                row_townships = [str(row.get("township", "")).strip()]
            for township in row_townships:
                label = str(township).strip()
                if label:
                    assigned[label] = str(row.get("name", row.get("code", ""))).strip() or str(row.get("code", ""))

        conflicts = [township for township in townships if township in assigned]
        if conflicts:
            raise ValueError(f"Township already assigned: {', '.join(conflicts)}")

    def create_team(
        self,
        name: str,
        sales_man_name: str,
        position: str,
        phone: str,
        township: str = "",
        townships: list[str] | None = None,
        item_targets: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        data = self.store.get_data()
        teams = data.setdefault("teams", [])
        normalized_townships = self._normalized_team_townships(
            {"township": township, "townships": townships or []}
        )
        normalized_targets = self._normalized_item_targets(item_targets or [])
        self._validate_team_townships(teams, normalized_townships)

        next_id = (max((int(team["id"]) for team in teams), default=0) + 1) if teams else 1
        team = {
            "id": next_id,
            "code": self._next_team_code(teams),
            "name": name.strip(),
            "sales_man_name": sales_man_name.strip(),
            "position": position.strip(),
            "phone": phone.strip(),
            "township": normalized_townships[0] if normalized_townships else "",
            "townships": normalized_townships,
            "item_targets": normalized_targets,
        }
        teams.append(team)
        self._sync_customer_team_codes(data)
        self.store.save_data(data)
        return team

    def update_team(self, team_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        data = self.store.get_data()
        teams = data.setdefault("teams", [])
        team = next((row for row in teams if int(row.get("id", 0)) == int(team_id)), None)
        if not team:
            raise ValueError(f"Team not found: {team_id}")

        next_townships = self._normalized_team_townships(
            {
                "township": payload.get("township", team.get("township", "")),
                "townships": payload.get("townships", team.get("townships", [])),
            }
        )
        self._validate_team_townships(teams, next_townships, team_id)

        team["name"] = str(payload.get("name", team.get("name", ""))).strip()
        team["sales_man_name"] = str(payload.get("sales_man_name", team.get("sales_man_name", ""))).strip()
        team["position"] = str(payload.get("position", team.get("position", ""))).strip()
        team["phone"] = str(payload.get("phone", team.get("phone", ""))).strip()
        team["townships"] = next_townships
        team["township"] = next_townships[0] if next_townships else ""
        if "item_targets" in payload:
            team["item_targets"] = self._normalized_item_targets(payload.get("item_targets", []))
        self._sync_customer_team_codes(data)
        self.store.save_data(data)
        return team

    def delete_team(self, team_id: int) -> None:
        data = self.store.get_data()
        teams = data.setdefault("teams", [])
        idx = next((i for i, team in enumerate(teams) if int(team.get("id", 0)) == int(team_id)), None)
        if idx is None:
            raise ValueError(f"Team not found: {team_id}")
        teams.pop(idx)
        self._sync_customer_team_codes(data)
        self.store.save_data(data)

    def create_customer(
        self,
        name: str,
        phone: str,
        email: str = "",
        vehicle_no: str = "",
        township: str = "",
        address: str = "",
        notes: str = "",
        credit_balance: float = 0.0,
        route_order: int = 0,
        preferred_visit_time: str = "",
    ) -> dict[str, Any]:
        data = self.store.get_data()
        customers = data.setdefault("customers", [])

        next_id = (max((int(c["id"]) for c in customers), default=0) + 1) if customers else 1
        now = datetime.now().isoformat(timespec="seconds")
        normalized_township = township.strip()
        customer = {
            "id": next_id,
            "name": name.strip(),
            "phone": phone.strip(),
            "email": email.strip(),
            "vehicle_no": vehicle_no.strip(),
            "township": normalized_township,
            "address": address.strip(),
            "notes": notes.strip(),
            "team_code": self.team_code_for_township(normalized_township),
            "loyalty_points": 0,
            "credit_balance": round(float(credit_balance), 2),
            "route_order": int(route_order),
            "preferred_visit_time": preferred_visit_time.strip(),
            "last_visit_at": "",
            "last_latitude": None,
            "last_longitude": None,
            "created_at": now,
            "updated_at": now,
        }
        customers.append(customer)
        self.store.save_data(data)
        return customer

    def update_customer(self, customer_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        data = self.store.get_data()
        customers = data.setdefault("customers", [])
        for customer in customers:
            if int(customer["id"]) == int(customer_id):
                for field in ["name", "phone", "email", "vehicle_no", "township", "address", "notes", "preferred_visit_time"]:
                    if field in payload:
                        customer[field] = str(payload[field]).strip()
                if "loyalty_points" in payload:
                    customer["loyalty_points"] = int(payload["loyalty_points"])
                if "credit_balance" in payload:
                    customer["credit_balance"] = round(float(payload["credit_balance"]), 2)
                if "route_order" in payload:
                    customer["route_order"] = int(payload["route_order"])
                if "last_visit_at" in payload:
                    customer["last_visit_at"] = str(payload["last_visit_at"]).strip()
                if "last_latitude" in payload:
                    customer["last_latitude"] = None if payload["last_latitude"] in ("", None) else float(payload["last_latitude"])
                if "last_longitude" in payload:
                    customer["last_longitude"] = None if payload["last_longitude"] in ("", None) else float(payload["last_longitude"])
                if "township" in payload:
                    customer["team_code"] = self.team_code_for_township(customer.get("township", ""))
                customer["updated_at"] = datetime.now().isoformat(timespec="seconds")
                self.store.save_data(data)
                return customer
        raise ValueError(f"Customer not found: {customer_id}")

    def route_plan(self, team_code: str = "") -> list[dict[str, Any]]:
        customers = [
            customer
            for customer in self.store.get_data().get("customers", [])
            if not team_code or str(customer.get("team_code", "")).strip().upper() == team_code.strip().upper()
        ]

        def sort_key(customer: dict[str, Any]) -> tuple[Any, ...]:
            route_order = int(customer.get("route_order", 0))
            last_visit = str(customer.get("last_visit_at", ""))
            credit = -float(customer.get("credit_balance", 0))
            return (
                0 if route_order > 0 else 1,
                route_order if route_order > 0 else 9999,
                last_visit or "0000-00-00T00:00:00",
                credit,
                str(customer.get("name", "")),
            )

        result: list[dict[str, Any]] = []
        for index, customer in enumerate(sorted(customers, key=sort_key), start=1):
            reason = "Manual route order" if int(customer.get("route_order", 0)) > 0 else "Follow up overdue"
            if float(customer.get("credit_balance", 0)) > 0:
                reason = "Credit collection due"
            result.append(
                {
                    "customer_id": int(customer["id"]),
                    "customer_name": str(customer.get("name", "")),
                    "address": str(customer.get("address", "")),
                    "phone": str(customer.get("phone", "")),
                    "sequence": index,
                    "priority_reason": reason,
                    "credit_balance": round(float(customer.get("credit_balance", 0)), 2),
                    "last_visit_at": str(customer.get("last_visit_at", "")),
                }
            )
        return result

    def customer_insights(self, customer_id: int) -> dict[str, Any]:
        data = self.store.get_data()
        customer = next((row for row in data.get("customers", []) if int(row.get("id", 0)) == int(customer_id)), None)
        if not customer:
            raise ValueError(f"Customer not found: {customer_id}")

        sales = [
            sale
            for sale in data.get("sales", [])
            if sale.get("customer") and int(sale["customer"].get("id", 0)) == int(customer_id)
        ]
        sales.sort(key=lambda row: str(row.get("timestamp", "")), reverse=True)
        item_totals: dict[str, int] = {}
        total_spent = 0.0
        for sale in sales:
            total_spent += float(sale.get("invoice_total", sale.get("grand_total", 0)))
            for item in sale.get("items", []):
                name = str(item.get("name", "")).strip()
                item_totals[name] = item_totals.get(name, 0) + int(item.get("quantity", 0))

        favorite_items = [name for name, _qty in sorted(item_totals.items(), key=lambda row: row[1], reverse=True)[:3]]
        return {
            "customer_id": int(customer["id"]),
            "credit_balance": round(float(customer.get("credit_balance", 0)), 2),
            "last_purchase_at": str(sales[0].get("timestamp", "")) if sales else "",
            "favorite_items": favorite_items,
            "recent_receipts": sales[:5],
            "total_spent": round(total_spent, 2),
        }

    def sales_staff_dashboard(self, username: str) -> dict[str, Any]:
        data = self.store.get_data()
        today_key = date.today().isoformat()
        daily = data.get("employee_daily_sales", {}).get(today_key, {}).get(username, {})
        target_config = data.get("sales_targets", {}).get(username) or data.get("sales_targets", {}).get("salestaff", {})
        today_sales = round(float(daily.get("revenue", 0)), 2)
        daily_target = round(float(target_config.get("daily_target", 0)), 2)
        completion_pct = round((today_sales / daily_target) * 100, 2) if daily_target > 0 else 0.0
        commission_rate = float(target_config.get("commission_rate", 0))
        estimated_commission = round(today_sales * commission_rate, 2)
        return {
            "date": today_key,
            "today_sales": today_sales,
            "daily_target": daily_target,
            "completion_pct": completion_pct,
            "estimated_commission": estimated_commission,
            "commission_rate": commission_rate,
            "promotions": self.list_promotions(active_only=True),
        }

    def field_force_dashboard(self) -> list[dict[str, Any]]:
        data = self.store.get_data()
        today_key = date.today().isoformat()
        today_sales = data.get("employee_daily_sales", {}).get(today_key, {})
        sales_staff = [user for user in data.get("users", []) if user.get("role") == "sales_staff"]
        sales = data.get("sales", [])
        dashboard: list[dict[str, Any]] = []
        for user in sales_staff:
            username = str(user.get("username", ""))
            latest_sale = next((sale for sale in reversed(sales) if sale.get("cashier") == username), None)
            dashboard.append(
                {
                    "username": username,
                    "today_sales": round(float(today_sales.get(username, {}).get("revenue", 0)), 2),
                    "transactions": int(today_sales.get(username, {}).get("transactions", 0)),
                    "last_invoice_id": str(latest_sale.get("invoice_id", "")) if latest_sale else "",
                    "last_seen_at": str((latest_sale.get("location") or {}).get("captured_at", latest_sale.get("timestamp", "") if latest_sale else "")),
                    "location": latest_sale.get("location") if latest_sale else None,
                }
            )
        return dashboard

    def delete_customer(self, customer_id: int) -> None:
        data = self.store.get_data()
        customers = data.setdefault("customers", [])
        idx = next((i for i, c in enumerate(customers) if int(c["id"]) == int(customer_id)), None)
        if idx is None:
            raise ValueError(f"Customer not found: {customer_id}")
        customers.pop(idx)
        self.store.save_data(data)

    def start_shift(self, username: str) -> dict[str, Any]:
        data = self.store.get_data()
        shifts = data.setdefault("shifts", [])

        if any(s["username"] == username and not s.get("end") for s in shifts):
            raise ValueError(f"Shift already open for {username}")

        next_id = (max((int(s["id"]) for s in shifts), default=0) + 1) if shifts else 1
        now = datetime.now().isoformat(timespec="seconds")
        shift = {
            "id": next_id,
            "username": username,
            "start": now,
            "end": "",
            "transactions": 0,
            "revenue": 0.0,
            "profit": 0.0,
        }
        shifts.append(shift)
        self.store.save_data(data)
        return shift

    def end_shift(self, username: str) -> dict[str, Any]:
        data = self.store.get_data()
        shifts = data.setdefault("shifts", [])
        for shift in reversed(shifts):
            if shift["username"] == username and not shift.get("end"):
                shift["end"] = datetime.now().isoformat(timespec="seconds")
                self.store.save_data(data)
                return shift
        raise ValueError(f"No active shift found for {username}")

    def list_shifts(self, for_date: str = "") -> list[dict[str, Any]]:
        shifts = self.store.get_data().get("shifts", [])
        if not for_date:
            return shifts
        return [s for s in shifts if str(s.get("start", "")).startswith(for_date)]

    def add_to_cart(self, sku: str, qty: int) -> None:
        if qty <= 0:
            raise ValueError("Quantity must be > 0")

        data = self.store.get_data()
        product = next((p for p in data["products"] if p["sku"] == sku), None)
        if not product:
            raise ValueError(f"SKU not found: {sku}")

        existing_qty = self.cart[sku].quantity if sku in self.cart else 0
        if product["stock"] < existing_qty + qty:
            raise ValueError("Insufficient stock")

        if sku in self.cart:
            self.cart[sku].quantity += qty
            self.cart[sku].unit_price = self._unit_price_for_quantity(product, self.cart[sku].quantity)
        else:
            self.cart[sku] = CartItem(
                sku=product["sku"],
                name=product["name"],
                unit_price=self._unit_price_for_quantity(product, qty),
                quantity=qty,
            )

    def remove_from_cart(self, sku: str, qty: int) -> None:
        if sku not in self.cart:
            raise ValueError(f"SKU not in cart: {sku}")
        if qty <= 0:
            raise ValueError("Quantity must be > 0")

        self.cart[sku].quantity -= qty
        if self.cart[sku].quantity <= 0:
            del self.cart[sku]

    def view_cart(self) -> list[CartItem]:
        return list(self.cart.values())

    def cart_total(self) -> float:
        return round(sum(item.line_total for item in self.cart.values()), 2)

    def _promotion_discount(self, promo_code: str, cart_items: list[dict[str, Any]]) -> tuple[float, dict[str, Any] | None]:
        if not promo_code:
            return 0.0, None

        promotions = self.store.get_data().get("promotions", [])
        promo = next((p for p in promotions if p.get("code", "").upper() == promo_code.upper()), None)
        if not promo or not promo.get("active", False):
            raise ValueError("Invalid or inactive promotion code")

        category = promo.get("category", "").strip()
        applicable_items = cart_items
        if category:
            sku_to_category = {p["sku"]: p.get("category", "") for p in self.store.get_data()["products"]}
            applicable_items = [i for i in cart_items if sku_to_category.get(i["sku"], "") == category]

        applicable_subtotal = round(sum(i["line_total"] for i in applicable_items), 2)
        if applicable_subtotal <= 0:
            raise ValueError("Promotion not applicable to selected cart items")

        min_subtotal = float(promo.get("min_subtotal", 0))
        if applicable_subtotal < min_subtotal:
            raise ValueError(f"Promotion requires minimum subtotal of {min_subtotal}")

        if promo["type"] == "percentage":
            promo_discount = round(applicable_subtotal * (float(promo["value"]) / 100), 2)
        else:
            promo_discount = min(round(float(promo["value"]), 2), applicable_subtotal)

        meta = {
            "code": promo["code"],
            "type": promo["type"],
            "value": float(promo["value"]),
            "category": category,
            "discount": promo_discount,
        }
        return promo_discount, meta

    def _validate_payments(self, payments: list[dict[str, Any]], grand_total: float) -> tuple[list[dict[str, Any]], float, float]:
        if not payments:
            payments = [{"method": "cash", "amount": grand_total}]

        normalized: list[dict[str, Any]] = []
        total_paid = 0.0
        for payment in payments:
            method = str(payment.get("method", "")).strip()
            amount = round(float(payment.get("amount", 0)), 2)
            if method not in self.PAYMENT_OPTIONS:
                raise ValueError(f"Unsupported payment method: {method}")
            if amount <= 0:
                raise ValueError("Payment amount must be > 0")
            normalized.append({"method": method, "amount": amount})
            total_paid += amount

        total_paid = round(total_paid, 2)
        if total_paid < grand_total:
            raise ValueError("Insufficient payment amount")

        return normalized, total_paid, round(total_paid - grand_total, 2)

    def _build_checkout_items(self, data: dict[str, Any], payload_items: list[dict[str, Any]] | None) -> tuple[list[dict[str, Any]], float, float]:
        requested_items = payload_items or []
        if requested_items:
            cart_entries: list[dict[str, Any]] = []
            for raw_item in requested_items:
                sku = str(raw_item.get("sku", "")).strip().upper()
                quantity = int(raw_item.get("quantity", 0))
                if not sku:
                    raise ValueError("Checkout item sku is required")
                if quantity <= 0:
                    raise ValueError("Checkout item quantity must be > 0")
                product = next((p for p in data["products"] if p["sku"] == sku), None)
                if not product:
                    raise ValueError(f"SKU not found during checkout: {sku}")
                cart_entries.append(
                    {
                        "sku": product["sku"],
                        "name": product["name"],
                        "unit_price": self._unit_price_for_quantity(product, quantity),
                        "quantity": quantity,
                        "line_total": round(self._unit_price_for_quantity(product, quantity) * quantity, 2),
                    }
                )
        else:
            if not self.cart:
                raise ValueError("Cart is empty")
            cart_entries = [
                {
                    "sku": cart_item.sku,
                    "name": cart_item.name,
                    "unit_price": round(float(cart_item.unit_price), 2),
                    "quantity": cart_item.quantity,
                    "line_total": round(float(cart_item.line_total), 2),
                }
                for cart_item in self.cart.values()
            ]

        items: list[dict[str, Any]] = []
        total_cost = 0.0
        subtotal = 0.0
        for cart_entry in cart_entries:
            product = next((p for p in data["products"] if p["sku"] == cart_entry["sku"]), None)
            if not product:
                raise ValueError(f"SKU not found during checkout: {cart_entry['sku']}")
            if product["stock"] < cart_entry["quantity"]:
                raise ValueError(f"Insufficient stock during checkout: {cart_entry['sku']}")

            product["stock"] -= cart_entry["quantity"]
            line_cost = round(float(product.get("cost_price", 0)) * cart_entry["quantity"], 2)
            total_cost += line_cost
            subtotal += float(cart_entry["line_total"])
            items.append(
                {
                    "sku": cart_entry["sku"],
                    "name": cart_entry["name"],
                    "unit_price": round(float(cart_entry["unit_price"]), 2),
                    "unit_cost": round(float(product.get("cost_price", 0)), 2),
                    "quantity": cart_entry["quantity"],
                    "line_total": round(float(cart_entry["line_total"]), 2),
                    "line_cost": line_cost,
                }
            )

        return items, round(subtotal, 2), round(total_cost, 2)

    def _record_employee_sale(self, data: dict[str, Any], cashier: str, revenue: float, profit: float) -> None:
        day_key = date.today().isoformat()
        daily = data.setdefault("employee_daily_sales", {})
        day_obj = daily.setdefault(day_key, {})
        employee = day_obj.setdefault(cashier, {"transactions": 0, "revenue": 0.0, "profit": 0.0})
        employee["transactions"] += 1
        employee["revenue"] = round(float(employee["revenue"]) + revenue, 2)
        employee["profit"] = round(float(employee["profit"]) + profit, 2)

        for shift in reversed(data.setdefault("shifts", [])):
            if shift["username"] == cashier and not shift.get("end"):
                shift["transactions"] = int(shift.get("transactions", 0)) + 1
                shift["revenue"] = round(float(shift.get("revenue", 0)) + revenue, 2)
                shift["profit"] = round(float(shift.get("profit", 0)) + profit, 2)
                break

    def _append_audit(
        self,
        data: dict[str, Any],
        username: str,
        action: str,
        target: str,
        details: dict[str, Any] | None = None,
        device_id: str = "",
    ) -> None:
        logs = data.setdefault("audit_logs", [])
        logs.append(
            {
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "username": username,
                "action": action,
                "target": target,
                "device_id": device_id,
                "details_hash": stable_hash(details or {}),
            }
        )

    def checkout(
        self,
        discount_pct: float = 0.0,
        cashier: str = "",
        promo_code: str = "",
        payments: list[dict[str, Any]] | None = None,
        items_payload: list[dict[str, Any]] | None = None,
        customer_id: int | None = None,
        idempotency_key: str = "",
        device_id: str = "",
        location: dict[str, Any] | None = None,
        visit_note: str = "",
        generate_tax_invoice: bool = False,
        tax_rate: float = 0.0,
        tax_tin: str = "",
    ) -> dict[str, Any]:
        if discount_pct < 0 or discount_pct > 100:
            raise ValueError("Discount must be between 0 and 100")

        data = self.store.get_data()
        if idempotency_key:
            previous_invoice = data.setdefault("idempotency_keys", {}).get(idempotency_key)
            if previous_invoice:
                existing = next((s for s in data.get("sales", []) if s["invoice_id"] == previous_invoice), None)
                if existing:
                    return existing

        items, subtotal, total_cost = self._build_checkout_items(data, items_payload)
        manual_discount = round(subtotal * (discount_pct / 100), 2)
        promo_discount, promo_meta = self._promotion_discount(promo_code.strip(), items)
        total_discount = round(min(subtotal, manual_discount + promo_discount), 2)
        grand_total = round(subtotal - total_discount, 2)
        if tax_rate < 0:
            raise ValueError("Tax rate cannot be negative")
        tax_amount = round(grand_total * (tax_rate / 100), 2) if generate_tax_invoice else 0.0
        invoice_total = round(grand_total + tax_amount, 2)
        total_cost = round(total_cost, 2)
        gross_profit = round(grand_total - total_cost, 2)

        payment_list, total_paid, change_due = self._validate_payments(payments or [], invoice_total)

        customer = None
        if customer_id is not None:
            customer = next(
                (c for c in data.get("customers", []) if int(c["id"]) == int(customer_id)),
                None,
            )
            if not customer:
                raise ValueError(f"Customer not found: {customer_id}")
            customer["loyalty_points"] = int(customer.get("loyalty_points", 0)) + int(grand_total // 10)
            customer["updated_at"] = datetime.now().isoformat(timespec="seconds")
            customer["last_visit_at"] = datetime.now().isoformat(timespec="seconds")
            if location:
                customer["last_latitude"] = float(location.get("latitude", 0))
                customer["last_longitude"] = float(location.get("longitude", 0))

        receipt = {
            "business_name": "Shwe Htoo Thit",
            "invoice_id": f"{len(data['sales']) + 1:06d}",
            "timestamp": datetime.now().isoformat(timespec="seconds"),
            "cashier": cashier,
            "customer": customer,
            "items": items,
            "location": {
                "latitude": float(location.get("latitude", 0)),
                "longitude": float(location.get("longitude", 0)),
                "accuracy": float(location.get("accuracy", 0)),
                "captured_at": str(location.get("captured_at", datetime.now().isoformat(timespec="seconds"))),
            } if location else None,
            "visit_note": visit_note.strip(),
            "subtotal": subtotal,
            "discount_pct": discount_pct,
            "manual_discount": manual_discount,
            "promo_discount": promo_discount,
            "discount": total_discount,
            "promotion": promo_meta,
            "grand_total": grand_total,
            "tax_invoice": {
                "enabled": generate_tax_invoice,
                "tax_rate": round(float(tax_rate), 2),
                "tax_amount": tax_amount,
                "tax_tin": tax_tin.strip(),
            },
            "invoice_total": invoice_total,
            "total_cost": total_cost,
            "gross_profit": gross_profit,
            "payments": payment_list,
            "total_paid": total_paid,
            "change_due": change_due,
        }

        # Prevent accidental double-entry when idempotency header is missing.
        transaction_fingerprint = stable_hash(
            {
                "cashier": cashier,
                "customer_id": customer_id,
                "items": [{"sku": i["sku"], "qty": i["quantity"]} for i in items],
                "grand_total": grand_total,
                "payments": payment_list,
            }
        )
        last_sale = data.get("sales", [])[-1] if data.get("sales") else None
        if last_sale:
            last_timestamp = datetime.fromisoformat(last_sale["timestamp"])
            age_seconds = (datetime.now() - last_timestamp).total_seconds()
            last_fingerprint = stable_hash(
                {
                    "cashier": last_sale.get("cashier", ""),
                    "customer_id": (last_sale.get("customer") or {}).get("id"),
                    "items": [{"sku": i["sku"], "qty": i["quantity"]} for i in last_sale.get("items", [])],
                    "grand_total": float(last_sale.get("grand_total", 0)),
                    "payments": [
                        {"method": p.get("method"), "amount": float(p.get("amount", 0))}
                        for p in last_sale.get("payments", [])
                    ],
                }
            )
            if transaction_fingerprint == last_fingerprint and age_seconds <= 90:
                return last_sale

        previous_hash = data.get("sales_chain_last_hash", "")
        payload_for_hash = {
            "invoice_id": receipt["invoice_id"],
            "timestamp": receipt["timestamp"],
            "cashier": receipt["cashier"],
            "grand_total": receipt["grand_total"],
            "total_cost": receipt["total_cost"],
            "items": receipt["items"],
        }
        receipt["previous_hash"] = previous_hash
        receipt["integrity_hash"] = chained_record_hash(previous_hash, payload_for_hash)

        data.setdefault("sales", []).append(receipt)
        data["sales_chain_last_hash"] = receipt["integrity_hash"]
        if idempotency_key:
            data.setdefault("idempotency_keys", {})[idempotency_key] = receipt["invoice_id"]
        self._record_employee_sale(data, cashier or "unknown", grand_total, gross_profit)
        self._append_audit(
            data,
            cashier or "unknown",
            "checkout",
            receipt["invoice_id"],
            {
                "grand_total": grand_total,
                "items_count": len(receipt["items"]),
                "idempotency_key": idempotency_key,
            },
            device_id=device_id,
        )
        self.store.save_data(data)
        if not items_payload:
            self.cart.clear()
        return receipt

    @staticmethod
    def _period_start(period: str) -> date:
        today = date.today()
        if period == "daily":
            return today
        if period == "weekly":
            return today - timedelta(days=today.weekday())
        if period == "monthly":
            return today.replace(day=1)
        raise ValueError("Period must be daily, weekly, or monthly")

    def sales_report(self, period: str = "daily") -> dict[str, Any]:
        start = self._period_start(period)
        data = self.store.get_data()
        sales = [
            s
            for s in data.get("sales", [])
            if datetime.fromisoformat(s["timestamp"]).date() >= start
        ]

        total_sales = round(sum(float(s["grand_total"]) for s in sales), 2)
        total_profit = round(sum(float(s.get("gross_profit", 0)) for s in sales), 2)

        item_counts: dict[str, int] = {}
        for sale in sales:
            for item in sale["items"]:
                item_counts[item["name"]] = item_counts.get(item["name"], 0) + int(item["quantity"])

        return {
            "period": period,
            "from_date": start.isoformat(),
            "transactions": len(sales),
            "total_sales": total_sales,
            "total_profit": total_profit,
            "top_items": sorted(item_counts.items(), key=lambda x: x[1], reverse=True),
            "low_stock_alerts": self.get_low_stock_alerts(),
        }

    def employee_sales_report(self, for_date: str = "") -> dict[str, Any]:
        day_key = for_date or date.today().isoformat()
        daily = self.store.get_data().get("employee_daily_sales", {})
        return {"date": day_key, "employees": daily.get(day_key, {})}

    def profit_and_loss_report(self, period: str = "monthly") -> dict[str, Any]:
        start = self._period_start(period)
        sales = [
            s
            for s in self.store.get_data().get("sales", [])
            if datetime.fromisoformat(s["timestamp"]).date() >= start
        ]

        revenue = round(sum(float(s.get("grand_total", 0)) for s in sales), 2)
        cost = round(sum(float(s.get("total_cost", 0)) for s in sales), 2)
        gross_profit = round(revenue - cost, 2)

        return {
            "period": period,
            "from_date": start.isoformat(),
            "revenue": revenue,
            "cost": cost,
            "gross_profit": gross_profit,
            "transactions": len(sales),
        }

    def recent_receipts(self, limit: int = 20) -> list[dict[str, Any]]:
        sales = self.store.get_data().get("sales", [])
        return list(reversed(sales[-limit:]))

    def list_audit_logs(self, limit: int = 200) -> list[dict[str, Any]]:
        logs = self.store.get_data().get("audit_logs", [])
        return list(reversed(logs[-limit:]))
