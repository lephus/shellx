# ShellX desktop native (macOS + Windows): đặc tả thiết kế

- **Ngày:** 2026-10-18
- **Trạng thái:** đã brainstorm với người dùng ngày 18/10/2026. Một người review đã đọc với vai người sẽ làm; các câu hỏi của họ đã được trả lời (U14) hoặc được chốt ở §14 (C12–C17). Đang chờ người dùng duyệt. Mục §6 ghi các quyết định của người dùng, giữ nguyên lời họ nói. Mục §14 ghi các lựa chọn do người viết spec chốt. Mục §15 là phần để lại cho người làm.
- **Phạm vi:** app desktop ShellX viết lại bằng code native cho macOS và Windows, kèm relay v2 và trang xem link chia sẻ trên web. **Không gồm** app mobile native: đó là dự án riêng, sẽ brainstorm sau khi desktop xong.
- **Thay cho:** app desktop Flutter (`apps/desktop`, bản 1.0.0 đang phát hành). Các spec A1–A13 và V2-x vẫn là tài liệu tham khảo về hành vi, nhưng không ràng buộc bản native.
- **Bản phác đã duyệt:** `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html`. Bốn hướng ban đầu nằm ở `bon-huong-ban-dau.html` cùng thư mục, người dùng chọn hướng D. Hai file là fragment cho visual companion của brainstorming, nên mở bằng trình duyệt sẽ thiếu khung CSS ngoài, nhưng phần cửa sổ app vẫn hiện đúng.
- **Nguồn đã kiểm ngày 18/10/2026:**
  - repo `https://github.com/lephus/shellx-pro`, commit `d0b2cd7e` ngày 17/10/2026. Đây là bản sao nguyên vẹn của `manaflow-ai/cmux`, chưa có thay đổi nào của ShellX;
  - code ShellX tại `6ba1f0a3` (`main`);
  - `web/src/layouts/Base.astro` (bộ màu) và `web/public/favicon.svg` (logo);
  - file Figma coolicons `vaiWWRDJjP2mRdlOhHEzdh` (node `17102:2265`, 442 icon) và repo `krystonschwarze/coolicons` bản v4.1.

---

## 1. Ý định và lý do

Người dùng thấy app desktop Flutter "trải nghiệm kém" và thấy cmux (đã sao về thành `lephus/shellx-pro`) "tốt hơn nhiều". Khi được hỏi cmux tốt ở chỗ nào, họ trả lời "tất cả". Người dùng muốn:

1. ShellX có cảm giác và hiệu năng của một app native thật, ngang cmux: terminal vẽ bằng GPU, mở nhanh, gõ không trễ.
2. Giao diện "bứt phá hơn" cmux. Hướng được chọn là **"Mọi máy, một chỗ"**: sidebar gom phiên theo máy, chuyển một phiên sang điện thoại hoặc chia sẻ nó chỉ bằng một nút. cmux đã có phần phản chiếu workspace giữa các máy (`Sources/Devices`, `Hive`, `CmuxTerminalSharing`), nhưng phần đó chỉ chạy qua cloud của Manaflow. cmux cũng không gom sidebar theo máy, không chạy trên Windows, và không có link chia sẻ mở bằng trình duyệt. Ba điểm đó, cộng với relay tự host, là chất riêng của ShellX.
3. Desktop làm trước và chạy được trên **cả Mac lẫn Windows**. Sau đó mới làm mobile native cho iOS và Android "để hiệu suất đạt tối đa".

Người dùng chấp nhận hai cái giá: **ShellX trở thành mã nguồn mở theo GPL** (trả lời "có"), và **Mac với Windows dùng hai bộ giao diện riêng** ("làm hai lần nhưng đảm bảo hiệu suất mượt là tốt").

## 2. Mục tiêu và tiêu chí thành công

### 2.1 Mục tiêu

- **G1:** app ShellX cho macOS dựng trên code cmux, giữ toàn bộ tính năng của app Mac cmux, trừ các phần phụ thuộc máy chủ của Manaflow (§9).
- **G2:** app ShellX cho Windows có cùng bố cục, cùng hệ màu và cùng các khoảnh khắc chính như bản Mac, chạy native, không dùng Electron hay webview cho giao diện chính.
- **G3:** sidebar gom theo máy. Ngồi ở một máy ShellX có thể xem và điều khiển phiên trên máy ShellX khác trong cùng tài khoản, **khi app ShellX trên máy đó đang mở** (U14). VPS được thêm vào qua SSH.
- **G4:** có link chia sẻ phiên mở được bằng trình duyệt, chọn được quyền và hạn dùng. Có nút "Tiếp tục trên điện thoại", nút này hoạt động được cả trước khi có app mobile native.
- **G5:** có relay v2 với giao thức mới, mã hoá đầu cuối, chạy trên VPS hiện có.
- **G6:** cập nhật và bắt buộc cập nhật vẫn quản lý qua `admin.shellx.pro`, như bản Flutter đang làm.

### 2.2 Tiêu chí thành công (đo được)

1. **Hiệu năng trên Mac:** đo ShellX và cmux gốc (build từ commit fork) trên cùng một máy, cùng cấu hình Ghostty, theo năm chỉ số:
   - (a) mở app lạnh đến lúc có dấu nhắc lệnh gõ được;
   - (b) độ trễ từ lúc gõ phím đến lúc chữ hiện lên;
   - (c) thời gian `cat` một file 100 MB;
   - (d) RAM lúc rảnh với 1 cửa sổ có 4 pane;
   - (e) CPU lúc rảnh.

   ShellX **không được tệ hơn cmux quá 10%** ở bất kỳ chỉ số nào. Cách đo cụ thể để §15 quyết, nhưng phải ghi lại để chạy lại được trước mỗi bản phát hành.
2. **Hiệu năng trên Windows:** đo năm chỉ số (a)–(e) như trên, so với Windows Terminal bản stable mới nhất trên cùng máy. Ngưỡng là không tệ hơn quá 10%.
3. **Mượt:** cuộn terminal, mở hoặc đóng sidebar, chuyển phiên đều không rớt khung hình ở 60 Hz. Trên màn ProMotion phải đạt 120 Hz.
4. **Đổi phiên giữa các máy:** bấm vào một phiên của máy khác (máy đó đang mở ShellX) thì nội dung hiện lên trong ≤ 1 giây, khi hai máy và relay ở mạng thông thường tại Việt Nam.
5. **Chia sẻ:** người nhận mở link trên trình duyệt di động hoặc desktop thì thấy terminal trong ≤ 2 giây, không cần cài app, không cần tài khoản.
6. **Bảo mật:** relay, hoặc người chỉ có mật khẩu tài khoản mà chưa được máy đích chấp thuận, **không đọc được và không điều khiển được** terminal. Đây là nguyên tắc 4 của spec v1, nay giữ nguyên.
7. **Giao diện:** khớp bản phác hướng D: bố cục, bộ màu ở §7.4, icon coolicons, không có gradient trên các thành phần giao diện.

