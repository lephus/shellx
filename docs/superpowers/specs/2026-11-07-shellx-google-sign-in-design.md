# ShellX: đăng nhập bằng Google (và Apple trên iPhone) — đặc tả thiết kế

Ngày: 2026-11-07. Dự án 1/3 của đợt "ShellX cho Android" (xem mục 12). Nhãn: **[người dùng]** là quyết
định của người dùng; **[người viết]** là quyết định của người viết đặc tả, người dùng có thể đổi.

## 1. Ý định và lý do

Người dùng muốn đưa ShellX lên Google Play cho mọi người. Trong buổi brainstorm 2026-11-07 họ quyết định
đổi cách đăng nhập của **mọi** app:

- "Đăng nhập bằng Google: iOS và android … buộc login với Google, riêng ios thì có thêm login với apple
  => dựa vào địa chỉ email để link với desktop app tương ứng" **[người dùng]**.
- "desktop chỉ còn đăng nhập Google giống điện thoại" **[người dùng]**.
- Bản tóm tắt cuối (Apple ẩn email nối qua QR, chạy song song rồi cắt mật khẩu, đăng xuất mọi phiên cũ một
  lần) được người dùng xác nhận: "đúng rồi" **[người dùng]**.

Lý do (người viết suy ra, người dùng không phản đối):

- Một danh tính ở mọi nơi: điện thoại và desktop cùng nói "đây là tài khoản Google X", không phụ thuộc
  người dùng gõ email có khớp không.
- Relay hôm nay **tạo tài khoản mà không xác minh email** (`relay/src/routes/auth.ts`, `POST /register`).
  Nối tài khoản theo email chỉ an toàn khi email đã được Google / Apple xác minh.
- **Hôm nay không app native nào tạo được tài khoản mới**: Mac, Windows và iPhone chỉ gọi
  `POST /v1/auth/login` (`shellx-core/src/auth.rs`, `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift`).
  Chỉ app Flutter cũ (tag `flutter-final`, `packages/shellx_core/lib/src/api/shellx_api.dart:48`) và script
  test `scripts/shellx/share-e2e.mjs` gọi `/v1/auth/register`, dù trang chủ ghi "Install ShellX on your
  computer and create an account" (`web/src/i18n/ui.ts`). Lần đăng nhập Google đầu tiên tự tạo tài khoản,
  lấp chỗ hổng này.
- App Store yêu cầu (Guideline 4.8): app có đăng nhập Google phải có thêm một cách đăng nhập giữ kín email,
  vì vậy iPhone có Apple.

## 2. Mục tiêu

- **G1.** Mac, Windows và Android chỉ có một nút "Tiếp tục với Google". iPhone có "Tiếp tục với Google" và
  "Đăng nhập bằng Apple". Không còn ô email / mật khẩu, không còn đăng ký hay đổi mật khẩu trong app nào
  **[người dùng]**.
- **G2.** Tài khoản email / mật khẩu đang có được **giữ nguyên** khi người dùng đăng nhập Google bằng đúng
  email đó: còn Mac, điện thoại đã ghép, quyền (`phone_grants`), phiên chia sẻ. Điện thoại và Mac đã ghép
  không phải quét QR lại **[người dùng: nối theo email]**.
- **G3.** Người mới bắt đầu từ app nào cũng được: lần đăng nhập Google đầu tiên tạo tài khoản. Sau đó đăng
  nhập Google trên app khác vào đúng tài khoản đó **[người viết]**.
- **G4.** Apple trên iPhone dùng được cả khi người dùng chọn **ẩn email**: tài khoản Apple đó được gắn vào
  tài khoản của Mac khi điện thoại quét QR và người dùng bấm Cho phép trên Mac **[người dùng xác nhận]**.
