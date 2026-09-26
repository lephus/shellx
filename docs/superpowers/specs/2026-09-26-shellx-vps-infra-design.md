# ShellX: chuyển hạ tầng từ Cloudflare sang VPS riêng (thiết kế)

- **Ngày:** 2026-09-26
- **Trạng thái:** chờ người dùng duyệt
- **Thay thế:** các phần hạ tầng Cloudflare trong `2026-09-25-shellx-v1-design.md` (D7, D8, §3 sơ đồ, §10, §11, §13, §15, rủi ro R1/R2). Các phần còn lại của spec v1 giữ nguyên hiệu lực.

## 1. Bối cảnh và các quyết định của người dùng

Relay v1 đã viết xong dưới dạng Cloudflare Worker (Hono) + Durable Object `UserHub` + D1 + rate limiting binding, có 238 test. Ngoài relay còn landing page trên Pages và bản cài desktop trên R2. Hai lý do khiến gói Free không dùng được:

- argon2id tốn vài chục ms CPU mỗi lần băm, vượt giới hạn 10 ms CPU/request của gói Free.
- Quota request mỗi ngày của Workers/Durable Objects gói Free quá nhỏ cho lưu lượng terminal.

Người dùng không muốn trả Workers Paid. Các quyết định (2026-09-26):

| # | Quyết định |
|---|---|
| V1 | Bỏ Cloudflare. Chạy relay, landing page và nơi tải bản cài trên VPS của người dùng. |
| V2 | VPS giữ cấu hình hiện có: Ubuntu, Docker, `jwilder/nginx-proxy` + `jrcs/letsencrypt-nginx-proxy-companion`. ShellX chạy dạng container gắn vào proxy đó. |
| V3 | DNS đặt ở nhà đăng ký tên miền. Các bản ghi A của `shellx.pro`, `www`, `relay`, `download` trỏ về IP VPS (người dùng đã cập nhật, đang chờ đồng bộ). |
| V4 | Relay chuyển sang Node.js + TypeScript, giữ Hono và toàn bộ logic nghiệp vụ. Chỉ thay các phần riêng của Cloudflare (phương án A). |
| V5 | Không có CI. Chỉ có CD: push `main` → build, test trong bước build image, deploy. Tag `desktop-v*` → phát hành bản cài. |
| V6 | Bước build image relay chạy toàn bộ test relay. Test fail thì không deploy. |
| V7 | Database D1 `shellx-production` đã tạo nhầm đã được xóa theo đồng ý của người dùng. |

## 2. Mục tiêu và ngoài phạm vi

**Mục tiêu**
- `https://relay.shellx.pro`, `https://shellx.pro` (và `www` chuyển về), `https://download.shellx.pro` chạy trên VPS, có HTTPS tự động.
- **Giao thức REST/WebSocket giữ y nguyên.** Đường dẫn, mã lỗi, mã đóng 4001/4002/4003, frame CBOR, luật ghép nối và tombstone không đổi, nên `shellx_core`, `shellx_client`, `shellx_agent`, app desktop và app mobile không phải sửa code.
- Push `main` là deploy, có kiểm tra sức khỏe và tự quay lại bản trước khi hỏng.

**Ngoài phạm vi**
- Chạy nhiều máy chủ hoặc nhiều tiến trình relay. v1 dùng một tiến trình trên một VPS; ghi thành rủi ro.
- CI chạy test app desktop/mobile hoặc build Windows. Người dùng đã bỏ CI; các test đó chạy ở máy dev.
- Chống DDoS ở tầng mạng. Không còn Cloudflare phía trước; chỉ có giới hạn tần suất của ứng dụng và của nginx.

## 3. Bố trí trên VPS

Thư mục triển khai là `/opt/shellx`, do workflow deploy đồng bộ từ thư mục `deploy/` trong repo:

```
/opt/shellx/
  docker-compose.yml     # từ deploy/docker-compose.yml
  relay.env              # từ deploy/relay.env (phiên bản tối thiểu, link bản cài; không chứa bí mật)
  .env                   # do workflow ghi: IMAGE_TAG=<commit SHA>, PROXY_NETWORK=<tên network của nginx-proxy>
  downloads/desktop/<version>/ShellX-<version>.dmg | ShellX-Setup-<version>.exe
  backups/relay-<YYYY-MM-DD>.db
```

