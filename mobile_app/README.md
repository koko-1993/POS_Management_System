# Shwe Htoo Thit Flutter Mobile App

This directory contains a Flutter client for `sales_staff` and other selling roles.

## What Is Included
- Phone login with configurable backend URL
- Persistent device ID for backend authorization
- Quick product add
- Customer selection and creation
- Multi-payment checkout
- Recent invoice list

## Before Running
This environment did not have the Flutter SDK installed, so the Flutter source was created manually.
Generate the Android shell after installing Flutter:

```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter create . --platforms android
flutter pub get
```

## Run The Backend
From the project root:

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.api_server --host 0.0.0.0 --port 8000
```

## Authorize The Phone Device
Example:

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.device_manager authorize salestaff MOBILE-SALES-01
```

## Run The Flutter App
Use the same device ID inside the login screen:

```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter run
```

## Login Example
- Backend URL: `http://192.168.x.x:8000`
- Username: `salestaff`
- Password: `sales123`
- Device ID: `MOBILE-SALES-01`