- **G5.** Xoá tài khoản ngay trong app iPhone và Android (bắt buộc: App Store 5.1.1(v); Google Play "account
  deletion"), cùng một trang web hướng dẫn xoá **[người viết; bắt buộc để lên store]**.

### 2.1 Tiêu chí thành công

1. Một tài khoản email / mật khẩu cũ có 1 Mac + 1 iPhone đã ghép: đăng nhập Google (cùng email) trên Mac
   rồi trên iPhone → iPhone thấy Mac và workspace như trước, **không** quét QR lại.
2. Người mới: đăng nhập Google trên Android → tài khoản mới; cài desktop, đăng nhập cùng Google → ghép
   Android với Mac bằng QR như hôm nay.
3. iPhone đăng nhập Apple, ẩn email → quét QR của Mac → bấm Cho phép trên Mac → iPhone vào đúng tài khoản
   của Mac. Lần sau đăng nhập Apple đó vào thẳng tài khoản này.
4. Không ai chiếm được tài khoản người khác bằng cách đăng ký trước bằng email của họ (mục 8).
5. Từ lúc người dùng xong bước của Google / Apple đến lúc app đã đăng nhập: p95 < 2 s qua relay thật.

## 3. Không làm

- Đăng nhập bằng mật khẩu, đăng ký, đổi mật khẩu, quên mật khẩu: **bỏ** sau ngày cắt (mục 7).
- Nhà cung cấp khác (GitHub, Microsoft, email magic link) **[người viết]**.
- Apple trên Mac, Windows hay Android; Google là cách duy nhất ở đó **[người dùng]**.
- Gắn nhiều tài khoản Google vào một tài khoản ShellX; gộp hai tài khoản ShellX đang có với nhau. Ngoại lệ
  duy nhất là Apple gắn qua QR (G4) **[người viết]**.
- Đăng nhập trang quản trị `admin.shellx.pro` (vẫn là `ADMIN_PASSWORD`) **[người viết]**.
- Nút xoá tài khoản trên desktop: không bắt buộc, desktop chỉ dẫn link tới trang hướng dẫn **[người viết]**.

## 4. Điều tuyệt đối tránh

- Một người vào được tài khoản của người khác qua việc nối theo email.
- Người dùng cũ mất Mac, mất ghép cặp hay mất phiên chia sẻ sau khi đổi.
- Desktop và điện thoại lặng lẽ rơi vào hai tài khoản khác nhau mà không ai biết: app luôn hiện email của
  tài khoản đang dùng.
- Người dùng bị kẹt không có đường vào (ví dụ Apple ẩn email mà không có cách nối).
- Mở trang đăng nhập Google trong webview nhúng (Google chặn, và trông như lừa đảo).

## 5. Ràng buộc

- **Ranh giới giấy phép iOS** (`scripts/shellx/check-ios-license.sh`): không package tải từ mạng, nên
  **không dùng GoogleSignIn SDK**. iPhone làm OAuth 2.0 + PKCE bằng `ASWebAuthenticationSession` và Apple
  bằng `AuthenticationServices` (cả hai là framework của Apple; thêm module vào allowlist của script nếu
  cần, có ghi lý do).
- **Android**: Credential Manager (`androidx.credentials`, `com.google.android.libraries.identity.googleid`),
  giấy phép Apache 2.0. Chi tiết ở đặc tả Android.
- **Desktop**: OAuth cho app cài trên máy theo cách Google khuyên: mở **trình duyệt mặc định**, chuyển
  hướng về `http://127.0.0.1:<cổng>` (loopback), PKCE S256. Làm **một lần trong `shellx-core`** (Rust) để
  Mac và Windows dùng chung.
- **Relay** (`relay/`, Node 22, Hono, SQLite): xác minh ID token bằng khoá công khai (JWKS) của Google và
  Apple, có cache. Được thêm một thư viện JWT có bảo trì (gợi ý `jose`, MIT); không tự viết phần kiểm chữ ký.
- Client cũ vẫn chạy cho tới ngày cắt: desktop ≤ 1.7.0, iPhone 1.0.0 (5) và app Flutter cũ đều đăng nhập
  bằng mật khẩu.
- Mac: code liên kết vào app giữ tương thích Swift 6.0. Test Mac chỉ qua `scripts/shellx/test-app.sh`.
  Không bao giờ thoát, thay hay mở lại ShellX đang chạy của người dùng.
- Bí mật: Google client ID không phải bí mật. Client secret của client "Desktop app" nằm trong app (Google
  coi đó là không bí mật) nhưng không được ghi vào log. Khoá Sign in with Apple (`.p8`) chỉ nằm trên VPS
  như khoá APNs. Không bao giờ hỏi khoá hay mật khẩu trong chat.
- Chuỗi hiển thị mới theo `skills/cmux-localization` (Mac), `scripts/check-strings.py` (iPhone),
  `windows/shellx-model/src/strings.rs` (Windows); có tiếng Anh và tiếng Việt.

## 6. Thiết kế

### 6.1 Dữ liệu trên relay [người viết]

Migration mới `relay/migrations/0010_identities.sql`:

- Bảng `identities`: `provider` (`google` | `apple`), `subject` (claim `sub`), `user_id` → `users(id)`
  `ON DELETE CASCADE`, `email` (lúc gắn), `is_private_email` (Apple), `apple_refresh_token` (chỉ Apple, để
  thu hồi khi xoá tài khoản), `linked_via_device_id` (iPhone đã gắn Apple ID qua QR, để hiện tên trên
  desktop), `created_at`, `last_used_at`. Khoá chính (`provider`, `subject`).
- `users.password_hash` cho phép `NULL`. `NULL` = tài khoản không còn mật khẩu.
- `tokens`: thêm cột ghi cách đăng nhập (`password` | `google` | `apple`; token cũ mặc định `password`)
  để ngày cắt xoá đúng token mật khẩu. Builder có thể chọn cách tương đương.
- `users.email` vẫn là email hiển thị của tài khoản. Tài khoản mới tạo từ Google lấy email Google.

### 6.2 API đăng nhập mới [người viết; tên chính xác do builder chốt]

- `POST /v1/auth/nonce` → `{nonce, expires_in}`: nonce ngẫu nhiên, dùng một lần, sống 10 phút. Mọi lần
  đăng nhập Google / Apple phải mang một nonce relay đã cấp, để token bị lộ không dùng lại được.
- `POST /v1/auth/google {id_token, nonce, device}`. `device` giống hôm nay (`kind`, `name`, `platform`,
  `public_key`; `relay/src/auth/device.ts`).
- `POST /v1/auth/apple {identity_token, authorization_code, nonce, device}`: chỉ nhận `platform: "ios"`.
- Trả về như `login` hôm nay: `{user_id, device_id, token}`. Riêng Apple không khớp tài khoản nào thì trả
  `{status: "link_required", link_token}` (mục 6.4).
- Kiểm ID token: chữ ký qua JWKS; `iss` đúng nhà cung cấp; `aud` thuộc **danh sách client ID cấu hình**
  (Google: client iOS, client "Web" mà Android dùng làm `serverClientId`, client Desktop; Apple: bundle id
  `com.shellx.prod`, `com.shellx.dev`); `exp` chưa qua, `iat` không quá 10 phút; nonce khớp nonce đã cấp và
  bị đánh dấu đã dùng; `email_verified` là true. Sai bất kỳ điểm nào → `invalid_credentials`, không nói lý
  do cụ thể ra ngoài.
- Giới hạn tần suất theo IP như `login` hiện nay (`limiters.loginIp`).
- Apple: relay đổi `authorization_code` lấy `refresh_token` (REST `https://appleid.apple.com/auth/token`,
  client secret là JWT ES256 ký bằng khoá Sign in with Apple), lưu vào `identities.apple_refresh_token`.
  Đổi thất bại không chặn đăng nhập; lần đăng nhập sau thử lại.
- Cấu hình mới qua env (đi qua `deploy/docker-compose.yml` như APNs): danh sách client ID Google, danh sách
  client ID Apple, team ID, key ID và đường dẫn khoá Sign in with Apple, công tắc `PASSWORD_LOGIN`
  (`on` | `off`).

### 6.3 Luật tìm tài khoản (trái tim của thiết kế)

Khi một ID token hợp lệ đến **từ màn đăng nhập** (chưa đăng nhập), relay làm theo thứ tự:

1. Có `identities` với (`provider`, `sub`) → vào tài khoản đó. Email đổi bên Google không ảnh hưởng.
2. Chưa có, mà email đã xác minh **trùng** `users.email` (so sau khi bỏ khoảng trắng và viết thường bằng
   `normalizeEmail`, `relay/src/auth/email.ts`; không gộp biến thể dấu chấm hay `+tag` của Gmail
   **[người viết]**):
   - tài khoản đó **không còn mật khẩu** (tạo bằng Google, hoặc đã qua ngày cắt) → gắn danh tính vào tài
     khoản đó **[người dùng: nối theo email]**;
   - tài khoản đó **còn mật khẩu** (trước ngày cắt) → **không gắn**, trả `switch_from_signed_in_device`.
     App báo: "Email này đã có tài khoản ShellX. Mở ShellX trên một máy đang đăng nhập, vào Cài đặt › Tài
     khoản › Chuyển sang Google, rồi thử lại." **[người viết; chống chiếm tài khoản, mục 8]**
3. Không trùng, nhà cung cấp là Google → tạo tài khoản mới với email Google.
4. Nhà cung cấp là Apple mà không trùng (email ẩn, hoặc email thật nhưng không có tài khoản), **hoặc** trùng một
   tài khoản còn mật khẩu → **không tạo tài khoản, không nối theo email**; trả `link_required` (mục 6.4) **[người viết, người dùng xác nhận]**. Lý do: desktop chỉ có
   Google, nên một tài khoản chỉ có Apple sẽ không bao giờ có Mac.

Thiết bị: như `login` hôm nay, cùng tài khoản + cùng khoá công khai → cùng `device_id`. Nhờ vậy Mac giữ
`machines` và điện thoại giữ `phone_grants` khi đăng nhập lại bằng Google, **miễn là app không "Đăng
xuất"** (đăng xuất xoá máy và bỏ ghép, `relay/src/routes/auth.ts:160`,
`shellx-ios/.../Account/AppCoordinator.swift` `signOut`). Vì vậy:

