---
layout: ../../layouts/Legal.astro
lang: en
page: privacy
title: Privacy Policy
description: What data ShellX collects, why, how long it is kept, and your rights.
updated: "2026-10-07"
---

ShellX ("we") provides a desktop agent (macOS, Windows), a mobile app (iOS, Android), a relay server at `relay.shellx.pro` and the website `shellx.pro` (together, the "Service"). This policy explains what data is collected, what it is used for, how long it is kept, and what rights you have.

## Summary

- Terminal content (the commands you type and the output you see) is **end-to-end encrypted** between your phone and your computer. The relay only forwards encrypted data and **cannot read** it, except for the content of push notifications (section 3).
- We store only what is needed to run your account: your email, a hash of your password, device information and pairing records.
- Push notifications: while the computer's "Notify when long commands finish" setting is on (the default), or when a program sends a notification, the agent sends the notification text through our server, Google Firebase Cloud Messaging and Apple Push Notification service, without end-to-end encryption, to paired phones that allowed notifications (section 3).
- Voice input: when you tap the mic, what you say is turned into text by Apple's (iPhone) or Google's (Android, when the phone cannot do it itself) speech recognition, which may process the audio on their servers. ShellX does not store or receive the audio (section 2).
- No ads, no analytics or tracking tools, and we never sell data.

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

**Push token** — if you allow notifications in the mobile app, the server stores that phone's push token (FCM token), its platform (iOS or Android) and when it was last updated (section 3).

**Pairing records** — when you pair a phone with a computer by scanning a QR code, the server stores the (computer, phone) pair and when it was paired, for display in the apps only. Whether a phone is trusted is decided and stored on your computer, not on the server.

**IP addresses** — your IP address is used transiently to limit sign-in and registration attempts per 60-second window (to stop password guessing and abuse). We do not store IP addresses in the account database. `https://` requests to the Service are not access-logged; however, if you visit over a plain `http://` link, the shared web server may record that request (including your IP address) in its technical log before redirecting you to `https://`.

**Operational logs** — the server keeps minimal technical logs to run the Service and fix problems: timestamps, device IDs, error codes and frame sizes. Logs **never** contain terminal content, passwords or access tokens.

## 2. Terminal content is end-to-end encrypted

Your phone and your computer set up an encrypted channel using the Noise protocol, with keys that only those two devices hold. The relay sees only encrypted frames, the sending and receiving device IDs, and the size and timing of frames; it cannot read what you type or what is displayed, and it does not even know how many terminal sessions you have open — except for the content of push notifications (section 3). We do not store terminal content.

To replay output produced while your phone is briefly disconnected, the agent keeps up to 256 KiB of the most recent output of each session **in your computer's memory**. It is never sent to us and is gone when the session ends or the agent quits. Separately, the desktop app can save recent terminal contents on your computer to restore them when it reopens; see section 4.

### Voice input

- The mobile app uses the microphone only when you tap the mic on the terminal screen; it never records in the background.
- Speech is turned into text by the phone's speech recognition, **before** end-to-end encryption. On iPhone, Apple's speech recognition is used: Apple may process the audio on the phone or on its servers. On Android, speech is recognized on the phone when it can be; otherwise the audio goes to Google's speech recognition service. Apple and Google handle it under their own policies.
- ShellX does not store audio and does not send audio to ShellX servers. The text you send goes to the terminal like typed keys, end-to-end encrypted as above; the relay cannot read it.
- Your recognition language choice (Vietnamese/English) is stored on the phone.

## 3. Push notifications

The agent on your computer can tell your paired phones when a long-running command finishes, or when a program sends a notification — even when the mobile app is closed.

- **What the agent sends, and when.** While the computer's "Notify when long commands finish" setting is on (default: 30 seconds) — and whenever a program in the terminal emits a notification sequence (for example `shellx notify`, OSC 9, OSC 777) — the agent sends the **notification text** to the ShellX relay: the computer's name, the session or terminal window name, the command line, its exit code and running time, or the text the program sent. This text is **not end-to-end encrypted**.
- **What the relay does with it.** The relay only forwards it through **Google Firebase Cloud Messaging** and, for iPhones, **Apple Push Notification service**, and only to phones that are paired with that computer and have allowed notifications. The relay does not store it or write it to its logs; Google and Apple process it under their own policies.
- **When no phone can receive it** (no phone has allowed notifications, or all are signed out), the agent stops sending for up to 15 minutes — less if a phone connects to the computer in the meantime.
- **Push tokens.** When you allow notifications, the mobile app receives a push token (FCM token) from Google Firebase Cloud Messaging and sends it to our server. The server keeps it until you sign out on that phone, delete your account, turn off ShellX notifications in the phone's settings (the next time the app opens), or Firebase reports the token is no longer valid.
- This is the only exception to section 2: only the content of notifications, not the rest of your terminal.
- **How to turn it off:** choose "Off" under "Notify when long commands finish" in the ShellX menu on the computer (notifications when commands finish), turn off ShellX notifications in your phone's settings, or sign out on the phone.

## 4. Data that stays on your devices

The device private key, access token, the list of trusted phones (on the computer), the list of paired computers (on the phone) and your settings are stored in the operating system's secure storage (Keychain on macOS/iOS, Windows Credential Manager with AES-encrypted files on Windows, Android Keystore) or in the app's settings storage. They are not sent to our servers, except for the access token, which accompanies each request to authenticate it.

