Manual checks of spec §10, all pending (need a person, a real phone and a Mac):

1. iPhone (iOS 17 or 18): a Vite tool on `http://localhost:5173` opens; HMR works (edit a file on the computer, the page on the phone changes); Telex typing in the page's fields.
2. A tool declared as `http://127.0.0.1:8000` (Django or Jupyter) opens on the iPhone (E2 always uses `localhost`).
3. Android 10, 14, 16: as (1) (cleartext to localhost only, E14).
4. A low port (a tool on port 80 on the computer) and a port taken on the phone (another app listening on the same port): alias mode (E3) and its strip.
5. A frontend and its API on two ports, both on for the phone: the page reaches the API (E4).
6. Background and back: the page reloads and works.
7. Slow network (Network Link Conditioner, 3G): a big image, a terminal at the same time; the channel stays after a minute.
8. Turning 📱 off on the desktop while the phone shows the page: the page says so within 1 s.
9. VoiceOver / TalkBack in a tool page: note how far they read.

Added during execution (security and platform behaviour the tests cannot reach):

10. CSP (top-level ruling): a tool page that requests a `localhost` port the phone does not serve is blocked by the CSP, and no request reaches that port.
11. S1: a tool form that submits to an `https` site is blocked by the CSP on Android and iOS (nothing leaves; the page stays); `fetch`/XHR to `https` still work.
12. S2 / Task 9 I1, iPhone and Android: `NetworkInterface.list(includeLoopback: true)` lists `::1` on the device (if it does not, the phone serves 127.0.0.1 alone); with another listener on `[::1]:P` (P = the tool's port), the tool opens on an alias port with E3's strip and that listener receives no request; with nothing on `[::1]:P`, same-port mode.
13. S2: where no port can be held on both loopback addresses (e.g. an app holding `[::1]`'s ports), the page shows "Điện thoại không mở được cổng cục bộ cho tool." and keeps retrying.
14. Android downloads: a link to a PDF, a zip and an attachment (with and without `Content-Disposition`, with a `#fragment`) shows one "Tải tệp chưa làm được trên điện thoại." toast and does not loop; note whether a started load keeps the loading line and how many identical toasts appear.
15. Android back: after the tool reopened on another port (E3), back leaves the page and sends nothing to the old port; after an app switch on the same ports, back from the start page lands once on a white page (known).
16. Android `beforeunload`: a page with unsaved changes, left or turned off on the computer, shows the WebView's own confirm dialog; note what "stay" does (the page may keep running while nothing serves its ports — known).
17. Both platforms: leaving a tool page stops its scripts (no request reaches the tool's ports afterwards); on a re-serve with other ports, the old web view goes blank before the new entry loads.
18. iOS: a failed navigation (a file iOS cannot show) ends the progress line; "Xóa dữ liệu của tool" signs out a tool that keeps its login in IndexedDB (e.g. Firebase Auth); Cache API and service-worker data are not cleared (known).