- khi bị relay trả 401, mọi app mới hiện màn đăng nhập nhưng **giữ** khoá thiết bị và các Mac đã ghép,
  như iPhone đang làm (`AppCoordinator.handleUnauthorized`) và `shellx-core` đang giữ `machine.json`;
- người đang đăng nhập bằng mật khẩu chuyển sang Google **ngay trong app** (mục 6.3b), không đăng xuất.

### 6.3b Chuyển sang Google ngay trong app [người viết]

- Bản app mới (desktop 1.8.0, iPhone) đang giữ token mật khẩu thì hiện một băng một lần và một mục trong
  Cài đặt › Tài khoản: **"Chuyển sang đăng nhập Google"**.
- Bấm → bước Google như thường → `POST /v1/auth/google/link {id_token, nonce}` **kèm bearer token hiện
  tại**. Token chứng minh người này đang giữ tài khoản, nên relay gắn danh tính Google vào **chính tài
  khoản này**, kể cả khi email Google khác `users.email`. Khi đó `users.email` đổi thành email Google, trừ
  khi tài khoản khác đã dùng email ấy (`email_in_use`).
- Token của máy này được đánh dấu là Google. Thiết bị khác và mật khẩu **không đổi** cho tới ngày cắt, nên
  các bản app cũ vẫn chạy.
