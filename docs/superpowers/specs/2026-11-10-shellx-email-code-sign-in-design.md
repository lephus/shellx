# ShellX: đăng nhập bằng email và mã OTP (gửi qua Resend) — đặc tả thiết kế

Ngày: 2026-11-10. Bổ sung cho đặc tả đăng nhập Google `2026-11-07-shellx-google-sign-in-design.md` (S1).
Nhãn: **[người dùng]** là quyết định của người dùng; **[người viết]** là quyết định của người viết, người dùng
có thể đổi. Trạng thái: **bản đề xuất, chờ người dùng duyệt** (các câu hỏi mở ở mục 11).

## 1. Ý định và lý do

Người dùng yêu cầu 2026-11-10: "làm thêm cho tôi một option là login bằng cách nhập email và nhận mã OTP từ
ứng dụng gửi qua mail bằng resend; nhập OTP xong là đăng nhập" **[người dùng]**. Hoàn thành thì đẩy lên
`develop` **[người dùng]**.

Lý do (người viết suy ra): không phải ai cũng có hoặc muốn dùng tài khoản Google (email công ty, email
Việt Nam không phải Gmail, máy Android không có Google Play services, desktop không muốn mở trình duyệt).
Mã gửi qua email là cách vào thứ hai không cần nhà cung cấp danh tính nào, và vẫn chứng minh được người
dùng kiểm soát hộp thư, đúng mức tin cậy mà "đặt lại mật khẩu qua email" trước đây dựa vào.

S1 §3 từng loại "magic link qua email" **[người viết, 2026-11-07]**; đặc tả này đảo quyết định đó theo yêu
cầu mới của người dùng, nhưng chọn **mã số** thay cho **đường link**: mã gõ được trên máy khác với máy nhận
mail (đọc mail trên điện thoại, gõ mã trên Mac), không cần deep link, không có đường link để giả mạo.

## 2. Mục tiêu, không mục tiêu, phản mục tiêu

Mục tiêu:
- Một cách vào thứ hai trên mọi app có màn đăng nhập (Mac, Windows, iPhone, Android), bên cạnh Continue with
  Google (và Apple trên iPhone), dùng chung mô hình tài khoản, thiết bị, phiên và kiểu lỗi hiện có.
- Relay chỉ cần `RESEND_API_KEY` là đăng nhập được, không phụ thuộc Google hay Apple được cấu hình.
- An toàn mặc định: chỉ lưu băm, mã sống ngắn, giới hạn số lần đoán và tần suất, không ghi email hay mã vào
  log, không thêm cách dò tài khoản mới.
- Tài khoản chỉ có email vẫn tự xoá được trong app (Apple và Google Play bắt buộc).

Không mục tiêu: magic link; quay lại mật khẩu; đổi email tài khoản; gửi mail tiếp thị hay thông báo khác;
SMS; đổi giao diện đăng nhập ngoài phần thêm vào.

Phản mục tiêu (làm xong vẫn thất bại nếu xảy ra): mã đoán được trực tuyến; relay không khởi động được khi
thiếu Resend; địa chỉ email lọt vào log; hai mô hình tài khoản song song; app cũ hỏng với relay mới.

## 3. Trải nghiệm người dùng (mọi app)

Màn đăng nhập hôm nay có Continue with Google (iPhone thêm Apple; điện thoại thêm "Try without an account";
Mac và Windows là một hộp thoại chỉ có nút Google). Thêm:

1. Dưới các nút có sẵn: vạch "hoặc" và nút phụ **Continue with email**.
2. Bấm vào → **bước email**, ngay trong màn đó (không route mới): ô nhập email (bàn phím email, autofill
   username), nút **Send code** (bật khi ô có `@` và dấu chấm sau đó; relay mới kiểm tra thật); trên điện
   thoại link "Try without an account" vẫn còn.