## 3. Không làm (non-goals)

- App mobile native iOS/Android: dự án riêng, làm sau.
- Tương thích với app điện thoại Flutter hiện tại. Người dùng đã nói "không cần". Hệ quả là từ khi desktop native ra mắt đến khi có app mobile native, điện thoại chỉ dùng được ShellX qua link trên trình duyệt.
- Tương thích với giao thức relay v1 hay với bản desktop Flutter.
- Các tính năng cmux phụ thuộc máy chủ Manaflow: máy ảo cloud (⌘Y, ⌘⇧Y), tài khoản cmux, relay và presence của họ, `coderouter`, billing (§9).
- Chia sẻ cửa sổ của các terminal khác (Terminal.app, iTerm2, VS Code, Cursor), tức phần `shellx-term` đang làm trong bản Flutter. Để đợt sau.
- Bản Linux.
- Dịch vụ chạy nền giữ phiên sống khi app đã thoát, và việc tự bật cùng máy (U14). Như cmux: thoát app thì các phiên trên máy đó đóng, và máy đó hiện "ngoại tuyến" với các máy khác.
- Thông báo đẩy tới điện thoại trong giai đoạn chỉ có trang xem trên trình duyệt (§7.2). Thông báo trên điện thoại đến cùng app mobile native.
- Trong **đợt phát hành Windows đầu tiên**: trình duyệt nhúng và Agent Chat. Cả hai có trong đợt Windows sau (§10).

## 4. Điều tuyệt đối tránh (anti-goals)

Những điều sau khiến dự án thất bại, kể cả khi app vẫn "chạy được":

- Chậm hơn cmux gốc trên Mac, hoặc trên Windows chậm hơn Windows Terminal, vượt ngưỡng ở §2.2.
- Giao diện chính dựng bằng webview hoặc Electron. Khung trình duyệt nhúng thì được dùng webview, vì bản chất nó là trình duyệt.
- Màu gây mỏi mắt: nút dùng gradient, màu chói, quầng sáng. Người dùng đã nói rõ: "các button không nên gradient colors, sẽ gây mỏi mắt".
- Relay đọc được terminal của người dùng.
- Ghi đè hoặc làm hỏng cấu hình Ghostty sẵn có của người dùng.
- Gửi dữ liệu người dùng về Manaflow hoặc bất kỳ bên thứ ba nào (§9).

## 5. Ràng buộc

- **Giấy phép.** App Mac, CLI, iOS và `cmux-tui` của cmux dùng **GPL-3.0-or-later**. Mọi bản ShellX phát hành có dùng code này phải công khai mã nguồn tương ứng theo GPL. Các thư mục sau dùng **BUSL-1.1** và **không được dùng cho production** khi chưa có giấy phép thương mại của Manaflow: `web/`, `workers/ci-artifacts/`, `workers/iroh-v2/`, `workers/presence/`, `services/iroh-relay-minter/`, `cmux-tui/relays/cloudflare-do/`. Relay v2, web và admin của ShellX **không được** lấy code từ các thư mục đó.
- **Hạ tầng.** Dùng VPS hiện có: Docker sau `nginx-proxy` và letsencrypt companion. Mọi thứ ShellX đặt trên VPS nằm trong **một thư mục** `~/phu/shellx`. Tên miền `shellx.pro`. Không dùng Cloudflare Workers (người dùng đã bỏ vì phải trả tiền).
- **Tài khoản Apple.** Team ID `W4RF3W4VTZ`, bản macOS bắt buộc ký và notarize. Bản Windows phát hành không ký cho tới khi người dùng có chứng chỉ.
- **Phát hành.** Giữ quy tắc người dùng đã chốt ngày 15/10: mỗi lần push lên `main` thì phát hành đúng phiên bản ghi trong file cấu hình, phiên bản do người dùng tự đặt. Không quay lại cách phát hành theo tag, không tự chọn số phiên bản.
- **Trang web.** Trang xem link chia sẻ phải tuân theo cam kết hiện có của shellx.pro: không tải tài nguyên từ bên thứ ba. Test origin-guard trong `web/tests` đang kiểm tra điều này.
- **Bộ gõ tiếng Việt.** Gõ Telex/VNI qua bộ gõ của hệ điều hành và các bộ gõ phổ biến (Unikey, EVKey, bộ gõ tiếng Việt có sẵn của macOS/Windows) phải dùng được trong terminal trên cả hai nền tảng.
- **Ngôn ngữ.** Giao diện có tiếng Việt và tiếng Anh. cmux hiện chỉ có `en` và `ja`.

## 6. Quyết định của người dùng (18/10/2026)

| # | Quyết định | Lời người dùng |
|---|---|---|
| U1 | Làm lại app bằng code native và lấy cmux (`lephus/shellx-pro`) làm nền | "làm lại ứng dụng bằng cách clone lại https://github.com/lephus/shellx-pro" |
| U2 | Giữ mọi điều làm nên cmux | "tất cả" |
| U3 | Làm desktop trước, chạy cả Mac và Windows. Mobile làm sau, native cho iOS và Android | "hiện tại chúng ta sẽ làm desktop app trước, và desktop app của chúng ta cần chạy đc cả mac và win; sau đó chúng ta sẽ dựng mobile app cho cả android và ios (viết native app luôn, để hiệu suất đạt tối đa)" |
| U4 | Chấp nhận ShellX thành mã nguồn mở theo GPL | "có" |
| U5 | Mac fork cmux bằng Swift; Windows dựng trên lõi Rust `cmux-tui` với giao diện native. Chấp nhận làm UI hai lần | "đồng ý, làm hai lần nhưng đảm bảo hiệu suất mượt là tốt" |
| U6 | Chọn hướng giao diện D "Mọi máy, một chỗ" | "Chọn D" |
| U7 | Icon dùng bộ coolicons | "các icon trong ứng dụng nên dùng bộ icon https://www.figma.com/design/vaiWWRDJjP2mRdlOhHEzdh/coolicons-…" |
| U8 | Bản phác chi tiết hướng D (§7) đúng ý | "đúng" |
| U9 | Không cần tương thích với app điện thoại Flutter | "không cần" |
| U10 | Phạm vi bản đầu như §8–§9 | "chuẩn" |
| U11 | Logo và màu theo shellx.pro | "cập nhật lại logo mà màu sắc app giống với màu đang dùng ở https://shellx.pro/" |
| U12 | Màu dịu hơn, màu chủ đạo `#60a5fa`, nút không dùng gradient | "làm màu sắc dịu hơn tý, màu chủ đạo là 60a5fa và các button không nên gradiun colors, sẽ gây mỏi mắt" |
| U13 | Trạng thái "đang chạy" dùng màu vàng | "đang chạy nên là màu vàng" |
| U14 | Một máy chỉ điều khiển được từ xa khi app ShellX trên máy đó đang mở. Không có dịch vụ chạy nền, giống cmux | "Như cmux. Chỉ điều khiển được khi app đang mở." |