- Nhờ đó tài khoản cũ dùng email không phải Google (iCloud, Outlook, email công ty) vẫn giữ được mọi thứ,
  chỉ cần một máy còn đăng nhập.

### 6.4 Apple ẩn email: gắn qua QR [người dùng xác nhận]

1. iPhone đăng nhập Apple → relay trả `link_required` + `link_token` (sống 10 phút, gắn với `sub` của Apple
   và khoá công khai của iPhone; chỉ dùng cho bước gắn).
2. iPhone hiện màn "Kết nối với Mac của bạn": quét QR (hoặc dán mã) đúng như ghép cặp hôm nay. Mã
   `shellx-link://pair?...` đã có `machine_id`, khoá host và mã.
3. iPhone gửi yêu cầu ghép kèm `link_token` thay cho bearer token (ví dụ `POST /v1/auth/apple/link
   {link_token, machine_id, client_key_b64, proof_b64}`). Relay tạo một dòng `phone_pairings` thuộc tài
   khoản của máy đó, đánh dấu "gắn danh tính Apple".
4. Mac thấy yêu cầu trong danh sách chờ như mọi yêu cầu ghép, kiểm `proof` như hôm nay
   (`ShellXPhonePairingCoordinator`). Sheet trên Mac (`Sources/ShellX/Remote/UI/PhonePairingSheet.swift`)
   ghi thêm một dòng rõ ràng: "Cho phép sẽ để tài khoản Apple này đăng nhập vào tài khoản ShellX của bạn".
