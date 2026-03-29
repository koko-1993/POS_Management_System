from __future__ import annotations

import csv
from pathlib import Path
from typing import Any


class InvoiceExporter:
    def __init__(self, export_dir: str):
        self.export_dir = Path(export_dir)
        self.export_dir.mkdir(parents=True, exist_ok=True)

    def export_csv(self, receipt: dict[str, Any]) -> str:
        invoice_id = receipt["invoice_id"]
        file_path = self.export_dir / f"invoice_{invoice_id}.csv"
        with file_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["business_name", receipt.get("business_name", "Shwe Htoo Thit")])
            writer.writerow(["invoice_id", invoice_id])
            writer.writerow(["timestamp", receipt["timestamp"]])
            writer.writerow(["cashier", receipt.get("cashier", "")])
            writer.writerow([])
            writer.writerow(["sku", "name", "unit_price", "quantity", "line_total"])
            for item in receipt["items"]:
                writer.writerow(
                    [
                        item["sku"],
                        item["name"],
                        item["unit_price"],
                        item["quantity"],
                        item["line_total"],
                    ]
                )
            writer.writerow([])
            writer.writerow(["subtotal", receipt["subtotal"]])
            writer.writerow(["discount_pct", receipt.get("discount_pct", 0)])
            writer.writerow(["manual_discount", receipt.get("manual_discount", 0)])
            writer.writerow(["promo_discount", receipt.get("promo_discount", 0)])
            writer.writerow(["discount_total", receipt.get("discount", 0)])
            promo = receipt.get("promotion")
            writer.writerow(["promotion_code", promo.get("code", "") if promo else ""])
            writer.writerow(["grand_total", receipt["grand_total"]])
            tax = receipt.get("tax_invoice", {}) or {}
            writer.writerow(["tax_invoice_enabled", tax.get("enabled", False)])
            writer.writerow(["tax_rate", tax.get("tax_rate", 0)])
            writer.writerow(["tax_amount", tax.get("tax_amount", 0)])
            writer.writerow(["tax_tin", tax.get("tax_tin", "")])
            writer.writerow(["invoice_total", receipt.get("invoice_total", receipt["grand_total"])])
            writer.writerow(["total_paid", receipt.get("total_paid", receipt["grand_total"])])
            writer.writerow(["change_due", receipt.get("change_due", 0)])
            writer.writerow([])
            writer.writerow(["payment_method", "amount"])
            for payment in receipt.get("payments", []):
                writer.writerow([payment["method"], payment["amount"]])
        return str(file_path)

    def export_pdf(self, receipt: dict[str, Any]) -> str:
        invoice_id = receipt["invoice_id"]
        file_path = self.export_dir / f"invoice_{invoice_id}.pdf"

        lines = [
            receipt.get("business_name", "Shwe Htoo Thit"),
            f"Invoice ID: {invoice_id}",
            f"Timestamp: {receipt['timestamp']}",
            f"Cashier: {receipt.get('cashier', '')}",
            "",
            "Items:",
        ]
        for item in receipt["items"]:
            lines.append(
                f"{item['sku']} | {item['name']} | {item['quantity']} x {item['unit_price']} = {item['line_total']}"
            )

        promo = receipt.get("promotion")
        lines.extend(
            [
                "",
                f"Subtotal: {receipt['subtotal']}",
                f"Manual Discount: {receipt.get('manual_discount', 0)}",
                f"Promo Discount: {receipt.get('promo_discount', 0)}",
                f"Promotion Code: {promo.get('code', '') if promo else ''}",
                f"Grand Total: {receipt['grand_total']}",
                f"Tax Amount: {(receipt.get('tax_invoice', {}) or {}).get('tax_amount', 0)}",
                f"Invoice Total: {receipt.get('invoice_total', receipt['grand_total'])}",
                f"Total Paid: {receipt.get('total_paid', receipt['grand_total'])}",
                f"Change Due: {receipt.get('change_due', 0)}",
                "",
                "Payments:",
            ]
        )

        for payment in receipt.get("payments", []):
            lines.append(f"- {payment['method']}: {payment['amount']}")

        self._write_simple_pdf(file_path, lines)
        return str(file_path)

    def _write_simple_pdf(self, path: Path, lines: list[str]) -> None:
        escaped_lines = [line.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") for line in lines]

        content_lines = ["BT", "/F1 12 Tf", "72 760 Td", "14 TL"]
        first = True
        for line in escaped_lines:
            if first:
                content_lines.append(f"({line}) Tj")
                first = False
            else:
                content_lines.append(f"T* ({line}) Tj")
        content_lines.append("ET")
        content = "\n".join(content_lines).encode("latin-1", errors="replace")

        objects: list[bytes] = []
        objects.append(b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n")
        objects.append(b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n")
        objects.append(
            b"3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >> endobj\n"
        )
        objects.append(b"4 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n")
        objects.append(
            b"5 0 obj << /Length "
            + str(len(content)).encode("ascii")
            + b" >> stream\n"
            + content
            + b"\nendstream endobj\n"
        )

        pdf = bytearray(b"%PDF-1.4\n")
        offsets = [0]
        for obj in objects:
            offsets.append(len(pdf))
            pdf.extend(obj)

        xref_start = len(pdf)
        pdf.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
        pdf.extend(b"0000000000 65535 f \n")
        for off in offsets[1:]:
            pdf.extend(f"{off:010d} 00000 n \n".encode("ascii"))

        pdf.extend(
            b"trailer << /Size "
            + str(len(objects) + 1).encode("ascii")
            + b" /Root 1 0 R >>\nstartxref\n"
            + str(xref_start).encode("ascii")
            + b"\n%%EOF\n"
        )

        path.write_bytes(pdf)