Compose project `shellx` gồm các service:

| Service | Image | Vai trò |
|---|---|---|
| `relay` | `ghcr.io/lephus/shellx-relay:${IMAGE_TAG}` | Node 22, user không phải root, lắng nghe 8080 trong container, không publish cổng. Env `VIRTUAL_HOST=relay.shellx.pro`, `VIRTUAL_PORT=8080`, `LETSENCRYPT_HOST=relay.shellx.pro`, cộng thêm `relay.env`. Volume `shellx-data:/data` (SQLite `/data/relay.db`). Healthcheck `GET /v1/version`. `restart: unless-stopped`. |
| `web` | `ghcr.io/lephus/shellx-web:${IMAGE_TAG}` | nginx:alpine chứa bản build Astro. `VIRTUAL_HOST=shellx.pro,www.shellx.pro,download.shellx.pro`, `LETSENCRYPT_HOST` cùng danh sách. Mount `./downloads:/srv/downloads:ro`. |
| `backup` | `alpine` + `sqlite` | Chạy mỗi ngày lúc 03:00 (giờ VPS): `sqlite3 /data/relay.db ".backup /backups/relay-<ngày>.db"`, giữ 14 bản gần nhất. Mount volume `shellx-data` chỉ đọc và `./backups`. |

Cả ba service gắn vào network ngoài `${PROXY_NETWORK}` của nginx-proxy; `backup` không cần.

**nginx trong `web`** có ba server block theo `Host`:
- `shellx.pro`: trang tĩnh; trang 404 của Astro.
- `www.shellx.pro`: `301` về `https://shellx.pro$request_uri`.
- `download.shellx.pro`: `/srv/downloads`, không liệt kê thư mục, `Content-Disposition: attachment`.
- `access_log off` cho cả ba, giữ cam kết của chính sách quyền riêng tư.

**nginx-proxy**: file `vhost.d/relay.shellx.pro`, đặt một lần khi dựng VPS, gồm:
- `access_log off;`
- `proxy_read_timeout 120s;` và `proxy_send_timeout 120s;`. Client ping mỗi 30 giây nên WebSocket không bị cắt.
- `client_max_body_size 32k;`. Relay tự giới hạn 16 KiB và trả 413 đúng mã lỗi; nginx chỉ chặn body quá lớn từ sớm.

nginx-proxy đã tự chuyển tiếp nâng cấp WebSocket. Chứng chỉ do letsencrypt-companion cấp qua HTTP-01.

## 4. Relay trên Node

### 4.1 Giữ nguyên
Các module sau giữ nguyên, trừ phần gọi D1 đổi sang SQLite:
- `auth/`: email, domain tạm, chính sách mật khẩu, token, phiên, thiết bị.
- `protocol/`: CBOR, frame, UUID.
- `http/`: giới hạn body, lỗi.
- `routes/`: auth, account, devices, pairings, ws.
- `hub/token-bucket.ts`: 500 frame/giây/kết nối, vượt thì đóng 4003.
- `log.ts`.

Toàn bộ quy tắc trong spec v1 §5, §6, §10.2 vẫn là chuẩn.

### 4.2 Thay thế phần của Cloudflare