5. Bấm Cho phép → relay, trong một giao dịch: tạo `identities` (apple, `sub`) cho tài khoản của Mac, tạo
   thiết bị iPhone và token, cấp quyền như ghép cặp thường. iPhone hỏi lại bằng `link_token` và nhận
   `{user_id, device_id, token, machine}`.
6. Từ chối, hết hạn hay `link_token` hết hạn → iPhone về màn đăng nhập với lời báo ngắn.

`link_token` chỉ giữ trong bộ nhớ; app bị tắt giữa chừng thì người dùng đăng nhập Apple lại.

**Quyền của Apple ID đã gắn** [người viết]: đó là chính chủ tài khoản (người bấm Cho phép trên Mac là chủ
tài khoản), nên Apple ID ấy có đủ quyền như Google: đăng nhập, ghép thêm Mac bằng QR, xoá tài khoản. Sheet
trên Mac nói rõ: "Apple ID này sẽ đăng nhập và quản lý được tài khoản ShellX của bạn, kể cả xoá tài
khoản."

**Gỡ Apple ID** [người viết]: Cài đặt › Tài khoản trên desktop liệt kê các cách đăng nhập (Google + email;
mỗi Apple ID kèm tên iPhone đã gắn nó). Apple ID có nút **Gỡ**: relay xoá danh tính, thu hồi token Apple,
xoá token của các thiết bị đã đăng nhập bằng nó. Bỏ ghép iPhone **không** gỡ Apple ID (hai việc khác nhau).
Cần route liệt kê và gỡ danh tính, và cột ghi thiết bị đã gắn danh tính (6.1). Không gỡ được danh tính
Google cuối cùng.

### 6.5 Desktop (Mac và Windows)

- `shellx-core` thêm ba lệnh (cùng kiểu `auth.login` hôm nay, `shellx-core/src/lib.rs`):
  - `auth.google.begin` → `{flow_id, auth_url}`: lấy nonce từ relay, mở cổng nghe ngẫu nhiên **chỉ trên
    127.0.0.1**, tạo `state` và PKCE S256;
  - `auth.google.finish {flow_id}`: chờ trình duyệt quay về (tối đa 5 phút), kiểm `state`, đổi `code` lấy
    token ở Google, gửi `id_token` tới `POST /v1/auth/google`. Thành công thì ghi `session.json` và dọn
    trạng thái y như `auth.login` hôm nay;
  - `auth.google.cancel {flow_id}`.
  Trang loopback trả về một trang nhỏ "Bạn có thể đóng tab này và quay lại ShellX" (song ngữ).
- **Mac**: `Sources/ShellX/Remote/UI/SignInSheet.swift` chỉ còn nút "Tiếp tục với Google". App mở
  `auth_url` bằng trình duyệt mặc định, sheet hiện "Đang chờ Google… [Huỷ]", rồi email của tài khoản khi
  xong. Logic ở `Packages/Shared/ShellXBrand/Sources/ShellXRemoteCore/ShellXAccount.swift`.
- **Windows**: `windows/shellx-app/src/ui/account.rs`, `windows/shellx-model/src/account.rs`,
  `core_api.rs`, `strings.rs` (giữ test `sign_in_strings_match_the_mac`).
- Màn đăng nhập không còn ô mật khẩu. `shellx-core` vẫn giữ một đường dùng token mật khẩu **đang có** cho
  tới ngày cắt, để app đã đăng nhập chạy tiếp và "Chuyển sang Google" (6.3b) gọi được `auth.google.link`
  (bước Google như trên + bearer token hiện tại).
- Khi relay trả 401: hiện màn đăng nhập Google, **giữ** khoá thiết bị và `machine.json`, không xoá máy
  (6.3).
- Settings › Account trên desktop **[người viết]**:
  - hiện email và Đăng xuất;
  - mục "Chuyển sang đăng nhập Google" khi máy còn token mật khẩu;
  - danh sách cách đăng nhập (Google, các Apple ID kèm tên iPhone, nút Gỡ cho Apple ID, 6.4);
  - link "Xoá tài khoản" mở `https://shellx.pro/privacy#delete-account`.

