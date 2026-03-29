# Shwe Htoo Thit POS System (Python + React)

A lightweight Point-of-Sale management system you can run in terminal.

## Features
- Role-based login (`admin`, `cashier`, `storekeeper`, `sales_staff`)
- Strong password policy support and optional admin 2FA
- Shift tracking with daily sales by employee
- Daily / Weekly / Monthly sales reports
- Inventory reports
- Profit & Loss reports (revenue vs cost)
- Product catalog with categories (`Fuel types`, `Additives`, `Lubricants`, `Packaging`)
- Stock tracking with low-stock threshold alerts
- Customer list CRUD for all roles
- Checkout with invoice/receipt generation
- Multiple payment options (`cash`, `card`, `mobile_wallet`, `bank_transfer`)
- Discounts & promotions (manual discount + promo code)
- Offline action queue in UI with sync when connection returns
- Invoice export to CSV and PDF
- Printer support from UI (thermal layout and A4 print layout)
- Multi-language UI switch (English / Burmese)
- Frontend fast-action buttons for busy counters (quick SKU, quick qty, quick cash)
- Improved checkout validation for stock/payment errors
- Optional tax invoice metadata (`generate_tax_invoice`, `tax_rate`, `tax_tin`)
- Persistent storage in SQLite
- Encryption at rest for sensitive customer/payment data
- Daily automatic backup (local + cloud mock folder)
- Idempotency + duplicate-entry protection for checkout
- Tamper-evident sales integrity hash chain
- Audit trail log (`who` did `what` transaction and from which device)
- POS device restriction using `X-Device-ID`

## Run
```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.cli
```

## Run Web UI (React + Python API)
```bash
cd /home/lenovo/Desktop/POS_system_management
pip install -r requirements.txt
python3 -m src.pos.api_server
```
Open:
- `http://127.0.0.1:8000`
- Mobile sales app: `http://127.0.0.1:8000/mobile`

To allow phones on the same Wi-Fi network to connect:
```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.api_server --host 0.0.0.0 --port 8000
```

## Security Notes
- API requests include `X-Device-ID`; login is blocked for unauthorized terminals.
- Admin OTP/2FA is currently disabled by default for testing and demo deployments.
- Production note: set `POS_ENABLE_ADMIN_2FA=1` to re-enable OTP login for admin.
- When `POS_ENABLE_ADMIN_2FA=1`, admin login requires OTP (`otp_code`) in addition to username/password.
- Google Authenticator setup details can be shown with:
  ```bash
  cd /home/lenovo/Desktop/POS_system_management
  python3 -m src.pos.google_auth admin
  ```
- Sales accounts are created by admin from the `Accounts` screen and must be assigned to a sale team.
- Device authorization for sales phones is optional. If you set allowed devices for a sales account, only those phone IDs can log in.
- To allow a salesperson phone to log in when device restriction is enabled:
  ```bash
  cd /home/lenovo/Desktop/POS_system_management
  python3 -m src.pos.device_manager authorize <sales_username> MOBILE-SALES-01
  ```
- Change default passwords immediately; `AuthService.change_password` enforces strong passwords.
- Checkout supports `Idempotency-Key` header to avoid duplicate transactions on retry.
- Audit log endpoint for admin: `/api/audit-logs?limit=100`
- Sensitive fields are stored encrypted inside `data/pos_data.db`.
- Daily backups are written to:
  - `backups/local`
  - `backups/cloud_mock` (cloud-sync placeholder)
  - Backup files are SQLite copies named `pos_data_<timestamp>.db`

## Run tests
```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m unittest discover -s tests -v
```

## Flutter Mobile App
Flutter client source is available in:
- `mobile_app/`

Because Flutter SDK was not installed in this environment, install Flutter first and then generate the Android shell:

```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter create . --platforms android
flutter pub get
flutter run
```

See:
- `mobile_app/README.md`

## Data file
Data persists to:
- `data/pos_data.db`

## Default users
- Admin: `admin` / `admin123`
- Cashier: `cashier` / `cashier123`
- Storekeeper: `storekeeper` / `store123`
- Sales Staff: create accounts from the Admin `Accounts` screen
Note: Sales staff web access is disabled. Use the mobile app flow below.
Note: Admin OTP is intentionally disabled right now for testing/demo use.
Note: For real production, set `POS_ENABLE_ADMIN_2FA=1` and then configure the admin OTP secret from `data/pos_data.db`.

## Backup and Restore
- The app creates at most one automatic backup per day when data is saved.
- Backups are stored in:
  - `backups/local/pos_data_<timestamp>.db`
  - `backups/cloud_mock/pos_data_<timestamp>.db`
- To restore from a backup, replace the main database with a backup copy:

```bash
cd /home/lenovo/Desktop/POS_system_management
cp backups/local/pos_data_YYYYMMDD_HHMMSS.db data/pos_data.db
```

- You can inspect the database with:

```bash
sqlite3 data/pos_data.db ".tables"
sqlite3 data/pos_data.db "select state_key, length(payload) from app_state;"
```

## Mobile Sales Flow
1. Run the API server.
2. In the admin web console, open `Accounts` and create a `sales_staff` account assigned to a sale team.
3. If you want device restriction, authorize the phone device ID for that username. If you skip this step, the new sales account can log in from any phone:
   ```bash
   cd /home/lenovo/Desktop/POS_system_management
   python3 -m src.pos.device_manager authorize <sales_username> MOBILE-SALES-01
   ```
4. Open the mobile app at `http://127.0.0.1:8000/mobile`
5. Log in with:
   - Username: the sales account created by admin
   - Password: the password set for that account
   - Device ID: the same value you authorized, for example `MOBILE-SALES-01`, or any phone ID when device restriction is not enabled

## Invoice exports
Checkout automatically generates invoice files in:
- `exports/invoice_<invoice_id>.csv`
- `exports/invoice_<invoice_id>.pdf`