## 7. Thiết kế trải nghiệm (hướng D)

Bản phác: `docs/superpowers/design/2026-10-18-native-desktop/huong-d-mockup.html`. Mục này mô tả bản phác bằng lời. Hai nguồn mà khác nhau thì bản phác là chuẩn về bố cục, còn mục này là chuẩn về hành vi.

### 7.1 Cửa sổ chính

- **Thanh tiêu đề** gồm, theo thứ tự:
  - nút cửa sổ: trái trên macOS, phải trên Windows;
  - nút ẩn/hiện sidebar (`Window_Sidebar`);
  - ô tìm kiếm ở giữa, "Tìm phiên, máy, lệnh… ⌘K". Ô này là command palette của cmux, mở rộng thêm để tìm cả máy và phiên trên máy khác;
  - chuông thông báo (`Bell_Ring`), có chấm số màu chủ đạo, gom thông báo từ **mọi máy**;
  - nút cài đặt (`Settings`).
- **Sidebar** (khoảng 290 px), từ trên xuống:
  1. Logo ShellX và chữ "ShellX".
  2. Tiêu đề "MÁY CỦA BẠN", kèm nút `Add_Plus` để thêm máy (ghép cặp với máy ShellX khác, hoặc thêm VPS qua SSH).
  3. Mỗi máy là một nhóm. Đầu nhóm gồm icon loại máy (`Laptop`/`Desktop` cho máy tính, `Data` cho VPS), tên máy, ghi chú ("máy này", "văn phòng", "SSH") và chấm trạng thái online. Máy đang chạy app luôn đứng đầu. Máy nào đã tắt ShellX thì hiện mờ, ghi "ngoại tuyến · lần cuối HH:MM" và không có phiên bên dưới (U14).
  4. Mỗi phiên dưới máy hiển thị:
     - icon `Terminal`;
     - tên phiên;
     - nhánh git · thư mục · cổng đang mở;
     - câu cuối agent nói, nếu phiên đang chờ bạn;
     - bên phải: nhãn trạng thái, icon `Mobile` khi điện thoại đang xem, icon `Users` kèm số người khi đang chia sẻ.
  5. Mục "THIẾT BỊ ĐANG KẾT NỐI": điện thoại hoặc trình duyệt đang xem phiên nào.
  6. Chân sidebar: `Shield_Check` "Mã hoá đầu cuối · relay.shellx.pro".
- **Khu vực chính:**
  - Thanh phiên gồm icon `Terminal`, "tên phiên › máy · thư mục", chip nhánh git, nút chính "Tiếp tục trên điện thoại" (`Mobile`), nút "Chia sẻ" (`Link`) và nút `More_Horizontal`.
  - Dải hiện diện ngay dưới, cho biết ai đang xem phiên này (điện thoại, người được chia sẻ).
  - Các pane terminal chia khung như cmux. Pane có agent đang chờ bạn thì có viền màu chủ đạo.
- **Thông báo nổi** ở góc dưới phải cho sự kiện từ máy khác, ví dụ "build-win đã xong · PC Windows · văn phòng", kèm nút "Xem". Bấm "Xem" thì chuyển sang phiên đó.

### 7.2 Khoảnh khắc 1: "Tiếp tục trên điện thoại"

- Popover hiện mã QR dùng một lần, hết hạn sau 2 phút, kèm dòng "Quét bằng app ShellX". Có thêm nút "Gửi tới máy đã ghép cặp".
- Phiên **vẫn chạy trên máy tính**. Điện thoại chỉ là màn hình thứ hai: xem được và gõ được. Thoát ShellX trên máy tính thì điện thoại bị ngắt (U14).
- **Trước khi có app mobile native:**
  - QR mở trang xem phiên trên trình duyệt điện thoại. Đây là cùng trang với link chia sẻ ở §7.3, quyền "được gõ".
  - Trang trên trình duyệt **không gửi thông báo đẩy**. Lý do: Web Push đi qua máy chủ push của Apple/Google, trên iOS còn bắt người dùng phải thêm trang vào màn hình chính. Đây là lựa chọn của người viết spec (C14).
  - Nút "Gửi tới máy đã ghép cặp" ẩn cho tới khi có app mobile.
- **Khi đã có app mobile native:** QR và nút gửi sẽ mở app, và app nhận được thông báo khi agent cần bạn. Phần này thuộc dự án mobile.

### 7.3 Khoảnh khắc 2: "Chia sẻ phiên"

- Popover gồm:
  - link (ví dụ `shellx.pro/s/k7f2-9qd1`) và nút "Sao chép";
  - quyền: **Chỉ xem** (mặc định) / **Được gõ**;
  - hạn dùng: **15 phút** / **1 giờ** (mặc định) / **Khi tôi tắt**;
  - danh sách "Đang xem".
- Người nhận mở link trên trình duyệt, không cần cài app, không cần tài khoản.
- Chủ phiên thu hồi được link bất cứ lúc nào. Thu hồi thì mọi người đang xem bị ngắt ngay. Thoát ShellX trên máy chủ phiên cũng ngắt mọi người đang xem. Link vẫn còn hạn thì mở lại app là xem tiếp được.
- **Thứ được chia sẻ là cả phiên** (C12), gồm mọi pane terminal của phiên đó:
  - trên trình duyệt desktop, người xem thấy đúng bố cục chia khung;
  - trên điện thoại, người xem thấy từng pane một, kèm thanh chuyển pane;
  - pane trình duyệt nhúng và pane Agent Chat không chia sẻ, chỉ hiện một ô giữ chỗ.

### 7.4 Hệ thị giác

**Bộ màu** (token dùng chung cho Mac, Windows và trang xem link):

| Token | Giá trị | Dùng cho |
|---|---|---|
| `bg` | `#0b0716` | nền cửa sổ, nền terminal mặc định (giống nền shellx.pro) |
| `panel` | `#100b1d` | sidebar, thanh tiêu đề |
| `raise` | `#171128` | khối, popover, thông báo nổi |
| `line` | `#211a37` | đường chia mảnh |
| `border` | `#2a2145` | viền nút, ô nhập (giống `--border` của web) |
| `text` | `#cdc7e0` | chữ thường |
| `text-hi` | `#e6e2f2` | tiêu đề, tên phiên |
| `muted` | `#8a83a6` | chữ phụ, metadata |
| `primary` | `#60a5fa` | **màu chủ đạo**: dấu nhắc lệnh, điểm nhấn, trạng thái "chờ bạn" |
| `primary-soft` | `rgba(96,165,250,.12)` | nền nút chính, nền nhãn "chờ bạn" |
| `primary-line` | `rgba(96,165,250,.45)` | viền nút chính, viền pane hoặc phiên đang chờ |
| `primary-text` | `#93c5fd` | chữ trên nền `primary-soft` |
| `running` | `#e8c468` | trạng thái "đang chạy" (vàng dịu) |
| `done` | `#6fd49a` | trạng thái "xong", chấm online |
| `error` | `#e88a8a` | trạng thái "lỗi" |