### 6.6 iPhone

- `shellx-ios/ShellX/UI/SignIn/SignInView.swift`: hai nút "Tiếp tục với Google" và "Đăng nhập bằng Apple"
  (nút Apple theo mẫu chuẩn của Apple, HIG Sign in with Apple).
- Google: `ASWebAuthenticationSession` với client iOS, callback qua scheme đảo của client ID, PKCE S256,
  nonce từ relay. Client ID khác nhau cho `com.shellx.prod` và `com.shellx.dev`.
- Apple: `ASAuthorizationAppleIDProvider` chỉ xin scope `email` **[người viết]**; entitlement
  `com.apple.developer.applesignin` trong `shellx-ios/Config/`.
- `shellx-link/Sources/ShellXLinkAccount/RelayAPI.swift` thêm nonce, Google, Apple, Apple link; bỏ
  `login` (mật khẩu) sau ngày cắt. Lỗi mới vào `SignInError`.
- `link_required` → màn "Kết nối với Mac của bạn" dùng lại `PairingSheet` / `QRScannerView`.
- `switch_from_signed_in_device` → lời báo ở 6.3 bước 2.
- iPhone đang giữ token mật khẩu: băng một lần và mục "Chuyển sang đăng nhập Google" trong Cài đặt › Tài
  khoản (6.3b). 401 giữ khoá và các Mac như `handleUnauthorized` đang làm.
- Settings › Tài khoản: thêm **Xoá tài khoản…** (mục 6.8).
- **Xem thử không cần tài khoản** **[người viết; người dùng chưa trả lời câu hỏi này]**:
  - **Vì sao**: người duyệt App Store không có Mac. Bỏ mật khẩu thì tài khoản demo cũng mất.
  - **Ở đâu**: một nút chữ trên màn đăng nhập và trên `FirstMacView`.
  - **Mở ra gì**: Mac giả của `ShellX/Debug/DemoComposition.swift` / `DemoScript.swift`, nay đưa vào cả bản
    phát hành.
  - **Hành vi**: luôn có băng "Demo · Thoát". Không gửi gì lên mạng, không chạm dữ liệu thật.
  - **Kiểm bản phát hành**: `release/mobile/ios.sh --check-app` hôm nay từ chối code demo trong bản
    Release. Sửa phép kiểm để cho phép phần demo này mà vẫn chặn mọi công cụ chỉ dành cho debug.
  - **Ghi chú cho người duyệt**: dùng nút này; dùng đầy đủ cần một Mac chạy ShellX.

### 6.7 Android

Dùng chung API relay ở mục 6.2. Credential Manager với `GetSignInWithGoogleOption`, `serverClientId` là
client "Web", nonce từ relay. Không có Apple. Chi tiết ở
`docs/superpowers/specs/2026-11-07-shellx-android-app-design.md`.

### 6.8 Xoá tài khoản [người viết; bắt buộc để lên store]

- `DELETE /v1/account` đổi cách xác nhận: thay `password` bằng một ID token **mới** (Google hoặc Apple,
  `iat` ≤ 5 phút, nonce mới) thuộc một danh tính của chính tài khoản này. Tài khoản còn mật khẩu (chưa nối)
  thì vẫn nhận mật khẩu cho tới ngày cắt.
- Tài khoản có danh tính Apple: relay thu hồi token Apple (`https://appleid.apple.com/auth/revoke`, bắt
  buộc theo yêu cầu của Apple); thất bại thì ghi log loại lỗi, không chặn việc xoá.
- iPhone / Android: Settings › Tài khoản › **Xoá tài khoản…** → hộp xác nhận ghi rõ hậu quả → đăng nhập
  lại với nhà cung cấp → xoá → dọn dữ liệu máy như khi đăng xuất (`LocalDataWiping`).
- Web: viết lại `web/src/pages/privacy.md` §9 (cách xoá trong app, hoặc gửi email) và các đoạn nói về mật
  khẩu, FCM, dữ liệu lưu. Đây là "Delete account URL" khai trên Google Play.