3. Relay trả 202 → **bước mã**: "We sent a code to foo@bar.com", ô 6 chữ số (bàn phím số, kiểu one-time
   code để iPhone/Android tự điền khi hệ điều hành đọc được), nút **Verify** (tự gửi khi đủ 6 số), **Resend
   code** (khoá 60 giây, đếm ngược), **Use a different email** (quay lại bước 2).
4. Mã đúng → đăng nhập xong theo đúng đường của Google (lưu phiên với `auth_method = "email"`, sang màn đã
   đăng nhập). Lỗi hiện ngay dưới ô nhập (mục 5).

Settings › Account: hàng phương thức đăng nhập hiện "Email code · foo@bar.com" cho identity `email`.
**Delete Account** (chỉ điện thoại, như hôm nay) với phiên `email`: hộp thoại gửi mã tới email của tài khoản
rồi hỏi mã (thay cho xác nhận lại bằng Google); phiên Google giữ xác nhận bằng Google như cũ. Mac và
Windows giữ đường link tới trang privacy (`#delete-account`) cho mọi phiên **[người viết]**; trang đó nói
thêm "hoặc xoá trong app điện thoại, Settings › Account".

Ngôn ngữ email: theo ngôn ngữ app (`vi` → tiếng Việt, còn lại tiếng Anh) **[người viết]**.

## 4. Relay: API

Hai route mới mount tại `/v1/auth/email` (file `relay/src/routes/email-sign-in.ts`), cùng kiểu lỗi
`{"error":{"code","message"}}` và giới hạn body 16 KiB như các route đăng nhập khác.

```
POST /v1/auth/email/code     {email, locale?: "en"|"vi"}
  -> 202 {challenge_id, expires_in: 600, resend_in: 60, email}      email đã chuẩn hoá (trim, lowercase)
     400 invalid_email | 400 disposable_email | 429 rate_limited
     503 email_sign_in_disabled (relay không có RESEND_API_KEY)
     502 email_send_failed (Resend lỗi / quá hạn 10 s; challenge bị xoá)

POST /v1/auth/email/verify   {challenge_id, code, device}           device như /v1/auth/google (kind ≠ agent)
  -> 200 {user_id, device_id, token, email}                          đúng shape của /v1/auth/google
     401 invalid_code          sai mã; challenge còn, đếm thêm một lần
     410 code_expired          challenge không có, hết hạn, đã dùng, hoặc đây là lần sai thứ 5 (challenge bị xoá)
     409 switch_from_signed_in_device   tài khoản mật khẩu khi PASSWORD_LOGIN=on (như Google)
     400 invalid_device | 429 rate_limited

DELETE /v1/account           bearer + {challenge_id, code}           thêm cách xác nhận lại thứ ba
  -> 204; 401 invalid_code | 410 code_expired | 401 reauth_required (mã của email khác email tài khoản)
```

Quy tắc:
- `challenge_id`: 32 byte ngẫu nhiên base64url (43 ký tự, `generateToken()`); DB chỉ giữ `sha256(challenge_id)`.
- Mã: 6 chữ số từ `crypto.randomInt(0, 1_000_000)` có đệm số 0; DB chỉ giữ `sha256(challenge_id + ":" + code)`.
  Ai đọc được DB vẫn không đoán nổi mã vì thiếu `challenge_id` (128 bit), đúng cách relay giữ token và nonce.
  So băm bằng `timingSafeEqual`.
- Hạn 10 phút (600 s), tối đa 5 lần đoán một mã, mỗi email chỉ mã mới nhất còn hiệu lực (xin mã mới xoá
  challenge cũ của email đó). Tối đa 50 000 challenge sống (→ 429), như nonce.
- Tần suất (bộ `SlidingWindowLimiter` có sẵn, thêm vào `RateLimiters` + `unlimited` của test):
  `emailCodeIp` 10/phút mỗi IP; `emailCodeEmail` 3/phút **và** 10/giờ mỗi email (hai limiter, cửa sổ
  60 s và 3 600 s); `/verify` dùng `loginIp` 10/phút có sẵn; `DELETE /v1/account` giữ `loginEmail` 5/email
  như hôm nay (`relay/src/routes/account.ts`). Kẻ dò mã nhận nhiều nhất 50 lần
  đoán mỗi giờ cho một địa chỉ (xác suất 5·10⁻⁵/giờ) và nạn nhân thấy 10 email lạ mỗi giờ.