**Quy tắc:**

- **Không dùng gradient, quầng sáng hay bóng màu** trên mọi thành phần giao diện. Logo là ngoại lệ duy nhất, vì nó giữ nguyên gradient của chính nó.
- **Nút chính:** nền `primary-soft`, viền 1 px `primary-line`, chữ `primary-text`. **Nút phụ:** nền `raise`, viền `border`, chữ `text`. Cả hai đều là màu đặc.
- **Nhãn trạng thái:** nền là màu trạng thái với độ đậm khoảng 12%, chữ là màu trạng thái.

| Trạng thái | Nhãn | Màu |
|---|---|---|
| Chờ bạn | "chờ bạn" | `primary`, kèm viền ở phiên trong sidebar và ở pane |
| Đang chạy | "chạy" | `running` |
| Xong | "xong" | `done` |
| Lỗi | "lỗi" | `error` |
| Rảnh | không có nhãn | `muted` |

- **Chủ đề màu:** bản đầu chỉ có giao diện tối. Đây là lựa chọn của người viết spec, xem §14.
- **Chữ:** terminal mặc định dùng JetBrains Mono. Nếu người dùng có cấu hình Ghostty thì cấu hình đó thắng. Tiêu đề lớn và wordmark dùng Space Grotesk, như shellx.pro. Chữ giao diện dùng font hệ thống (SF trên Mac, Segoe UI Variable trên Windows).
- **Icon:** bộ **coolicons v4.1**, gồm 442 icon, nét 2 px trên lưới 24 px, tô bằng `currentColor`.
  - Nguồn chuẩn: file Figma người dùng đưa, đã kiểm có đủ 442 icon. Bản tải được nằm ở repo `krystonschwarze/coolicons` bản v4.1.
  - Giấy phép **CC BY 4.0**: phải ghi "coolicons by Kryston Schwarze" trong màn hình Giới thiệu.
  - 20 icon bản phác dùng đã lưu ở `docs/superpowers/design/2026-10-18-native-desktop/coolicons/`.
  - Mọi icon trong app, kể cả icon cmux đang dùng, đều đổi sang coolicons. Chỗ nào coolicons không có icon phù hợp thì người làm chọn icon gần nhất trong bộ và ghi lại.
- **Logo:** `web/public/favicon.svg`: nền tím đậm, dấu ">" màu mint (máy tính), dấu "<" màu trắng tím (điện thoại), kèm con trỏ. Icon app cho macOS và Windows dựng từ file SVG này.
- **Bảng màu terminal mặc định:** nền `bg`, con trỏ và dấu nhắc lệnh `primary`. 16 màu ANSI do người làm chỉnh cho hợp bộ màu. Theme Ghostty của người dùng luôn thắng.

## 8. Kiến trúc

### 8.1 Tổng thể

```
 ┌────────────── macOS ──────────────┐   ┌───────────── Windows ─────────────┐
 │ ShellX.app (Swift/AppKit, fork    │   │ ShellX.exe (Rust, UI native vẽ    │
 │ cmux) + libghostty (Metal)        │   │ bằng GPU) + lõi cmux-tui          │
 │   └─ remote: daemon cmux-remote   │   │   └─ remote: daemon cmux-remote   │
 └───────────────┬───────────────────┘   └───────────────┬───────────────────┘
                 │  cùng MỘT giao thức (remote cmux-tui, D-W0-1), trong kênh  │
                 │  Noise mã hoá đầu cuối, chuyển qua cmux-relay tự host      │
                 └───────────────┬───────────────────────┘
                     ┌───────────▼────────────┐        ┌───────────────────────┐
                     │ relay v2 (VPS,         │◄──────►│ Trang xem link chia sẻ │
                     │ ~/phu/shellx)          │        │ (shellx.pro/s/…)       │
                     └────────────────────────┘        └───────────────────────┘
```

### 8.2 macOS: fork cmux

- **Repo:** `lephus/shellx-pro`, công khai theo GPL.
- **Giữ kết nối với upstream:** giữ remote tới `manaflow-ai/cmux` để định kỳ kéo bản sửa về. Code riêng của ShellX tách thành thư mục hoặc module Swift riêng, càng ít đụng file của cmux càng tốt. Riêng phần sidebar gom theo máy chắc chắn sẽ xung đột với upstream, và cái giá đó đã được chấp nhận.
- **Giữ của cmux:**
  - terminal libghostty, chia khung (bonsplit), tab dọc;
  - vòng sáng thông báo và bảng thông báo;
  - trình duyệt nhúng và API điều khiển trình duyệt;
  - Agent Chat;
  - CLI và socket API;
  - workspace SSH;
  - Claude Code Teams;
  - custom commands, command palette;
  - đọc cấu hình Ghostty sẵn có;
  - phím tắt;
  - khôi phục phiên, theo đúng cách cmux làm: chỉ khôi phục bố cục, không giữ shell sống qua lần thoát app (U14).
- **Giữ, nhưng chuyển từ cloud Manaflow sang hạ tầng ShellX** (C16). Người review đã kiểm thấy cmux có sẵn:
  - phản chiếu workspace của máy khác (`Sources/Devices/*`: `DeviceTerminalMirrorSession`, `DeviceWorkspaceProjection`; `Sources/Hive`);
  - thống nhất một kích thước terminal giữa máy chủ phiên, điện thoại và các máy khác (`Packages/macOS/CmuxTerminalSharing`);
  - làm máy chủ cho điện thoại (`Sources/Mobile`, `CmuxMobileHost`);
  - presence (`CmuxWorkspacePresence`);
  - danh sách máy dùng giao thức remote của `cmux-tui` (`SurfaceCatalog`, `Sources/RemoteTui`).

  Hiện các phần này chạy qua iroh của Manaflow với đăng nhập Stack Auth, và chỉ bật khi có cờ cloud (`DevicesFeature.isAvailable` cần `CloudMachinesFeature.isEnabled`). ShellX giữ phần giao diện và logic, chỉ thay đường truyền và đăng nhập (§8.5). Đây là phần nền của sidebar gom theo máy.

  **Thực tế đã kiểm (bổ sung 18/10, sau khi đọc code):**
  - Máy Mac chia sẻ phiên **của chính nó** (`Devices`, `MobileHost`) bằng **mobile RPC protocol** của `CMUXMobileCore`. Các tin gồm `terminal.bytes`, `mobile.terminal.input`, `mobile.sync.*`. Giao thức này chạy trên `CmxByteTransport`/`CmxByteTransportFactory`, với các loại đường truyền iroh, tailscale và websocket. App iOS của cmux là client của giao thức này.
  - Bản Mac chỉ nói **giao thức remote của `cmux-tui`** khi làm **client** (`RemoteTui` chạy `cmux-tui remote connect … --headless`). Máy Mac không phục vụ phiên libghostty của nó qua giao thức `cmux-tui`.