### 6.9 Gỡ đăng nhập mật khẩu

Khi `PASSWORD_LOGIN=off`: `/v1/auth/register`, `/v1/auth/login`, `/v1/auth/password` trả `410
password_sign_in_removed`. Script `relay/src/scripts/reset-password.ts` và lệnh `reset-password` trong
`package.json` bị gỡ. Trang quản trị không đổi.

## 7. Chuyển đổi [người viết, người dùng xác nhận]

1. **Chuẩn bị (người dùng)**: tạo OAuth client trên Google Cloud và bật Sign in with Apple (mục 10). Builder
   đưa danh sách giá trị cần điền.
2. **Relay pha 1**: deploy bản có migration 0010, các route Google / Apple / nonce / Apple link, xoá tài
   khoản mới. Mật khẩu **vẫn bật**. `/v1/auth/register` đóng luôn (không client nào dùng, mà để mở thì ai
   cũng tạo được tài khoản chưa xác minh) **[người viết]**.
3. **Phát hành app**: desktop 1.8.0 (Mac + Windows) chỉ có Google; iPhone bản mới có Google + Apple + Xoá
   tài khoản. Android ra sau, đã có Google ngay từ đầu.
4. **Bắt buộc cập nhật desktop**: đặt `MIN_MACOS` / `MIN_WINDOWS` = 1.8.0 trong `deploy/relay.env` rồi
   deploy. Trang quản trị không đặt được hai giá trị này (`relay/src/settings.ts:43-47`). iPhone dùng lời
   nhắc cập nhật đã có. App Flutter đã xoá hẳn **[người dùng]**: không làm gì cho nó; nếu còn bản nào chạy
   thì nó mất đăng nhập ở ngày cắt.
5. **Ngày cắt (người dùng chọn ngày, sau khi xem số bản app cũ còn chạy trên trang quản trị)**: đặt
   `PASSWORD_LOGIN=off`; mọi tài khoản còn mật khẩu bị xoá mật khẩu; xoá mọi token đăng nhập bằng mật khẩu.
   Từ đây mọi phiên cũ đã bị đăng xuất đúng một lần. App mới khi nhận 401 hiện nút Google mà vẫn giữ máy và
   ghép cặp (6.3).

Sau ngày cắt, tài khoản cũ chưa chuyển vẫn nằm đó; lần đầu có người đăng nhập Google đúng email, luật 6.3
bước 2 nối thẳng vào.

Token bị xoá không cắt ngay kết nối đang chạy: app native không dùng `/v1/ws` (nơi mã đóng `4002` có tác
dụng). Lần gọi REST hay lần xin vé relay2 kế tiếp nhận 401 (vé sống 120 s, `relay/src/v2/tickets.ts:4`).

## 8. An toàn

- **Chiếm tài khoản bằng đăng ký trước** (pre-hijacking): kẻ xấu đăng ký `nan@gmail.com` bằng mật khẩu
  khi email chưa được xác minh; nạn nhân sau đó đăng nhập Google và được nối vào tài khoản đó. Chặn bằng:
  - đóng `register` ở pha 1;
  - trước ngày cắt, đăng nhập Google **không** tự nối vào tài khoản còn mật khẩu. Chỉ máy đang giữ token
    của tài khoản đó mới nối được (6.3b);
  - ngày cắt xoá mọi mật khẩu và token mật khẩu, nên kẻ xấu mất mọi đường vào trước khi việc tự nối theo
    email được bật.
- **Dùng lại token**: nonce do relay cấp, dùng một lần, sống ngắn; `aud` chỉ nhận client ID của ShellX.
- **Chuyển hướng loopback**: chỉ nghe trên 127.0.0.1, PKCE + `state`, đóng cổng sau lần đầu hoặc sau 5
  phút.
- **Gắn Apple qua QR**: cần mã QR (proof HMAC, Mac kiểm) **và** người dùng bấm Cho phép trên Mac. Quyền
  mới duy nhất là danh tính Apple trở thành một cách đăng nhập vào tài khoản đó, và sheet trên Mac nói rõ
  điều này.
- **Log**: không ghi email, token, `sub`, nonce hay code; dùng `logMeta` như hiện nay.
- Relay tiếp tục chỉ lưu băm của token phiên.

