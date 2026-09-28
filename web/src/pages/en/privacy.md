---
layout: ../../layouts/Legal.astro
lang: en
page: privacy
title: Privacy Policy
description: What data ShellX collects, why, how long it is kept, and your rights.
updated: "2026-09-28"
---

ShellX ("we") provides a desktop agent (macOS, Windows), a mobile app (iOS, Android), a relay server at `relay.shellx.pro` and the website `shellx.pro` (together, the "Service"). This policy explains what data is collected, what it is used for, how long it is kept, and what rights you have.

## Summary

- Terminal content (the commands you type and the output you see) is **end-to-end encrypted** between your phone and your computer. The relay only forwards encrypted data and **cannot read** it.
- We store only what is needed to run your account: your email, a hash of your password, device information and pairing records.
- No ads, no analytics or tracking tools, no push notifications, and we never sell data.

## 1. Data stored on our servers

**Account**

- **Email** — your sign-in name, stored in lowercase. We do not send verification or marketing emails.
- **Password** — never stored as entered. The server stores only an **argon2id** hash, from which the password cannot be recovered.
- When the account was created and when the password was last changed.

**Devices** — each time you register or sign in on a device, we store:

- the **device name**: the hostname for a computer, the model name for a phone;
- the **device kind** (desktop agent or mobile app) and **platform** (macOS, Windows, iOS or Android);
- the device's **public key** (X25519). The matching private key never leaves the device;
- when the device was added and when it was **last online**, used to show "Last online" in the app.

**Access tokens** — each signed-in device receives a random access token. The server stores only its SHA-256 hash, when it was created and when it was last used.

**Pairing records** — when you pair a phone with a computer by scanning a QR code, the server stores the (computer, phone) pair and when it was paired, for display in the apps only. Whether a phone is trusted is decided and stored on your computer, not on the server.

**IP addresses** — your IP address is used transiently to limit sign-in and registration attempts per 60-second window (to stop password guessing and abuse). We do not store IP addresses in the account database. `https://` requests to the Service are not access-logged; however, if you visit over a plain `http://` link, the shared web server may record that request (including your IP address) in its technical log before redirecting you to `https://`.

**Operational logs** — the server keeps minimal technical logs to run the Service and fix problems: timestamps, device IDs, error codes and frame sizes. Logs **never** contain terminal content, passwords or access tokens.

## 2. Terminal content is end-to-end encrypted

Your phone and your computer set up an encrypted channel using the Noise protocol, with keys that only those two devices hold. The relay sees only encrypted frames, the sending and receiving device IDs, and the size and timing of frames; it cannot read what you type or what is displayed, and it does not even know how many terminal sessions you have open. We do not store terminal content.

To replay output produced while your phone is briefly disconnected, the agent keeps up to 256 KiB of the most recent output of each session **in your computer's memory**. It is never sent to us and is gone when the session ends or the agent quits.

## 3. Data that stays on your devices

The device private key, access token, the list of trusted phones (on the computer), the list of paired computers (on the phone) and your settings are stored in the operating system's secure storage (Keychain on macOS/iOS, Windows Credential Manager with AES-encrypted files on Windows, Android Keystore) or in the app's settings storage. They are not sent to our servers, except for the access token, which accompanies each request to authenticate it.

- **Camera:** the mobile app uses the camera only to scan pairing QR codes. Images are neither stored nor sent anywhere.
- **Biometrics:** the app lock uses Face ID, fingerprint or the device passcode through the operating system. The app only receives a success or failure result, never biometric data.
- **Full Disk Access (macOS):** this optional permission only lets the commands you run in the terminal reach your folders. The agent itself never reads or uploads your files.

## 4. What we do not do

- No analytics, advertising, tracking pixels or third-party tracking SDKs.
- No push notifications.
- We do not sell, rent or share personal data for advertising.
- The `shellx.pro` website sets no cookies and embeds no third-party scripts.

## 5. How we use data

We use the data listed in section 1 only to: create and authenticate your account; show your devices, their online status and pairings; relay encrypted data between devices of the same account; and protect the Service from abuse.

## 6. Infrastructure provider and where data is processed

The Service runs on a private server rented by ShellX in **Vietnam**: the relay server, the account database and its backups, the website and the installers. Data is stored and processed in **Vietnam**. We use no content delivery network (CDN) and no third-party analytics.

When you download the mobile app from the App Store or Google Play, Apple and Google process data under their own policies.

We disclose data to authorities only when the law requires it. Because terminal content is end-to-end encrypted, we do not have it to disclose.

## 7. Retention

- **Account and devices:** until the account is deleted.
- **Access tokens:** deleted when you sign out on that device or when revoked (changing your password revokes the tokens of all other devices); a token expires after 90 days without use.
- **Pairing records:** deleted when you revoke or unpair, or when you sign out of the agent on that computer.
- **Operational logs:** no longer than 30 days.
- **Database backups:** one per day; the 14 most recent are kept.

<h2 id="delete-account">8. Deleting your account</h2>

You can delete your account yourself in the mobile app: open **Settings → Delete account** and enter your password again to confirm. Deletion takes effect immediately and cannot be undone: the server permanently deletes the account with all of its devices, access tokens and pairing records; every connected device is signed out. The desktop agent cannot tell this apart from a password change, so it always deletes its access token, closes all terminal sessions and shows the sign-in screen again — it **keeps** its device key and its list of trusted phones. That list is cleared only when you sign in again with a different account, when you sign out of the agent from the tray, or when you uninstall the agent.

If you can no longer use the mobile app, email [support@shellx.pro](mailto:support@shellx.pro) **from the email address of the account** with the subject "Delete my ShellX account". We may ask for more information to confirm that you own the account, delete it within 30 days of verification, and confirm by email.

Operational logs (which never contain terminal content, passwords or access tokens) expire within 30 days. Deleted data may also remain in the daily database backups for up to 14 days, and is removed together with those backups.

Data stored on your devices (section 3): on Windows, uninstalling the agent removes it; on Android, uninstalling the app removes it. On macOS and iOS, Keychain entries may remain after you remove the app — on iOS, ShellX clears them the next time you install the app; on macOS, they may be reused if you reinstall ShellX — and you can remove them sooner with the operating system's keychain management tools.

## 9. Your rights

You have the right to request access to, correction of, or deletion of your personal data, to withdraw consent and to object to processing, under the data protection laws where you live. Send requests to [support@shellx.pro](mailto:support@shellx.pro); we reply within 30 days.

In the apps you can view your devices, revoke or remove pairings, sign out, change your password (from a signed-in computer) and delete your account (from the mobile app).

## 10. Security

All connections to our servers use TLS; terminal content is end-to-end encrypted; passwords are hashed with argon2id; access tokens are stored only as SHA-256 hashes; private keys live in the operating system's secure storage; and the mobile app is locked with biometrics by default. No system is perfectly secure; if an incident affects your data, we will notify you as required by law.

## 11. Children

The Service is not intended for anyone under 16, and we do not knowingly collect their data. If you know that someone under 16 has created an account, contact us and we will delete it.

## 12. Changes to this policy

When this policy changes, we update this page and the "Last updated" date at the top. For significant changes, we post a notice on `shellx.pro` before the change takes effect.

## 13. Contact

Privacy questions: [support@shellx.pro](mailto:support@shellx.pro).