| Cloudflare | Trên Node |
|---|---|
| Worker runtime | `@hono/node-server`. `src/server.ts` tạo HTTP server, gắn `ws` (`WebSocketServer({ noServer: true })`) vào sự kiện `upgrade` cho `/v1/ws` sau khi route xác thực token. |
| D1 | `better-sqlite3`, một file `DB_PATH` (mặc định `/data/relay.db`), `journal_mode=WAL`, `foreign_keys=ON`, `busy_timeout=5000`. Một lớp `Db` nhỏ bọc `prepare/run/get/all/transaction`. Các chỗ gọi D1 đổi sang lớp này và dùng transaction đồng bộ thay cho `batch`. |
| Migration D1 | Relay tự chạy migration khi khởi động từ `relay/migrations/*.sql`, theo thứ tự tên file, ghi vào bảng `schema_migrations(name, applied_at)`, mỗi file một transaction. `0001_init.sql` dùng lại nguyên văn. Không có rollback; sửa lỗi bằng migration mới. |
| Durable Object `UserHub` | `HubRegistry` trong tiến trình: `Map<userId, UserHub>`. Hub được tạo khi có kết nối đầu tiên hoặc khi một route REST cần báo cho hub, và bị gỡ khi không còn socket. Chi tiết ở §4.3. |
| Storage SQL của DO (tombstone `pending_pairing_removed`) | Bảng mới trong migration `0002_hub_state.sql`: cùng các cột như bảng của DO, thêm `user_id` và index `(user_id, agent_id)`. Tombstone giữ nguyên ngữ nghĩa: phát lại mỗi khi agent kết nối, cho tới khi có POST mới hơn, agent đăng xuất hoặc tài khoản bị xóa. |
| `setWebSocketAutoResponse("ping","pong")` | Frame text `ping` được trả `pong` ngay trong handler `message`, không qua hàng đợi của hub. |
| `serializeAttachment` | Metadata `{device_id, kind, conn_id, closing}` lưu trên đối tượng socket; không còn hibernation. |
| Rate limiting binding | `SlidingWindowLimiter` trong bộ nhớ: khóa là IP hoặc email, cửa sổ 60 giây, cùng mức cũ (đăng nhập 10/IP và 5/email, đăng ký 3/IP). Định kỳ dọn khóa hết hạn. `RATE_LIMITS_ENABLED=false` chỉ dùng khi chạy local hoặc e2e. |
| argon2id WASM | `@node-rs/argon2`, cùng tham số (m = 19456 KiB, t = 2, p = 1). Tối đa 4 lần băm cùng lúc; lần thứ 5 phải xếp hàng, để giới hạn RAM (4 × 19 MiB). Hash lưu theo chuẩn PHC `$argon2id$…`. |
| `env` binding | `src/config.ts` đọc biến môi trường một lần lúc khởi động: `PORT` (8080), `DB_PATH`, `MIN_AGENT`, `MIN_MOBILE`, `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL`, `RATE_LIMITS_ENABLED`. Thiếu biến bắt buộc thì thoát với lỗi một dòng. |
| IP client (`CF-Connecting-IP`) | Header `X-Real-IP` do nginx-proxy gắn. Khi chạy local không có header thì dùng địa chỉ socket. IP chỉ dùng cho bộ giới hạn tần suất trong bộ nhớ, không ghi log. |

### 4.3 `UserHub` trong tiến trình
- Mỗi tài khoản đúng một hub trong tiến trình. Mọi thao tác thay đổi trạng thái của hub đi qua **một hàng đợi tuần tự** (chuỗi Promise), gồm:
  - socket kết nối hoặc đóng;
  - frame đến;
  - lời gọi từ route REST: ghi hoặc xóa ghép nối, tombstone, đổi mật khẩu, xóa tài khoản, đăng xuất agent.

  Cách này giữ thứ tự mà Durable Object đảm bảo. Lỗi của một thao tác được bắt và ghi log theo loại, không làm hỏng hàng đợi.
- Hành vi giữ như bản Worker:
  - mỗi thiết bị một kết nối, kết nối mới thắng, kết nối cũ nhận 4001;
  - đổi mật khẩu thì các thiết bị khác nhận 4002;
  - xóa tài khoản thì mọi socket nhận 4002 và hàng đợi tombstone bị xóa;
  - PRESENCE khi thiết bị vào và ra;
  - chuyển tiếp DATA giữa các thiết bị cùng tài khoản;
  - EVENT `pairing_removed`;
  - giới hạn 500 frame/giây.
- Route REST gọi thẳng `registry.forUser(userId).<method>()`, thay cho `stub.fetch(...)`.
- **Tắt an toàn:** khi nhận SIGTERM/SIGINT, relay:
  1. ngừng nhận kết nối HTTP và WebSocket mới;
  2. đóng mọi socket bằng mã 1001 ("going away") để client tự kết nối lại theo backoff sẵn có;
  3. chờ các hàng đợi xong, tối đa 5 giây;
  4. đóng DB và thoát.

  Tổng thời gian dưới 10 giây, trong `stop_grace_period` của Compose.