- Email được `checkEmail` (`relay/src/auth/email.ts`) kiểm: sai cú pháp → `invalid_email`; domain dùng một
  lần → `disposable_email`, kể cả khi tài khoản đã có **[người viết]**.
- 202 trả cho mọi địa chỉ hợp lệ, không lộ việc tài khoản có hay chưa (lần `/verify` đầu tự tạo tài khoản).
- Email không chứa đường link. Tiêu đề `Your ShellX sign-in code is 123456` / `Mã đăng nhập ShellX của bạn là
  123456`; thân (text + HTML tối giản): nhập mã trong 10 phút; nếu không yêu cầu thì bỏ qua, không ai vào
  được nếu không có mã; ShellX không bao giờ hỏi mã này. Người gửi `EMAIL_FROM`.
- Log chỉ metadata (`logMeta`): `email_code_sent {locale}`, `email_code_refused {reason}`, `sign_in {provider:
  "email", via}`, `email_send_failed {status|error}`. Không bao giờ email, mã, challenge, IP.

## 5. Relay: tài khoản và identity

Identity mới `provider = 'email'`, `subject` = địa chỉ đã chuẩn hoá. `IdentityProvider` thêm `"email"`,
`AuthMethod` thêm `"email"`; `tokens.auth_method = 'email'`, `tokens.identity_id` trỏ tới identity này.

Phân giải tài khoản dùng lại `matchAccount` với một `VerifiedIdToken` tổng hợp `{provider: "email", subject:
email, email, isPrivateEmail: false}`:

| `matchAccount` | Google (giữ như cũ) | Email (mới) |
| --- | --- | --- |
| `identity` | đăng nhập, cập nhật `last_used_at` | như Google |
| `switch_required` (PASSWORD_LOGIN=on, còn mật khẩu) | 409 | 409 |
| `email`, `hasPrimary` = đã có identity Google | 401 (địa chỉ tái sử dụng) | **nối**: thêm identity `email` vào tài khoản đó; tài khoản giữ cả Google và email |
| `email`, không `hasPrimary` | bỏ mật khẩu + thêm identity | như Google |
| `none` | tài khoản mới + identity | như Google |

**Quyết định nối theo email [người viết, hỏi lại ở mục 11]:** mã vừa gửi tới chính địa chỉ đó là chứng
minh kiểm soát hộp thư ngay lúc này — mạnh hơn `email_verified` của Google và ngang với "đặt lại mật khẩu
qua email" mà relay từng có. Khác với Apple (S1: Apple không bao giờ nối theo email, vì địa chỉ Apple có
thể là địa chỉ ẩn và không được xác minh tại chỗ). Phương án thay thế nếu người dùng muốn chặt hơn: identity
email không nối, tài khoản mới, nối qua Mac (QR + Allow) như Apple.

Sửa kèm để hai kiểu identity sống chung trong một tài khoản (bốn chỗ hôm nay viết `!= 'apple'`):
- `hasPrimary` tính theo `provider IN ('google','test')` (`identity.ts:31`): tài khoản tạo bằng email rồi
  đăng nhập Google cùng địa chỉ → Google **nối** vào (không còn bị 401 nhầm). Cùng sửa ở `/google/link`
  (`sign-in.ts:115`, kiểm `identity_in_use`/`email_in_use`) và ở quy tắc bỏ identity (`identities.ts:55`).
- Index `identities_one_primary` (`0010_identities.sql:32`) → `WHERE provider IN ('google','test')`; thêm
  `identities_one_email` `UNIQUE (user_id) WHERE provider = 'email'`.
