# whiteboard_demo

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Run On Phone / Emulator (dev)

### 1) Start the Django backend so your phone can reach it

From `backend/` (Windows):

- `./venv/Scripts/python.exe manage.py runserver 0.0.0.0:8001`

Make sure Windows Firewall allows inbound connections to port `8001`.

### 2) Pick the right backend URL in the app

- Android emulator: `http://10.0.2.2:8001`
- Physical phone: `http://<YOUR_PC_LAN_IP>:8001` (example: `http://192.168.1.50:8001`)

You can set this in the app at **Settings → Backend → Backend URL**.