- Relay khởi động lại thì mọi kết nối rớt; client tự kết nối lại và các tab tự gắn lại (plan 03). Giống hành vi khi Cloudflare deploy bản mới.

### 4.4 Script quản trị
`reset-password` chạy trong container: `docker compose exec relay node dist/scripts/reset-password.js`. Script dùng thẳng SQLite, không qua wrangler, và giữ các thông báo lỗi một dòng, không in SQL. Các script `update-disposable-domains` và `blocklist` giữ nguyên, chạy bằng Node.

### 4.5 Gói và build
- `relay/package.json` bỏ `wrangler`, `@cloudflare/vitest-pool-workers`, `@cloudflare/workers-types` và module argon2 WASM. Thêm `@hono/node-server`, `ws`, `better-sqlite3`, `@node-rs/argon2` (phiên bản ghim chính xác) và `tsx` cho dev.
- Build bằng `tsc` ra `dist/`. `npm run dev` chạy relay tại `127.0.0.1:8787` với `DB_PATH=.data/relay.db` và `RATE_LIMITS_ENABLED=false`.
- Xóa `wrangler.jsonc`. `relay/README.md` viết lại cho Node/VPS.

### 4.6 Dockerfile (`relay/Dockerfile`, nhiều bước)
1. `deps`: `node:22-bookworm-slim`, `npm ci`.
2. `test`: chép source, chạy `npm run typecheck && npm test`. Bước này fail thì build dừng, image không ra (V6).
3. `build`: `npm run build`, rồi `npm prune --omit=dev`.
4. `runtime`: `node:22-bookworm-slim`, chép `dist/`, `migrations/`, `node_modules` đã prune; `USER node`; `EXPOSE 8080`; `CMD ["node","dist/server.js"]`.

Image `web` (`web/Dockerfile`): build Astro bằng Node 22 (`npm ci && npm run build`, gồm cả kiểm tra trang và link hiện có), rồi `nginx:alpine` chép `dist/` và `deploy/web/nginx.conf`.

## 5. Kiểm thử
- 238 test relay chuyển sang Vitest chạy Node thuần. Mỗi test dùng DB SQLite trong thư mục tạm, server thật trên cổng ngẫu nhiên và client `ws` thật. Test thay đổi theo nhóm:
  - Test hành vi (REST, WebSocket, hub, tombstone, mã đóng, giới hạn) giữ nguyên ý nghĩa, chỉ đổi phần dựng môi trường.
  - Test gắn với API riêng của Cloudflare (hibernation, `idFromName`, rate limiting binding) được viết lại cho bản tương ứng trên Node.
  - Test argon2 kiểm tra tham số và định dạng PHC.
- Test mới:
  - migration chạy một lần và bỏ qua khi đã chạy;
  - tombstone còn nguyên sau khi relay khởi động lại;
  - tắt an toàn đóng socket bằng 1001;
  - `X-Real-IP` được dùng cho giới hạn tần suất;
  - quá 4 lần băm cùng lúc thì xếp hàng;
  - thiếu biến môi trường bắt buộc thì thoát.
- `shellx_e2e`: chạy với `SHELLX_E2E_RELAY=http://127.0.0.1:8787` sau `npm run dev` trong `relay/`. Phải giữ 7/7 test.
- Sau mỗi lần deploy, workflow gọi `https://relay.shellx.pro/v1/version` và `https://shellx.pro/` (xem §6.1).

## 6. CD

`ci.yml` bị xóa (V5).