- Identity email cũ khi email tài khoản đổi: `/google/link` là chỗ duy nhất ghi lại `users.email`
  (`sign-in.ts:118-121`); nếu địa chỉ mới khác địa chỉ cũ, identity `email` của tài khoản bị xoá (token của
  nó cascade, các máy đã vào bằng địa chỉ cũ phải đăng nhập lại) — một địa chỉ không còn là email tài khoản
  thì không được mở tài khoản nữa **[người viết]**. Mã gửi tới địa chỉ mới sau đó nối bình thường.
- Tài khoản mật khẩu cũ trong lúc `PASSWORD_LOGIN=on` (trước cắt mật khẩu của 1D): `/verify` trả 409 như
  Google, app hiện thông điệp "switch" sẵn có (đổi sang Google từ máy đã đăng nhập); **không** làm
  `/v1/auth/email/link` trong đợt này **[người viết]**. Sau cắt mật khẩu, mã email vào thẳng (hàng
  "không `hasPrimary`").
- `DELETE /v1/account/identities/:id`: không cho bỏ identity cuối cùng tự đăng nhập được (google, test
  hoặc email); mã lỗi giữ `last_google_identity` để app cũ không đổi, thông điệp app mới nói chung "giữ ít
  nhất một cách đăng nhập" **[người viết]**.
- `GET /v1/account/identities` trả `provider: "email"` (shape không đổi).

Migration `relay/migrations/0011_email_sign_in.sql` (`-- migrate: foreign_keys=off`): rebuild `identities`
và `tokens` để nới CHECK (`provider IN ('google','apple','email','test')`, `auth_method IN
('password','google','apple','email','test')`), tạo lại index, thêm bảng:

```sql
CREATE TABLE email_codes (
  id             TEXT PRIMARY KEY,                 -- UUID, dùng làm Idempotency-Key gửi Resend
  challenge_hash BLOB NOT NULL UNIQUE,             -- sha256(challenge_id)
  code_hash      BLOB NOT NULL,                    -- sha256(challenge_id || ':' || code)
  email          TEXT NOT NULL,                    -- đã chuẩn hoá; sống tối đa 10 phút
  attempts       INTEGER NOT NULL DEFAULT 0,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL
);
CREATE INDEX email_codes_email ON email_codes (email);
CREATE INDEX email_codes_expires_at ON email_codes (expires_at);
```

Dọn: mỗi lần `/code` xoá các hàng hết hạn (như `issueNonce`); `/verify` xoá hàng khi đúng, khi hết hạn hoặc
khi sai lần thứ 5.

## 6. Relay: gửi mail và cấu hình

- `EmailGateway { send(message: {to, subject, text, html, idempotencyKey}): Promise<{ok: true} | {ok: false,
  status?, error?}> }` với `ResendClient` (`relay/src/email/resend.ts`): `POST https://api.resend.com/emails`,
  header `Authorization: Bearer <RESEND_API_KEY>`, `Idempotency-Key`, body `{from, to: [email], subject,
  text, html}`, `AbortSignal.timeout(10_000)`, `fetch` tiêm được như `AppleRestClient`. 2xx là gửi được; mọi
  thứ khác → `email_send_failed` (relay không thử lại; người dùng bấm Resend).
- Cấu hình: `RESEND_API_KEY` (bí mật, chỉ qua `.env` trên VPS, passthrough trong `deploy/docker-compose.yml`)
  và `EMAIL_FROM` (ví dụ `ShellX <sign-in@shellx.pro>`; domain phải được xác minh trong Resend). Cả hai có →
  bật (`logMeta("email_sign_in_enabled")`); cả hai thiếu → tắt (`email_sign_in_disabled`, `/code` trả 503);
  chỉ một → `ConfigError`, relay dừng (như cặp `TEST_IDP_*`). `relay/README.md` bảng env, `deploy/README.md`
  mục "Email sign-in (once, by hand)": tạo tài khoản Resend, thêm và xác minh domain (bản ghi DKIM/SPF Resend
  đưa), tạo API key quyền gửi, đặt hai biến, rollout. Trước khi domain xác minh, Resend chỉ gửi từ
  `onboarding@resend.dev` tới địa chỉ chủ tài khoản — đủ để thử.