- **Đổi thương hiệu:**
  - tên app "ShellX", bundle id `pro.shellx.desktop` (giữ id của bản Flutter);
  - icon app, bộ màu, coolicons, thêm bản dịch tiếng Việt;
  - lệnh CLI `cmux` đổi thành `shellx`. Tên lệnh này đã dùng ở spec A7 của bản Flutter.
- **Thay phần dính tới Manaflow:** xem §9.

### 8.3 Windows: Rust trên lõi `cmux-tui`

- **Hiện trạng của cmux:**
  - `cmux-tui` (Rust) đã có mô hình máy → phiên → workspace → pane → tab;
  - đã có các crate `cmux-pty`, `cmux-remote`, `ghostty-vt`/`ghostty-vt-sys` (build `libghostty-vt.a` từ submodule `ghostty` bằng Zig 0.16.0);
  - tài liệu ghi chỉ hỗ trợ macOS và Linux, "Windows support via ConPTY is planned for phase 2".
- **ShellX tự làm phần Windows:**
  - PTY qua ConPTY;
  - build `libghostty-vt` cho Windows;
  - giao diện native vẽ bằng GPU theo §7.
- **Kết nối với máy khác:** bản Windows phải làm được cả máy chủ phiên lẫn client, bằng **cùng giao thức với bản Mac** (C16). **Đã chốt ngày 19/10 (D-W0-1, ledger): giao thức remote của `cmux-tui`.** Bản Mac nhúng daemon `cmux-remote` và chiếu các terminal libghostty sang một "PTY ảo" trong `cmux-tui-core` (bước thử bridge M-B1 đã chạy thật: client `cmux-tui` gốc qua `cmux-relay` xem và gõ được vào terminal của app Mac, tạo được tab mới từ xa). Bản Windows port daemon đó (ConPTY đã có trong `cmux-pty`). Hai ứng viên đã cân nhắc:
  - **mobile RPC protocol:** Mac đã làm máy chủ, iOS đã làm client. Bản Windows phải viết bằng Rust cả máy chủ lẫn client;
  - **giao thức remote của `cmux-tui`:** cần port daemon `cmux-remote` sang Windows. Hiện daemon này chỉ chạy trên Unix: `crates/cmux-tui/src/main.rs:47-64` chặn lệnh remote trên Windows, và `docs/remote.md:260` ghi rõ "PTYs are explicitly unavailable on non-Unix daemons". Bản Mac cũng phải thêm phần phục vụ phiên qua giao thức này.
- **Ràng buộc cho bộ công cụ giao diện:**
  - native, vẽ bằng GPU (DirectX hoặc Vulkan), không webview cho giao diện chính;
  - chữ sắc nét kiểu DirectWrite, hỗ trợ màn hình DPI cao;
  - bộ gõ tiếng Việt chạy được trong terminal;
  - đọc được bằng trình đọc màn hình ở mức cơ bản;
  - giấy phép tương thích GPL.

  Việc chọn bộ công cụ cụ thể để §15 quyết sau bước thử ở §13. Ví dụ, GPUI của Zed có giấy phép Apache-2.0 và chạy được trên Windows.
- **Đợt Windows sau:** trình duyệt nhúng dùng WebView2.

### 8.4 `shellx-core`: logic dùng chung viết một lần

Đây là lựa chọn của người viết spec (C3). Giao thức giữa các máy đã có sẵn trong cmux (§8.2, §8.3), nên `shellx-core` chỉ chứa những phần **riêng của ShellX** mà cả hai nền tảng đều cần, viết **một lần bằng Rust**:

- client tài khoản ShellX (đăng nhập, danh sách thiết bị);
- ghép cặp và việc máy đích chấp thuận (§8.5);
- tạo, thu hồi và quản lý link chia sẻ;
- kiểm tra cập nhật và bắt buộc cập nhật.

Bản Windows gọi thư viện này trực tiếp. Bản Mac gọi qua C ABI; cmux đã có tiền lệ dùng Rust qua FFI (`Native/CommandPaletteNucleoFFI`). Nhờ vậy, "làm hai lần" chỉ áp dụng cho phần giao diện.

**Giấy phép:** desktop được dùng lại code cmux thoải mái, vì người dùng đã chấp nhận GPL (U4). Có hai chỗ cần ghi nhớ:

- `cmux-tui/Cargo.toml` khai `license = "MIT"`, nhưng `LICENSE` ở gốc repo ghi `cmux-tui` theo giấy phép "mà file này hoặc thông báo riêng của chúng ghi". Hai chỗ này mâu thuẫn. Chưa làm rõ được thì coi `cmux-tui` là GPL.
- App iOS sau này nếu chứa code GPL của Manaflow thì có rủi ro xung đột với điều khoản App Store, và chỉ Manaflow mới miễn được. Đây là rủi ro mở cho **dự án mobile** quyết, không chặn desktop.

### 8.5 Relay v2 và giao thức

- **Dịch vụ mới** chạy cạnh relay v1 trong `~/phu/shellx`, sau `nginx-proxy`. Relay v1 vẫn chạy để phục vụ app điện thoại Flutter cho tới khi người dùng quyết định tắt.
- **Nền của relay v2** (C16):
  - **phần chuyển gói** dùng bản tự host của `cmux-tui/crates/cmux-relay`. Đã đọc code ngày 18/10, relay này:
    - là server WebSocket (axum), cần TLS ở reverse proxy phía trước, tức `nginx-proxy`;
    - chỉ chuyển khung nhị phân mờ ("Relays only see slot identifiers, opaque circuit identifiers, timing, lane count, endpoint addresses, and ciphertext sizes", `spec/remote-daemon.md`);
    - xác thực bằng ticket HMAC-SHA256 sống tối đa 5 phút;
    - mã hoá đầu cuối bằng `Noise_XX_25519_ChaChaPoly_BLAKE2s` ở `cmux-remote/src/crypto.rs`;
    - đã có luồng mời → máy đích duyệt (`remote enroll create`, `identity.rs approve`), khớp nguyên tắc 2 bên dưới;
  - **API của ShellX:** tài khoản, thiết bị, chấp thuận, link chia sẻ, `/v1/version`. API này **cấp ticket** cho `cmux-relay` sau khi người dùng đăng nhập;
  - giao thức chạy trong kênh Noise là giao thức remote của `cmux-tui` (D-W0-1, chốt 19/10). Mac và Windows dùng **cùng một** giao thức.
