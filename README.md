# Get More Ram V2.0

A simple [SideSign](https://github.com/Mr3242-Scripter/SideSign) wrapper app that allows you to enable "Increased Memory Limit" for your sideloaded apps without using Xcode.

Authentication uses **your SideSign fork** (`Mr3242-Scripter/SideSign`), including the 2FA method picker (Devices / SMS / Phone) — the same auth path as your SideStore fork.

# How to use
1. Sideload this app
2. Go to settings, sign in with the Apple ID you used to sign the app you want to enable "Increased Memory Limit" (or import a SideStore account export)
3. Go to "App IDs" page
4. Tap Refresh
5. Tap the app you want to enable "Increased Memory Limit"
6. Tap "Add Increased Memory Limit"
7. Reinstall the app from SideStore/AltStore
8. Check if you have "Increased Memory Limit"

# Credits
- SideStore / SideSign — signing & auth
- Stossy11 — original StosSign integration (previous dependency)
