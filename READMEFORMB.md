# Shwe Htoo Thit Mobile App Guide

ဒီ file က `Flutter mobile app` အတွက်သပ်သပ်ဖတ်ရန် guide ပါ။

## Mobile App မှာ ပါတာတွေ
- phone ကနေ login ဝင်နိုင်ခြင်း
- backend URL ကို app ထဲမှာသတ်မှတ်နိုင်ခြင်း
- phone device ID ကိုသိမ်းထားပြီး authorized device နဲ့ပဲ login ဝင်နိုင်ခြင်း
- quick product add
- customer create / select
- multi-payment checkout
- recent invoice list

## Mobile App Source Folder
Flutter source code က ဒီ folder အောက်မှာရှိပါတယ်။

```text
/home/lenovo/Desktop/POS_system_management/mobile_app
```

## အရင်ဆုံး လိုအပ်တာ
ဒီ environment ထဲမှာ Flutter SDK မရှိသေးလို့ Android project shell ကို generate မလုပ်ရသေးပါဘူး။
သင့်စက်မှာ Flutter install လုပ်ပြီး အောက်က command တွေ run ပါ။

```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter create . --platforms android
flutter pub get
## Backend Server Run မယ်
Phone ကနေချိတ်သုံးမယ်ဆိုရင် server ကို LAN access ရအောင် `0.0.0.0` နဲ့ run ရပါမယ်။

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.api_server --host 0.0.0.0 --port 8000
```

## Phone Device ကို Authorize လုပ်မယ်
Sales staff ရဲ့ phone device ID ကို authorize လုပ်ပြီးမှ login ဝင်လို့ရပါမယ်။

Example:

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.device_manager authorize salestaff MOBILE-SALES-01
```

လိုချင်ရင် authorized devices list ကိုကြည့်လို့ရပါတယ်။

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.device_manager list salestaff
```

## Flutter App Run မယ်
```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter run
```

APK ထုတ်ချင်ရင်:

```bash
cd /home/lenovo/Desktop/POS_system_management/mobile_app
flutter build apk
```

## App ထဲမှာ Login ဝင်နည်း
- Backend URL: `http://192.168.x.x:8000`
- Username: `salestaff`
- Password: `sales123`
- Device ID: `MOBILE-SALES-01`

`192.168.x.x` နေရာမှာ backend run နေတဲ့ computer ရဲ့ local IP ကိုထည့်ရပါမယ်။

## Admin OTP လိုအပ်ရင်
Admin account အတွက် Google Authenticator setup info ကို ဒီ command နဲ့ထုတ်လို့ရပါတယ်။

```bash
cd /home/lenovo/Desktop/POS_system_management
python3 -m src.pos.google_auth admin
```

## Default Users
- Admin: `admin` / `admin123`
- Cashier: `cashier` / `cashier123`
- Storekeeper: `storekeeper` / `store123`
- Sales Staff: `salestaff` / `sales123`

## Useful Paths
- Main README: `/home/lenovo/Desktop/POS_system_management/README.md`
- Flutter mobile README: `/home/lenovo/Desktop/POS_system_management/mobile_app/README.md`
- Flutter main app file: `/home/lenovo/Desktop/POS_system_management/mobile_app/lib/main.dart`
- Backend API server: `/home/lenovo/Desktop/POS_system_management/src/pos/api_server.py`

## Notes
- Mobile app က Python backend API နဲ့ချိတ်သုံးတာဖြစ်ပါတယ်။
- Sales staff phone က authorized device မဟုတ်ရင် login မဝင်နိုင်ပါ။
- Flutter SDK install ပြီးမှ `flutter run` နဲ့ `flutter build apk` အလုပ်လုပ်ပါမယ်။