- **Tài khoản:** dùng lại tài khoản hiện có (email + mật khẩu, argon2id, các giới hạn tần suất của spec v1 §5.2), để người dùng không phải đăng ký lại. Đây là lựa chọn của người viết spec, xem §14. Thiết bị và ghép cặp thì làm mới, vì không cần tương thích.
- **Nguyên tắc bảo mật, bắt buộc:**
  1. Relay chỉ chuyển gói tin đã mã hoá giữa các thiết bị trong cùng tài khoản, không đọc được nội dung terminal.
  2. Có mật khẩu tài khoản thôi là chưa đủ. Một thiết bị mới chỉ xem hoặc điều khiển được một máy khi **máy đó chấp thuận tại chỗ**. Với điện thoại, đó là quét QR như v1. Với máy tính, cách làm để §15 quyết, ví dụ mã ngắn gõ tay hoặc hộp xác nhận trên máy đích.
  3. Với link chia sẻ, khoá giải mã không bao giờ đi qua máy chủ. Ví dụ: đặt khoá trong phần `#…` của URL. Cách làm cụ thể để §15 quyết.
- **Không lấy code BUSL** của cmux (§5). Các crate trong `cmux-tui/crates` (`cmux-remote`, `cmux-relay`, `cmux-remote-protocol`) không nằm trong danh sách BUSL, nên được dùng lại. Lưu ý: nếu relay dùng code GPL **và** được phân phối cho người khác thì relay cũng phải theo GPL. Chỉ chạy trên VPS của mình thì không tính là phân phối.
- **Trang xem link chia sẻ** được phục vụ cho trình duyệt người dùng, tức là có phân phối. Vì vậy trang này chỉ dùng code của ShellX và thư viện có giấy phép dễ dãi (MIT, Apache…), **hoặc** mã nguồn của nó nằm trong repo công khai `lephus/shellx-pro` theo GPL (C17).

### 8.6 Máy ở xa trong sidebar

- **Máy ShellX khác cùng tài khoản**, sau khi được chấp thuận (§8.5) và khi app trên máy đó đang mở (U14): hiện như một nhóm trong sidebar.
  - Có thể mở, xem, gõ và chia khung với phiên của máy đó như phiên tại chỗ.
  - Chia khung một phiên ở xa thì shell mới chạy **trên máy chủ phiên** và hiện cả trong cửa sổ của máy đó, vì đó là cùng một phiên (C12).
  - Thông báo của máy đó đổ về chuông chung.
- **VPS:** thêm qua SSH như workspace SSH của cmux (`cmux ssh` đổi thành `shellx ssh`). Người dùng không phải cài gì bằng tay. Hai điểm cụ thể (C13):
  - **VPS thuộc về máy đã thêm nó.** Cấu hình SSH và khoá nằm trên máy đó, không đồng bộ qua tài khoản. Ở bản đầu, máy khác trong tài khoản không thấy nhóm VPS này.
  - **ShellX được tự cài helper lên VPS** như cmux đang làm (`daemon/remote`, `WorkspaceRemoteDaemonManifest` tải `cmuxd-remote`). ShellX tự build, ký và host các bản helper (Linux, macOS) trên `download.shellx.pro`, đổi tên theo ShellX, và không tải gì từ máy chủ Manaflow.
- **Thiết bị đang xem** (điện thoại hoặc trình duyệt) không phải "máy" và không có phiên riêng. Chúng chỉ hiện ở mục "Thiết bị đang kết nối".

### 8.7 Trang xem link chia sẻ

- Phục vụ tại `shellx.pro/s/<id>`. Có thể là một phần của site Astro hiện có, hoặc một ứng dụng riêng cùng tên miền; người làm chọn.
- Dùng bộ màu §7.4.
- Bộ vẽ terminal trên trình duyệt do người làm chọn, nhưng phải tự host, theo cam kết không bên thứ ba ở §5.
- Chạy được trên Safari iOS và Chrome Android, có bàn phím ảo khi quyền là "Được gõ".

## 9. Thay phần phụ thuộc Manaflow

Các phần sau trong app Mac của cmux phải **bỏ hoặc trỏ sang hạ tầng ShellX**. Danh sách này ghi những gì đã thấy khi kiểm code; người làm rà soát đầy đủ trước khi phát hành.

| Phần của cmux | Cách xử lý |
|---|---|
| Sparkle `SUFeedURL` = `github.com/manaflow-ai/cmux/releases/.../appcast.xml` | Đổi sang appcast trên `download.shellx.pro`, kết hợp với bắt buộc cập nhật qua `/v1/version` (`min_agent`) như bản Flutter |
| `https://cmux.com/api/client-config` | Bỏ, hoặc thay bằng cấu hình do relay v2 phục vụ nếu cần |
| Đăng nhập Stack Auth, tài khoản cmux, presence worker, relay iroh của Manaflow | Thay bằng tài khoản ShellX và relay v2 (§8.5) |
| Máy ảo cloud (⌘Y, ⌘⇧Y, `CloudWelcome`, `coderouter`), billing, huy hiệu Pro | Bỏ |
| Telemetry Sentry và PostHog | Bỏ hẳn, không thay bằng dịch vụ bên thứ ba nào (§14) |
| Link tài liệu `cmux.com/docs/...` | Trỏ về tài liệu trên shellx.pro, hoặc ẩn nếu chưa có trang tương ứng |
| Tải `cmuxd-remote` và lệnh `cmux` lên máy SSH | Tải bản helper của ShellX từ `download.shellx.pro` (§8.6) |
| Phản chiếu thiết bị, Hive, presence, máy chủ cho điện thoại chạy qua iroh của Manaflow và cờ cloud | Giữ phần giao diện và logic, chuyển đường truyền sang relay v2 và đăng nhập sang tài khoản ShellX (§8.2, §8.5) |
| Ghép cặp và relay của app iOS cmux | Ngoài phạm vi; dự án mobile sẽ quyết |

## 10. Lộ trình theo đợt

| Đợt | Nội dung | Phát hành |
|---|---|---|
| 0 | Các bước thử ở §13. Đo mốc hiệu năng của cmux gốc và Windows Terminal. | Không |
| 1 | **Mac chạy tại chỗ:**<br>• fork, đổi thương hiệu, áp bộ màu §7.4, coolicons, tiếng Việt;<br>• bỏ phần phụ thuộc Manaflow (§9);<br>• sidebar gom theo máy, lúc này chỉ có nhóm "máy này" và VPS qua SSH;<br>• đạt tiêu chí hiệu năng §2.2 mục 1. | Bản thử nội bộ |
| 2 | **Song song với đợt 1:**<br>• relay v2 và `shellx-core`: tài khoản, ghép cặp, máy ở xa;<br>• link chia sẻ và trang xem;<br>• "Tiếp tục trên điện thoại" qua trình duyệt. | Không |
| 3 | **ShellX Mac 2.0.0 phát hành công khai.** Trước đó phát hành Flutter 1.0.1 (§11). Sau đó bắt người dùng Flutter trên macOS 14+ cập nhật sang bản native. | Có |
| 4 | **Windows đợt đầu:**<br>• terminal, chia khung, sidebar gom theo máy;<br>• thông báo, ghép cặp, máy ở xa;<br>• chia sẻ, "Tiếp tục trên điện thoại";<br>• cập nhật. | Có |
| 5 | **Windows đợt sau:** trình duyệt nhúng (WebView2), Agent Chat và các tính năng còn lại để ngang bản Mac. | Có |
| Sau | Dự án riêng: app mobile native iOS + Android, chia sẻ cửa sổ của terminal khác. | — |