- **Camera:** the mobile app uses the camera only to scan pairing QR codes. Images are neither stored nor sent anywhere.
- **Biometrics:** the app lock uses Face ID, fingerprint or the device passcode through the operating system. The app only receives a success or failure result, never biometric data.
- **Full Disk Access (macOS):** this optional permission only lets the commands you run in the terminal reach your folders. The agent itself never reads or uploads your files.
- **Session restore (computer):** to reopen your workspace after you quit the app or restart the computer, ShellX saves the tab/pane layout, each terminal's working folder and — if "Save terminal contents on quit" is on (the default) — up to the last 2,000 lines of each terminal (at most 256 KiB per terminal). These files stay on your computer, in the app's data folder for your account: on macOS `~/Library/Application Support/pro.shellx.desktop/restore`, readable only by your account and excluded from Time Machine backups; on Windows `%LOCALAPPDATA%\ShellX\restore`, deleted when you uninstall. These contents can include anything that was shown in the terminal; they are never sent to our servers, to your phone, or synced anywhere. You can turn off saving the contents, or clear what was saved, at any time from the ShellX menu on the computer → Terminal.

## 5. What we do not do

- No analytics, advertising, tracking pixels or third-party tracking SDKs. The mobile app uses Firebase Cloud Messaging only to receive push notifications, and none of Firebase's analytics services.
- No promotional notifications: push notifications only come from your own computers.
- We do not sell, rent or share personal data for advertising.
- The `shellx.pro` website sets no cookies and embeds no third-party scripts.

## 6. How we use data

We use the data listed in section 1 only to: create and authenticate your account; show your devices, their online status and pairings; relay encrypted data between devices of the same account; deliver the push notifications you turned on to your phone; and protect the Service from abuse.

## 7. Infrastructure provider and where data is processed

The Service runs on a private server rented by ShellX in **Vietnam**: the relay server, the account database and its backups, the website and the installers. Data is stored and processed in **Vietnam**. We use no content delivery network (CDN) and no third-party analytics.

When you download the mobile app from the App Store or Google Play, Apple and Google process data under their own policies. When you turn on push notifications, their content and the push token are passed to Google (Firebase Cloud Messaging) and, for iPhones, Apple (Apple Push Notification service) to reach your phone (section 3); these services may process data outside Vietnam. When you use voice input, the audio is processed by Apple's speech recognition (iPhone) or, when the phone cannot recognize it itself, Google's speech recognition (Android), which may also process it outside Vietnam (section 2).

We disclose data to authorities only when the law requires it. Because terminal content is end-to-end encrypted, we do not have it to disclose.

## 8. Retention

- **Account and devices:** until the account is deleted.
- **Access tokens:** deleted when you sign out on that device or when revoked (changing your password revokes the tokens of all other devices); a token expires after 90 days without use.
- **Push tokens:** deleted when you sign out on that phone, when the account is deleted, when you turn off ShellX notifications in the phone's settings (the next time the app opens), or when Firebase reports the token is no longer valid.
- **Pairing records:** deleted when you revoke or unpair, or when you sign out of the agent on that computer.
- **Operational logs:** no longer than 30 days.
- **Database backups:** one per day; the 14 most recent are kept.

<h2 id="delete-account">9. Deleting your account</h2>

You can delete your account yourself in the mobile app: open **Settings → Delete account** and enter your password again to confirm. Deletion takes effect immediately and cannot be undone: the server permanently deletes the account with all of its devices, access tokens, push tokens and pairing records; every connected device is signed out. The desktop agent cannot tell this apart from a password change, so it always deletes its access token, closes all terminal sessions and shows the sign-in screen again — it **keeps** its device key and its list of trusted phones. That list is cleared only when you sign in again with a different account, when you sign out of the agent from the tray, or when you uninstall the agent.

If you can no longer use the mobile app, email [phule9225@gmail.com](mailto:phule9225@gmail.com) **from the email address of the account** with the subject "Delete my ShellX account". We may ask for more information to confirm that you own the account, delete it within 30 days of verification, and confirm by email.

Operational logs (which never contain terminal content, passwords or access tokens) expire within 30 days. Deleted data may also remain in the daily database backups for up to 14 days, and is removed together with those backups.

Data stored on your devices (section 4): on Windows, uninstalling the agent removes it; on Android, uninstalling the app removes it. On macOS and iOS, Keychain entries may remain after you remove the app — on iOS, ShellX clears them the next time you install the app; on macOS, they may be reused if you reinstall ShellX — and you can remove them sooner with the operating system's keychain management tools.

## 10. Your rights

You have the right to request access to, correction of, or deletion of your personal data, to withdraw consent and to object to processing, under the data protection laws where you live. Send requests to [phule9225@gmail.com](mailto:phule9225@gmail.com); we reply within 30 days.

In the apps you can view your devices, revoke or remove pairings, sign out, change your password (from a signed-in computer) and delete your account (from the mobile app).

## 11. Security

All connections to our servers use TLS; terminal content is end-to-end encrypted (except the content of push notifications, section 3); passwords are hashed with argon2id; access tokens are stored only as SHA-256 hashes; private keys live in the operating system's secure storage; and the mobile app is locked with biometrics by default. No system is perfectly secure; if an incident affects your data, we will notify you as required by law.

## 12. Children

The Service is not intended for anyone under 16, and we do not knowingly collect their data. If you know that someone under 16 has created an account, contact us and we will delete it.

## 13. Changes to this policy

When this policy changes, we update this page and the "Last updated" date at the top. For significant changes, we post a notice on `shellx.pro` before the change takes effect.

## 14. Contact

Privacy questions: [phule9225@gmail.com](mailto:phule9225@gmail.com).
