Remote Controller - Local Wi-Fi Package
======================================

What this is:
- A local Wi-Fi phone remote controller for a Windows laptop.
- It is already packaged with the app dependencies.
- It only needs Node.js installed on the laptop.

What your dad needs:
1. A Windows laptop.
2. Node.js 20 or newer installed from https://nodejs.org/
3. Phone and laptop on the same Wi-Fi.

How to launch:
1. Unzip this folder somewhere normal, for example Desktop.
2. Double-click "Start Remote Controller.bat".
3. If Windows asks about the firewall, allow private/local network access.
4. The launcher prints "Paste this on your phone" and the current PIN.
5. Open that phone URL from the phone browser.
6. Type the PIN and approve the phone on the laptop page.
7. Leave the launcher window open if you want the URL and PIN visible. The controller keeps running until you use "Stop Remote Controller.bat".

Important:
- This package is for same Wi-Fi only.
- It will not work from mobile data unless you later set up Tailscale or another private network.
- Use "Stop Remote Controller.bat" when finished.
- If the phone cannot connect, run Start again and choose the firewall allow-rule prompt.