## 11. Phát hành, cập nhật, chuyển người dùng cũ

- **Phiên bản:** bản native bắt đầu từ **2.0.0**. Bản Flutter đang là 1.0.0.
- **Mac:**
  - ký bằng Developer ID của team `W4RF3W4VTZ` và notarize;
  - cập nhật qua Sparkle với appcast trên `download.shellx.pro`;
  - bắt buộc cập nhật qua `/v1/version`, admin quản lý `min_agent`.
- **Windows:**
  - bộ cài (Inno Setup như hiện tại, hoặc công cụ khác do người làm chọn), chưa ký;
  - cùng cơ chế kiểm tra và bắt buộc cập nhật như Mac.
- **Pipeline phát hành:**
  - Theo quy tắc ở §5: push `main` thì phát hành phiên bản ghi trong file cấu hình.
  - Pipeline mới nằm ở repo `lephus/shellx-pro`. Repo này công khai, nên GitHub Actions không tính phút như repo `shellx` riêng tư.
  - Secret ký app nằm trong GitHub Environment. Không bao giờ hỏi giá trị secret trong chat.
- **Yêu cầu hệ điều hành:** bản Mac native cần **macOS 14 trở lên**, vì cmux đặt `MACOSX_DEPLOYMENT_TARGET = 14.0`. Bản Flutter hiện chạy từ macOS 12.
- **Chuyển người dùng bản Flutter** (C15):
  - **Vướng mắc:** hiện `/v1/version` không yêu cầu đăng nhập, và app Flutter chỉ gửi `X-ShellX-Version` (`packages/shellx_core/lib/src/api/shellx_api.dart`). Relay không phân biệt được Mac với Windows, cũng không biết bản macOS. Nâng `min_agent` lúc này sẽ khoá cả người dùng macOS 12–13 lẫn Windows.
  - **Cách xử lý:** trước khi ra bản Mac 2.0.0, phát hành **một bản Flutter cuối cùng (1.0.1)**. Bản này chỉ thêm việc gửi nền tảng và phiên bản hệ điều hành. Relay đọc thông tin đó và đặt mức tối thiểu riêng cho từng nền tảng.
  - **Khi bản Mac 2.0.0 ra mắt:** chỉ người dùng Flutter trên macOS 14 trở lên mới thấy "Cần cập nhật" và được trỏ tới bộ cài native. Họ đăng nhập bằng tài khoản cũ và ghép cặp lại một lần.
  - Người dùng macOS 12–13 vẫn dùng bản Flutter 1.0.1, không nhận cập nhật nữa.
  - Người dùng Windows bản Flutter không bị bắt cập nhật cho tới khi bản Windows native ra mắt (đợt 4).
- **Code Flutter** (`apps/desktop`) đóng băng: không thêm tính năng mới sau khi bản native ra mắt. Ngoại lệ duy nhất là bản 1.0.1 nói trên. Gỡ khỏi repo khi nào thì người dùng quyết sau.

## 12. Giấy phép và ghi công

- `lephus/shellx-pro` giữ `LICENSE` của cmux và các file `THIRD_PARTY_LICENSES`. Mỗi bản phát hành kèm đường dẫn tới mã nguồn tương ứng.
- Màn hình Giới thiệu ghi công cmux/Manaflow (GPL-3.0-or-later), Ghostty, coolicons của Kryston Schwarze (CC BY 4.0) và các thư viện bên thứ ba còn lại.
- Chính sách quyền riêng tư và điều khoản trên shellx.pro phải sửa lại để phản ánh: mã nguồn mở, relay v2, link chia sẻ, không telemetry.

## 13. Rủi ro và bước thử sớm (đợt 0)

| Rủi ro | Mức | Bước thử | Nếu không đạt |
|---|---|---|---|
| `libghostty-vt` không build hoặc chạy được trên Windows bằng Zig | Cao | Build `ghostty-vt-sys` trên `windows-latest` và chạy test VT cơ bản | Dùng `alacritty_terminal` (Apache-2.0) làm bộ xử lý VT cho bản Windows |
| Bộ công cụ giao diện Windows không đáp ứng bộ gõ tiếng Việt, DPI cao hoặc độ trễ | Cao | Dựng cửa sổ terminal tối thiểu: gõ Telex qua Unikey/EVKey và bộ gõ có sẵn, đo độ trễ phím | Thử bộ công cụ khác, hoặc tự viết lớp vẽ bằng Direct2D/DirectWrite |
| Fork cmux khó build, ký hoặc notarize dưới team ShellX | Trung bình | Build, ký, notarize một bản chỉ đổi bundle id | Rà các entitlement và helper (`cmux-helper`, `ComputerUseHelper`, `TunnelExtension`); bỏ phần nào không cần |
| Kéo bản sửa từ upstream tốn công vì xung đột | Trung bình | Thử kéo về sau khi xong đợt 1 và ghi số file xung đột | Giãn chu kỳ kéo, hoặc chỉ cherry-pick bản sửa lỗi |
| Hiệu năng Windows kém xa Windows Terminal | Trung bình | Đo trong bước thử bộ công cụ giao diện | Điều chỉnh kiến trúc vẽ trước khi làm tiếp đợt 4 |
| `cmux-relay` tự host thực tế không giữ được bản rõ ngoài relay (đọc code thì đạt, nhưng chưa chạy thử), hoặc không gắn được ticket với tài khoản ShellX | Trung bình | Chạy `cmux-relay` cục bộ, nối hai đầu Noise qua nó với một chuỗi đánh dấu, kiểm tra chuỗi đó không bao giờ xuất hiện trong dữ liệu relay nhận | Iroh tự host, hoặc tự viết relay chuyển khung mờ |
| **Chọn giao thức chung cho Mac và Windows** (C16): mobile RPC protocol hay giao thức remote của `cmux-tui` | Cao | Ước lượng và dựng thử cả hai: (a) mobile RPC giữa hai máy Mac qua `CmxByteTransport` websocket → kênh Noise → `cmux-relay`, không dùng iroh hay Stack Auth; (b) `cmux-remote` daemon trên Windows, xem phải port những gì. Chọn theo bốn tiêu chí: công làm máy chủ phiên trên Windows, Mac phải thêm gì để làm máy chủ, client iOS/Android sau này dùng lại được bao nhiêu, và rủi ro khi kéo bản sửa từ upstream | Bước thử này phải chốt trước khi viết kế hoạch đợt 2 và đợt 4. **Đã chốt 19/10: (b)**, xem D-W0-1 trong ledger |
| Phần phản chiếu thiết bị của Mac (`Devices`, `Hive`) gắn chặt với iroh và Stack Auth (grant do broker ký, presence qua WebSocket xác thực bằng Stack), khó đổi đường truyền | Trung bình | Chính là bước (a) ở dòng trên | Chỉ giữ phần giao diện (`DeviceWorkspaceProjection`…), viết lại phần kết nối |

