# Thiết kế: Làm lại web marketing shellx.pro theo phong cách terminal

Ngày: 2026-09-28 · Trạng thái: đã duyệt qua hội thoại (toàn trang terminal, nội dung marketing đầy đủ, tông modern dark + cyan, hướng zero-dependency)

## 1. Mục tiêu và tiêu chí thành công

Trang `shellx.pro` hiện quá sơ sài cho mục đích marketing. Làm lại để:

- Truy cập vào là thấy **một phiên terminal** — khí chất hacker/IT, khớp với chính sản phẩm (remote terminal), theo tông **modern dark + cyan** (nền `#0b1120`, chữ `#e2e8f0`, prompt cyan `#22d3ee`, trạng thái ✓ xanh lá; không scanline, không glow CRT).
- **SEO kỹ thuật tối đa**: Lighthouse SEO 100, Performance ≥ 95, Accessibility 100, Best Practices 100; đủ meta/OG/sitemap/robots/JSON-LD; nội dung đủ dày (features, security, FAQ) để có cái mà xếp hạng.
- Không phá bất cứ cam kết hay hạ tầng nào đang chạy.

## 2. Ràng buộc cứng (từ privacy policy đã publish và hạ tầng)

- **Không cookie, không script/font/CDN bên thứ ba, không analytics.** Mọi tài nguyên self-host từ `shellx.pro`. Một test build mới sẽ cưỡng chế điều này (mục 7).
- **Nội dung phải là HTML ngữ nghĩa render sẵn** — hiệu ứng chỉ là lớp phủ; không JS thì trang vẫn nguyên vẹn.
- Giữ nguyên: cấu trúc URL (`/`, `/en/`, `/privacy/`, `/terms/`, `/en/...`), hệ i18n `ui.ts` (vi mặc định + en), `site.config.json`, guard `[quốc gia]`, `Dockerfile`/nginx, các test build cũ (link installer `data-platform`, store `data-store`/`aria-disabled`).
- Stack: Astro, **không thêm dependency nào**.

## 3. Kiến trúc

File đụng tới, tất cả trong `web/`:

- `src/layouts/Base.astro` — theme terminal tối cố định (`color-scheme: dark`, bỏ light mode), header thành dòng brand kiểu shell (vd `~/shellx`, chuyển ngữ dạng `--lang=en`), footer tối; nhận thêm props SEO (og image, JSON-LD).
- `src/layouts/Legal.astro` — chỉ khoác theme tối; thân privacy/terms giữ chữ sans dễ đọc.
- `src/components/Terminal.astro` — mới: khung cửa sổ terminal (title bar `shellx@pro — zsh`, 3 chấm trang trí `aria-hidden`).
- `src/components/TermBlock.astro` — mới: một cặp "prompt lệnh → output"; prompt `$` là trang trí (`aria-hidden`), heading/list bên trong là HTML thật.
- `src/components/Home.astro` — dựng lại thành phiên terminal 6 khối (mục 4). `Downloads.astro` được re-skin nhưng **giữ nguyên markup hợp đồng với test** (href installer, `data-platform`, `data-store`, `aria-disabled`).
- `src/pages/404.astro` — re-skin thành `command not found`.
- `public/fonts/` — JetBrains Mono woff2 subset (regular + bold, latin + vietnamese), tổng mục tiêu ≤ ~60 KB.
- `src/scripts/type-effect.js` (hoặc `<script>` trong component) — ~3 KB JS thuần: IntersectionObserver phủ hiệu ứng gõ chữ khi khối cuộn vào tầm nhìn; tôn trọng `prefers-reduced-motion: reduce` (tắt hẳn); con trỏ █ nhấp nháy bằng CSS.
- `public/robots.txt`, `public/og/` (ảnh OG), sitemap (mục 6).
- `src/i18n/ui.ts` — thêm chuỗi mới cho features/security/FAQ, đủ cả vi lẫn en.

## 4. Bố cục trang chủ — 6 khối lệnh

Mỗi section một cặp lệnh→output; toàn bộ là nội dung thật cho bot:

1. `$ shellx connect` — Hero: `✓ paired · e2e encrypted`, rồi **H1 = tagline** + intro (tái dùng copy hiện có).
2. `$ shellx --features` — 5-6 gạch đầu dòng: điều khiển terminal từ xa, mã hóa đầu cuối Noise, không cần mở port router, nhiều phiên cùng lúc, chạy macOS/Windows/iOS/Android.
3. `$ shellx pair --qr` — "Bắt đầu trong ba bước" (copy hiện có).
4. `$ shellx security` — Noise E2E (relay không đọc được nội dung), mật khẩu argon2id, không log nội dung terminal; link `/privacy/`.
5. `$ shellx download` — nội dung `Downloads.astro` hiện có, re-skin; App Store/Google Play vẫn "sắp ra mắt" từ `site.config.json`.
6. `$ shellx faq` — 4-5 `<details>/<summary>`: có cần mở port không; mất mạng giữa chừng thì sao; ShellX lưu dữ liệu gì; giá; nền tảng hỗ trợ.

Mỗi section có heading thật (h2, hero là h1). Trang chủ mỗi ngôn ngữ đúng **một h1**.

## 5. Hiệu ứng và accessibility

- HTML render sẵn 100%; JS chỉ animate phần hiển thị. Fallback không JS = trang tĩnh đầy đủ.
- `prefers-reduced-motion: reduce` → không animation. Cursor nhấp nháy thuần CSS.
- Ký hiệu trang trí (`$`, `→`, `✓`, 3 chấm title bar) `aria-hidden="true"`; ý nghĩa trạng thái có text thật đi kèm.
- Tương phản AA trên `#0b1120`; focus style rõ cho mọi link/nút; đọc tốt trên mobile (khung terminal co giãn, không scroll ngang).

## 6. Gói SEO

- Giữ: canonical + hreflang vi/en/x-default (đã có trong `Base.astro`).
- Thêm vào `<head>`: Open Graph (`og:title/description/image/url/type/locale` + alternate locale), Twitter card (`summary_large_image`), `theme-color`.
- `og:image`: PNG tĩnh 1200×630 phong cách terminal, mỗi ngôn ngữ một bản, tạo từ SVG trong repo và commit PNG; self-host.
- `public/robots.txt`: allow all + trỏ sitemap.
- `sitemap.xml`: sinh khi build bằng một endpoint Astro tĩnh (`src/pages/sitemap.xml.ts`) liệt kê 6 URL với `hreflang` alternates — không plugin.
- JSON-LD mỗi trang chủ: `SoftwareApplication` (name, OS, offers price 0 nếu đúng là miễn phí — xác nhận trong plan, url, inLanguage) + `WebSite`.
- Performance: font subset self-host + `font-display: swap`, JS < 5 KB, không CLS (khung terminal có kích thước ổn định), CSS inline theo mặc định Astro.

## 7. Testing (chạy trong `npm run build`, tức cả trong Docker build của deploy.yml)

Giữ toàn bộ test cũ. Thêm vào `tests/site.test.mjs`:

- `robots.txt` và `sitemap.xml` tồn tại; sitemap đủ đúng 6 URL với đúng host `https://shellx.pro`.
- Ảnh OG tồn tại và được tham chiếu đúng trên cả 2 trang chủ.
- Mỗi trang đúng một `<h1>`.
- JSON-LD parse được (JSON hợp lệ, `@type` đúng).
- **Không có `<script src>` hay `<link href>` trỏ ra origin ngoài `shellx.pro`** trên mọi trang dist — cưỡng chế cam kết privacy bằng CI.
- Trang chủ vẫn chứa đủ nội dung khi không JS (kiểm bằng chuỗi tĩnh trong dist HTML).

## 8. Ngoài phạm vi

- Không trang mới (`/security`, `/faq` riêng) — có thể mở rộng sau.
- Không terminal tương tác cho khách gõ (có thể làm easter egg sau).
- Không đổi nội dung pháp lý privacy/terms (chỉ đổi vỏ).
- Không đụng relay/agent/mobile, không đổi hạ tầng deploy.

## 9. Rủi ro và điểm cần xác nhận khi lập plan

- Font subset tiếng Việt cho JetBrains Mono: lấy woff2 subset từ nguồn chính thức (repo JetBrains Mono, OFL) — commit vào repo, ghi license `third_party` nếu quy ước repo yêu cầu.
- Giá sản phẩm cho JSON-LD `offers` (hiện app chưa thu phí?) — xác nhận với người dùng trước khi ghi "0".
- Copy marketing mới (features/security/FAQ) phải khớp sự thật kỹ thuật trong repo (Noise, argon2id, không log nội dung — đối chiếu privacy policy).