## 9. Kiểm thử

- **Relay** (vitest): JWKS giả và token ký bằng khoá thử; đủ các nhánh của 6.3; nonce dùng hai lần; `aud`
  lạ; email chưa xác minh; trước ngày cắt không tự nối vào tài khoản còn mật khẩu (`switch_from_signed_in_device`, Apple thì `link_required`); nối tại chỗ (6.3b); Apple
  link duyệt / từ chối / hết hạn; xoá tài khoản bằng token mới; `PASSWORD_LOGIN=off`.
- **shellx-core** (Rust): `auth.google.*` với Google giả (máy chủ token giả) và `shellx-core/fake-api`;
  `state` sai; hết giờ; huỷ.
- **Mac**: test hành vi cho sheet đăng nhập và sheet ghép có dòng Apple, qua
  `scripts/shellx/test-app.sh <Suite>`.
- **Windows**: test model trong `windows/shellx-model`.
- **iPhone**: test `ShellXAppCore` cho luồng đăng nhập và `link_required`; render test PNG (sáng / tối,
  en / vi) cho màn đăng nhập, màn kết nối Mac và hộp xoá tài khoản.
- **Bằng tay trên máy thật**: tiêu chí 2.1 từ 1 tới 4, qua relay thật, sau pha 1 (tiêu chí 1 bằng "Chuyển
  sang Google" ngay trong app).
- **Test không có người làm bước Google** [người viết]:
  - relay nhận thêm một **nhà cung cấp danh tính thử** (issuer riêng, khoá công khai đọc từ env), chỉ bật
    khi env có. Production không bao giờ đặt env này.
  - Các harness đang đăng nhập bằng mật khẩu chuyển sang nó: `scripts/shellx/share-e2e.mjs:223`
    (register), `scripts/shellx/remote-e2e/harness.py:456` (`auth.login`), `shellx-core/fake-api`.
  - Smoke test sau deploy (`relay/scripts/relay2-smoke.ts:113`) dùng một tài khoản smoke riêng. Token của
    tài khoản này do một script chỉ chạy được trên VPS cấp (trong container relay, đọc thẳng DB).

## 10. Phần việc của người dùng

- Google Cloud (dự án Firebase `shellxpro` hoặc dự án mới): màn đồng ý OAuth (tên ShellX, email hỗ trợ,
  `https://shellx.pro/privacy`, miền `shellx.pro`, scope `openid email profile`), publish lên Production.
  Tạo client: iOS × 2 (`com.shellx.prod`, `com.shellx.dev`), Android × 2 (package + SHA-1 của khoá debug,
  khoá upload `~/.shellx-release/shellx-upload.jks` và khoá Play App Signing), Web × 1 (cho Android),
  Desktop × 1.
- Apple Developer: bật Sign in with Apple cho hai App ID; tạo khoá Sign in with Apple (`.p8`), đặt lên VPS
  như khoá APNs.
- Điền env trên VPS; chạy deploy bằng `! bash deploy/vps-deploy.sh` (Claude không tự deploy).
- Chọn ngày cắt; phát hành desktop / iPhone theo quy trình phát hành hiện có.

## 11. Để lại cho người làm

- Tên route, tên trường, mã lỗi chính xác; thư viện JWT; nơi lưu nonce (bảng hay bộ nhớ có hạn).
- Cách `shellx-core` báo cho app mở trình duyệt; nội dung trang loopback.
- Chữ trên các nút và màn hình, theo quy tắc bản địa hoá và HIG / Material.
- Cách đánh dấu cách đăng nhập của token (6.1).

## 12. Ba dự án và thứ tự

1. **Đặc tả này** (đăng nhập), làm trước: nó đụng vào gốc tài khoản, và app Android cần API đăng nhập mới.
2. **Terminal thật trên điện thoại**: `2026-11-07-shellx-mobile-terminal-design.md`.
3. **App Android**: `2026-11-07-shellx-android-app-design.md`.

Dự án 2 không phụ thuộc dự án 1 nên chạy song song được ngay. Dự án 3 chỉ cần API của mục 6.2 cho màn đăng
nhập; các phần khác của nó bắt đầu được ngay **[người viết]**.