### 6.1 `deploy.yml` (push `main`)
- Chạy khi thay đổi thuộc `relay/**`, `web/**`, `deploy/**` hoặc chính `deploy.yml`. Bỏ qua commit chỉ sửa `docs/**`, `apps/**`, `packages/**`, vì app không chạy trên VPS.
- Một job duy nhất, `concurrency: deploy-production` (không hủy lần đang chạy):
  1. Đăng nhập GHCR bằng `GITHUB_TOKEN`. Build và push `shellx-relay:<sha>` (có bước test) và `shellx-web:<sha>`.
  2. Nạp SSH key từ secret `VPS_SSH_KEY`, `known_hosts` từ `VPS_KNOWN_HOSTS` (bắt buộc kiểm tra host).
  3. `rsync` `deploy/docker-compose.yml`, `deploy/relay.env`, `deploy/web/` lên `/opt/shellx/`.
  4. Trên VPS, qua SSH:
     1. lưu `IMAGE_TAG` cũ;
     2. ghi `IMAGE_TAG=<sha>` vào `.env`;
     3. `docker compose pull`;
     4. `docker compose up -d --remove-orphans`;
     5. chờ tối đa 60 giây cho `relay` báo healthy.

     Không healthy thì ghi lại `IMAGE_TAG` cũ, chạy `up -d` lần nữa và workflow fail.
  5. Từ runner: `curl -fsS https://relay.shellx.pro/v1/version` và `curl -fsS https://shellx.pro/`. Lần deploy đầu tiên có thể phải chờ chứng chỉ, nên thử lại tối đa 10 lần, mỗi lần cách 15 giây.
- Image GHCR để **public**, để VPS pull không cần đăng nhập. Image không chứa bí mật.

### 6.2 `release-desktop.yml` (tag `desktop-v*`)
- Giữ nguyên phần build, ký, notarize macOS và ký Windows.
- Bước "Upload to R2" đổi thành `rsync` lên `/opt/shellx/downloads/desktop/<version>/`, dùng cùng các secret SSH. Sau đó kiểm tra `https://download.shellx.pro/desktop/<version>/<file>` trả 200 và đúng kích thước.
- Bỏ `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `R2_BUCKET`.
- Muốn app hiện "có bản mới" thì sửa `LATEST_AGENT_VERSION`, `MAC_URL`, `WIN_URL` trong `deploy/relay.env` và push `main`. Có thể làm cùng lúc với tag.

### 6.3 GitHub secrets
- Mới:
  - `VPS_HOST`, `VPS_USER`;
  - `VPS_SSH_KEY`: key ed25519 chỉ dùng cho deploy;
  - `VPS_KNOWN_HOSTS`: kết quả `ssh-keyscan` của VPS, người dùng tự đối chiếu dấu vân tay.
- Bỏ: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- Giữ: các secret ký/notarize Apple và Azure.

User deploy trên VPS thuộc nhóm `docker` và sở hữu `/opt/shellx`; không cần sudo cho mỗi lần deploy.

## 7. Dựng VPS lần đầu (runbook trong `deploy/README.md`)
Người dùng tự chạy các bước này; Claude chỉ chạy qua SSH khi người dùng cho phép rõ ràng.
1. Tạo user deploy, thêm vào nhóm `docker`, đặt public key deploy vào `authorized_keys`, tạo `/opt/shellx` thuộc user đó.
2. Tìm tên network của nginx-proxy: `docker network ls`, ghi vào `/opt/shellx/.env` dạng `PROXY_NETWORK=…`.
3. Tạo `vhost.d/relay.shellx.pro` theo §3 trong thư mục vhost của nginx-proxy.
4. Chạy `ssh-keyscan <VPS>` trên máy người dùng, đối chiếu dấu vân tay, rồi thêm 4 secret vào GitHub.
5. Push `main` (hoặc chạy lại `deploy.yml`) để deploy lần đầu. Kiểm tra `curl https://relay.shellx.pro/v1/version`.

Phải làm sau khi DNS đã đồng bộ, vì letsencrypt-companion cần tên miền trỏ đúng VPS mới cấp được chứng chỉ.

## 8. Vận hành
- **Log:** `docker compose logs relay`. Relay chỉ ghi metadata (thời gian, `device_id`, loại lỗi), không ghi IP, email, token hay payload. Docker giới hạn log ở `max-size 10m`, `max-file 3`.
- **Sao lưu:** container `backup` chạy hằng ngày (§3). Khôi phục: dừng `relay`, chép bản sao lưu vào volume, rồi chạy lại. Chép bản sao lưu ra ngoài VPS là tùy người dùng, runbook ghi cách làm bằng `rsync`.
- **Quay lại bản cũ:** chạy lại `deploy.yml` ở commit cũ (workflow_dispatch với input `ref`), hoặc trên VPS sửa `IMAGE_TAG` trong `.env` rồi `docker compose up -d`.
- **Cập nhật phiên bản tối thiểu hoặc link bản cài:** sửa `deploy/relay.env` rồi push.