- Test: vitest với `fetch` giả (gateway nhận gì, 2xx/5xx/timeout), fake `now` cho hạn và cửa sổ limiter, 5
  lần sai, mã mới xoá mã cũ, các ca nối tài khoản của bảng mục 5, `DELETE /v1/account` bằng mã, quy tắc bỏ
  identity, `npm run typecheck`. Helper test `requestEmailCode`/`signInEmail` lấy mã từ gateway giả.

## 7. Các app

Chung: mô hình bước (idle → email → sending → code → verifying → done) tách khỏi UI để test được; đếm ngược
60 s qua clock tiêm được; ánh xạ lỗi mục 4 vào chuỗi; `locale` theo ngôn ngữ app; sau 200 đi đúng đường
hoàn tất của Google; không gọi thêm endpoint khám phá: relay cũ trả 404 `not_found` → hiện "This way of
signing in isn't available in this build" (`signin.error.providerUnavailable` có sẵn trên iPhone) **[người
viết]**, 503 `email_sign_in_disabled` cũng vậy.

Chuỗi mới (iPhone catalog en + vi, Android import; Mac `remote.signin.email.*` 10 ngôn ngữ qua
`scripts/localize-changes`; Windows `strings.rs` en/vi): `signin.email.continue`, `.or`, `.field`, `.send`,
`.sentTo` (%@), `.code`, `.verify`, `.resend`, `.resendIn` (%lld), `.change`; `signin.error.invalidEmail`,
`.disposableEmail`, `.invalidCode`, `.codeExpired`, `.emailSendFailed`; `settings.account.method.email`;
`settings.account.delete.codeIntro`, `.codeField`. Tên cuối cùng do plan chốt theo quy ước từng app.

- **iPhone** (`shellx-ios/` + gói MIT `shellx-link/Sources/ShellXLinkAccount/RelayAPI+SignIn.swift`, test
  riêng `ShellXLinkAccountTests`): `RelayAccountCalling` + `RelayAPI+SignIn.swift` thêm `requestEmailCode(email:
  locale:)`, `signInWithEmailCode(challengeID:code:)`, `deleteAccount(challengeID:code:)`; `AccountAuthMethod`
  thêm `.email`; `AppCoordinator` thêm `EmailSignInModel` (bước, đếm ngược, lỗi) và hoàn tất qua
  `completeSignIn`; `SignInView` thêm nút và hai bước; `DeleteAccountSheet` nhánh mã; `AccountSection` nhãn;
  fakes `FakeRelayAccount`. Test `dev.sh test core|app`, ảnh en + vi qua `dev.sh screenshots`.
- **Android** (`shellx-android/`, `shellx-link/kotlin/link-account`): `RelayApi` + DTO (`EmailChallenge`),
  `RelayAccountCalling`/`RelayAccountClient`, `SignInException` thêm các mã, `AppCoordinator` +
  `EmailSignInModel` (StateFlow) trong `:core`, `StoredSession` thêm `authMethod` (thiếu → `google`;
  `AccountVault` mã hoá thêm trường), `SignInView` Compose (ô email; ô mã `KeyboardType.Number` +
  `autofillHints`), `SignInErrorText`, `AccountSection`, `DeleteAccountDialog` nhánh mã cho phiên `email`;
  `ScriptedRelay` test; `dev.sh test link|core|app`, `screenshots record`.
- **Desktop chung** (`shellx-core/` Rust): RPC `auth.email.begin {email, locale}` → `{challenge_id,
  expires_in, resend_in, email}`, `auth.email.finish {challenge_id, code}` → phiên (device từ khoá máy như
  `auth.google.finish`; `session.json.auth_method = "email"`); `KNOWN_METHODS`, dispatch, `api.rs`, `fake-api`
  thêm hai route, `tests/email.rs`. Không có xoá tài khoản trên desktop (giữ như hôm nay).