## 14. Lựa chọn của người viết spec

Người dùng có thể đổi bất kỳ mục nào. Mỗi mục ghi kèm cái giá nếu chọn sai.

| # | Lựa chọn | Cái giá nếu sai |
|---|---|---|
| C1 | Màu trạng thái: "chờ bạn" dùng màu chủ đạo `#60a5fa`, giống cmux dùng viền xanh cho agent đang chờ. "Xong" `#6fd49a`, "lỗi" `#e88a8a`. Màu "đang chạy" (vàng) là của người dùng. | Đổi token, rẻ |
| C2 | Bản đầu chỉ có giao diện tối | Thêm giao diện sáng sau: phải làm thêm một bộ token, mức trung bình |
| C3 | Phần riêng của ShellX mà cả hai nền tảng cần (tài khoản, chấp thuận, link chia sẻ, cập nhật) viết một lần bằng Rust trong `shellx-core` và dùng chung qua FFI | Nếu FFI giữa Swift và Rust gây khó, phải viết lại các phần đó bằng Swift. Tốn công, nhưng không đổi thiết kế |
| C4 | Dùng lại tài khoản hiện có (email + mật khẩu) cho relay v2 | Nếu người dùng muốn đăng nhập kiểu khác (Apple/Google), phải thêm luồng đăng nhập |
| C5 | Bản native bắt đầu từ 2.0.0 | Chỉ là con số |
| C6 | Bỏ hẳn telemetry, không thêm báo lỗi tự động của bên thứ ba | Khó điều tra lỗi trên máy người dùng. Có thể thêm báo lỗi tự host sau |
| C7 | Lệnh CLI tên `shellx`. Cấu hình Ghostty vẫn đọc như cmux | Đổi tên lệnh sau sẽ làm hỏng script của người dùng |
| C8 | Mặc định của link chia sẻ: "Chỉ xem", hạn 1 giờ. QR "Tiếp tục trên điện thoại" hết hạn sau 2 phút, quyền "Được gõ" | Đổi mặc định, rẻ |
| C9 | Thứ tự đợt như §10: Mac và relay song song, Windows sau | Windows ra muộn hơn nếu người dùng cần nó sớm |
| C10 | Ngưỡng hiệu năng "không tệ hơn quá 10%" so với cmux gốc và Windows Terminal | Ngưỡng quá chặt thì kéo dài dự án; quá lỏng thì không đạt điều người dùng muốn |
| C11 | Relay v1 chạy song song cho tới khi người dùng quyết định tắt | Tốn thêm một dịch vụ trên VPS |
| C12 | Thứ được chia sẻ hoặc gửi sang điện thoại là **cả phiên**. Điện thoại xem từng pane một. Pane trình duyệt và Agent Chat không chia sẻ. Chia khung phiên ở xa thì shell chạy trên máy chủ phiên | Nếu người dùng chỉ muốn chia sẻ một pane, phải thêm chọn pane khi chia sẻ. Giao thức thì không đổi |
| C13 | VPS thuộc về máy đã thêm nó, không đồng bộ qua tài khoản. ShellX được tự cài helper lên VPS như cmux, và ShellX tự host helper | Muốn thấy VPS từ mọi máy thì phải đồng bộ cấu hình SSH qua tài khoản (có mã hoá). Tự host helper tốn thêm một quy trình build và ký cho Linux |
| C14 | Trang xem trên trình duyệt điện thoại không gửi thông báo đẩy. Thông báo đến cùng app mobile native | Người dùng không nhận được tin "agent cần bạn" trên điện thoại cho tới khi có app mobile |
| C15 | Phát hành Flutter 1.0.1 để gửi nền tảng và phiên bản hệ điều hành. Chỉ bắt người dùng Flutter trên macOS 14+ cập nhật. macOS 12–13 ở lại bản 1.0.1 | Thêm một bản Flutter, sửa nhỏ ở relay. Người dùng macOS 12–13 không có bản mới |
| C16 | Giữ các phần remote có sẵn của cmux (phản chiếu thiết bị, chia sẻ kích thước terminal, máy chủ cho điện thoại, presence, `RemoteTui`) và chỉ thay đường truyền và đăng nhập. Relay là bản tự host của `cmux-relay` (khung mờ + Noise). Mac và Windows dùng chung **một** giao thức, chọn giữa mobile RPC và giao thức `cmux-tui` ở bước thử §13 (sửa ngày 18/10 sau khi đọc code: Mac phục vụ phiên bằng mobile RPC chứ không phải giao thức `cmux-tui`). **Chốt 19/10: giao thức `cmux-tui`**, Mac thêm cầu nối daemon (~20 ngày công) | Nếu cả hai ứng viên đều tốn công, phải viết giao thức riêng. Đợt 2 và đợt 4 kéo dài thêm |
| C17 | Trang xem link chia sẻ chỉ dùng code của ShellX và thư viện giấy phép dễ dãi, hoặc nằm trong repo công khai theo GPL | Gần như không có giá, chỉ giới hạn lựa chọn thư viện |

## 15. Để lại cho người làm

- Cách đo hiệu năng cụ thể và công cụ đo (§2.2).
- Bộ công cụ giao diện cho Windows, chọn sau bước thử (§8.3, §13).
- Chi tiết giao thức relay v2: khung tin, cơ chế mã hoá (ví dụ Noise như v1), cách máy tính chấp thuận máy tính, cách đặt khoá trong link chia sẻ (§8.5).
- Bộ vẽ terminal trên trang xem link, và trang đó nằm trong site Astro hay là ứng dụng riêng (§8.7).
- 16 màu ANSI mặc định (§7.4).
- Icon thay thế khi coolicons không có icon phù hợp (§7.4).
- Chu kỳ kéo bản sửa từ upstream (§8.2).
- Tên đường dẫn hoặc tên miền con cho relay v2 trên VPS, miễn nằm trong `~/phu/shellx` (§8.5).
- Bộ cài Windows (§11).
- Giữ hay bỏ bản dịch tiếng Nhật có sẵn của cmux.