## 9. Quyền riêng tư, pháp lý và tài liệu
- `web/src/pages/privacy.md` và `en/privacy.md`:
  - thay đoạn "hạ tầng của Cloudflare, Inc. (Workers, Durable Objects, D1, R2, Pages)" bằng "máy chủ riêng do ShellX thuê tại **[quốc gia]**";
  - giữ các cam kết không cookie, không analytics, IP chỉ dùng tạm để giới hạn tần suất, không ghi log truy cập;
  - cập nhật `updated:`.

  Làm tương tự với `terms.md` nếu có nhắc Cloudflare. **Quốc gia đặt VPS là thông tin người dùng cung cấp sau; phải điền trước khi deploy bản web công khai.** Tới lúc đó, bước build web từ chối build nếu còn chữ đánh dấu `[quốc gia]`.
- Spec v1:
  - sửa D7, D8, sơ đồ §3, bảng thành phần, §10 (relay: Node, SQLite, hub trong tiến trình), §11 (deploy), §13, §15;
  - thay rủi ro R1/R2 bằng R-VPS (§10 của tài liệu này);
  - ghi chú đầu spec trỏ tới tài liệu này.
- `docs/superpowers/HANDOFF.md`, `relay/README.md` (dev và test), `deploy/README.md` (runbook), `web/README.md` (bỏ Pages, trỏ tới deploy).

## 10. Rủi ro
| # | Rủi ro | Giảm thiểu |
|---|---|---|
| R-VPS1 | Một VPS là điểm lỗi duy nhất: VPS chết thì toàn bộ dịch vụ dừng | Chấp nhận cho v1. Sao lưu SQLite hằng ngày. Runbook dựng lại từ image GHCR và bản sao lưu. |
| R-VPS2 | Không còn lớp chống DDoS phía trước | Giới hạn tần suất ở relay. Có thể thêm `limit_req` trong vhost của nginx-proxy khi cần. |
| R-VPS3 | Không có CI, lỗi app desktop/mobile và build Windows không được phát hiện tự động | Chạy test ở máy dev trước khi push. Relay có test trong bước build image. Người dùng đã chấp nhận (V5). |
| R-VPS4 | argon2 dùng 19 MiB mỗi lần băm, nhiều lần cùng lúc có thể làm hết RAM | Tối đa 4 lần cùng lúc (§4.2), cộng giới hạn đăng nhập/đăng ký theo IP và email. |
| R-VPS5 | Deploy làm rớt mọi WebSocket | Client tự kết nối lại và gắn lại tab. Chỉ deploy khi relay, web hoặc deploy thay đổi. |
| R-VPS6 | Chứng chỉ chưa cấp được khi DNS chưa đồng bộ | Dựng lần đầu sau khi DNS đã trỏ đúng. Workflow thử lại khi kiểm tra HTTPS. |

## 11. Dọn Cloudflare
- Đã xong: xóa D1 `shellx-production`; bỏ commit ghi id D1 chưa push.
- Trong repo: xóa `relay/wrangler.jsonc`, bỏ phụ thuộc Cloudflare (§4.5), bỏ bước R2 (§6.2), bỏ hướng dẫn Pages trong `web/README.md`.
- Người dùng tự làm khi nameserver đã chuyển hẳn về nhà đăng ký: xóa zone `shellx.pro` trên Cloudflare và thu hồi quyền OAuth của wrangler (`npx wrangler logout`).

## 12. Việc còn mở
1. Quốc gia đặt VPS, để ghi vào chính sách quyền riêng tư (§9). Người dùng trả lời sau.
2. Tên network Docker của nginx-proxy trên VPS (§7 bước 2). Người dùng đọc từ `docker network ls` khi dựng.