- **Mac** (`Sources/ShellX/Remote/UI`, `Packages/Shared/ShellXBrand`): `ShellXRemoteServicing` +
  `ShellXAccount` thêm hai bước (`Identity.authMethod` là String, nhận `"email"`); `EmailSignInModel` trong
  `ShellXRemoteUI` (test được, cạnh `GoogleSignInModel`); `SignInSheet` thêm nút, ô email, ô mã;
  `SignInErrorMessage` các mã mới; `ShellXAccountDetailView` nhãn phương thức; chuỗi qua `localize-changes`,
  `localization_catalog.py check`, `tests/test_shellx_vi.py`. Test gói + `scripts/shellx/test-app.sh <Suite>`;
  không `xcodebuild` trần.
- **Windows** (`windows/`): `shellx-model` `AccountState/Event/Action` thêm các bước (test `cargo test -p
  shellx-model` chạy được trên Mac); `core_api.rs` hai method; `login.rs` thêm nút và hai ô theo mẫu hộp
  thoại Google; `settings.rs` nhãn; `strings.rs` en/vi + test khớp chuỗi Mac. Bản release của `shellx-app`
  biên dịch được trên Mac (`cargo build --release -p shellx-app`, ảnh qua `dev/mac-shot.sh`,
  `windows/README.md`); chỉ test debug của `shellx-app` không chạy trên Mac — kiểm UI bằng ảnh, để cuối.

Thứ tự làm và hạ cánh (mỗi phần một nhánh, review xong merge vào `develop` và push): relay → Android → iPhone →
shellx-core + Mac → Windows **[người viết; hỏi ở mục 11]**. Các app giả relay trong test nên không chờ relay
chạy thật; hợp đồng API ở mục 4 là nguồn duy nhất.

## 8. Rollout và tài liệu

- Relay chạy production hôm nay chưa có 1A (trả 404 cho `/v1/auth/nonce`); tính năng này lên cùng đợt 1D:
  migration 0011 chạy lúc khởi động, hai biến môi trường do người dùng đặt trên VPS.
- App mới với relay cũ: nút email hiện, bấm gửi → "không khả dụng" (404); không hỏng gì khác. App cũ với relay
  mới: không đổi (shape cũ giữ nguyên, mã lỗi cũ giữ nguyên).
- `web/src/pages/privacy.md` mục Account: "We do not send verification or marketing emails" → "We send a
  sign-in code by email only when you ask for one (through Resend, resend.com); no marketing email"; mục
  Sign-in methods thêm identity email. Trang web chỉ lên khi người dùng push `main` (quy tắc web).
- Hợp đồng `2026-11-07-shellx-mobile-contracts.md`: thêm mục mới cho API, mã lỗi, chuỗi và `AccountAuthMethod`
  khi hạ cánh. Hand-off `HANDOFF-shellx-mobile.md`: việc người dùng (Resend, biến môi trường, 1D).

## 9. Rủi ro

- **Email vào spam / chậm**: domain chưa xác minh hay DKIM sai → mã không tới. Giảm: runbook kiểm tra domain
  Resend "Verified" trước khi bật; nút Resend sau 60 s; thông điệp "kiểm tra thư rác".
- **Resend ngừng hoạt động**: relay trả 502, Google/Apple vẫn vào được; không hàng đợi, không thử lại
  **[người viết]**.
- **Dò mã**: 10⁶ không gian, 5 lần/mã, 50 mã/giờ/email → 5·10⁻⁵ mỗi giờ, nạn nhân thấy email lạ. Chấp nhận.
- **Nối theo email nhầm người** (địa chỉ Gmail tái sử dụng sau khi chủ cũ xoá): rủi ro vốn có của mọi đăng
  nhập qua email, ngang đặt lại mật khẩu; chủ cũ đã mất hộp thư thì cũng mất Google. Chấp nhận, ghi ở mục 5.
- **Giới hạn Resend miễn phí** (100 email/ngày, 3 000/tháng): đủ cho giai đoạn này; vượt → 502 cho tới ngày
  mai; nâng gói là việc người dùng.
- **Windows UI chỉ kiểm bằng ảnh trên Mac** (test debug của `shellx-app` không chạy ở đây): có thể cần một
  vòng sửa khi build Windows thật trên VPS.
- **Tài khoản mật khẩu cũ** trong lúc chưa cắt mật khẩu nhận 409 với thông điệp nói về Google; chấp nhận vì
  cắt mật khẩu đi cùng 1D và số tài khoản ấy ít.
- **DB đọc được bởi kẻ tấn công**: không có mã lẫn challenge_id trong DB → không đăng nhập được; email chờ
  mã lộ trong tối đa 10 phút (users.email vốn đã lưu rõ).

## 10. Việc để lại cho người làm (plan)

Tên file và chuỗi cuối cùng theo quy ước từng app; bố cục ô 6 số (một ô hay sáu ô); cách chia bước trong
`SignInView` của mỗi app; cách test đếm ngược; ảnh chụp en + vi; nội dung HTML của email (tối giản, không
ảnh); thứ tự rebuild bảng trong migration; có dùng override URL relay cho thử tay trên emulator/simulator hay
không (nếu app có sẵn); hợp đồng và hand-off khi hạ cánh.

## 11. Câu hỏi mở cho người dùng

1. **Phạm vi app**: cả bốn (Mac, Windows, iPhone, Android) theo thứ tự relay → Android → iPhone → Mac →
   Windows, hay chỉ điện thoại trước? Mặc định: cả bốn.
2. **Nối tài khoản theo email** (mục 5): mã gửi tới foo@gmail.com đăng nhập vào tài khoản đã tạo bằng Google
   foo@gmail.com, tức ai kiểm soát hộp thư thì vào được tài khoản đó và các Mac đã nối. Quyết định 2026-11-08
   cho Apple ("xác minh hộp thư một lần không được mở tài khoản chạm tới terminal của Mac") đi ngược điều
   này; với mã email thì hộp thư được xác minh ngay lúc đó, và tài khoản tạo bằng email vốn đã là "hộp thư
   = tài khoản". Mặc định: có. Thay thế: tài khoản riêng, nối qua Mac (QR + Allow) như Apple — thêm một bảng
   kiểu `apple_links` cho email và màn "Connect to your Mac" trên cả Android (hôm nay chưa có).
3. **Địa chỉ gửi**: `ShellX <sign-in@shellx.pro>`? Người dùng cần xác minh domain đó trong Resend (DNS) và đặt
   `RESEND_API_KEY`, `EMAIL_FROM` trên VPS; không gửi key qua chat. Nếu muốn tôi gửi thử một mã thật từ relay
   chạy local tới email của bạn, đặt key vào `/Users/richard/Downloads/key/resend` và nói "thử gửi".
4. Các mặc định nhỏ (6 số, 10 phút, 5 lần, 60 s resend, 3/phút và 10/giờ mỗi email, email vi/en, xoá tài
   khoản bằng mã chỉ trên điện thoại, desktop giữ link privacy, không `/email/link` cho tài khoản mật khẩu
   cũ, identity email cũ bị xoá khi `/google/link` đổi email tài khoản, sửa trang privacy) — nói nếu muốn khác.

**Trả lời của người dùng (2026-11-11):** (1) cả bốn app; (2) có, mã email vào cùng tài khoản đã tạo bằng Google với
đúng email đó; (3) người gửi mặc định `ShellX <sign-in@shellx.pro>` (domain `shellx.pro` đã xác minh trong Resend;
một địa chỉ `gmail.com` không dùng làm người gửi được vì Resend chỉ gửi từ domain đã xác minh); (4) giữ các mặc định
nhỏ. Kế hoạch: `docs/superpowers/plans/2026-11-11-shellx-email-code-signin-{relay,android,ios,core-mac,windows}.md`.
