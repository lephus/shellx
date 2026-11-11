# ShellX cho Windows: dùng được thật — đặc tả thiết kế

Ngày: 2026-11-12. Liên quan: đặc tả đăng nhập email `2026-11-10-shellx-email-code-sign-in-design.md`, đặc tả
Windows giống Mac `2026-11-01-windows-mac-parity-design.md`, hợp đồng `plans/2026-11-07-shellx-mobile-contracts.md` §29.
Nhãn: **[người dùng]** là lời hoặc quyết định của người dùng; **[người viết]** là quyết định của người viết,
người dùng có thể đổi (gom ở mục 10). Trạng thái: người dùng đã cho phép làm tiếp ngay sau khi đặc tả xong
(2026-11-11: "sau khi xong spec, hãy thực hiện điều phối để hoàn thiện sản phẩm; tất cả push bàn giao lên develop").

Bằng chứng nằm trong năm bản review và một bản khảo sát, ở `.superpowers/sdd/2026-11-11-windows-usable/`
(không commit): `review-1-install-launch-render.md` (R1), `review-2-input.md` (R2), `review-3-local-terminal.md`
(R3), `review-4-account-pairing-remote.md` (R4), `review-5-history.md` (R5), `recon-mac-host.md` (M). Mỗi mục
dưới đây ghi nguồn dạng "R4 Blocker 1". Người làm đọc bản review tương ứng để lấy file:dòng và cách sửa gợi ý.

## 1. Ý định và lý do

Người dùng, 2026-11-11: "riêng với desktop app cho Windows bạn cần review kỹ nhé (phiên bản hiện tại Windows
không sử dụng được)" **[người dùng]**. Người dùng chưa nói rõ hỏng ở bước nào.

Review cho thấy không cần đoán: có lỗi chắc chắn chặn việc dùng, và có một lỗ hổng quy trình khiến không ai
biết. Bản Windows chưa từng được một người kiểm theo danh sách (0 trên 45 mục), và từ bản 1.5.1 chưa có bài
kiểm tự động nào chạy thử file exe (GitHub Actions bị khoá thanh toán từ 2026-10-28; bản build chéo trên VPS
không chạy test Windows, không chạy thử khởi động). Vì vậy đặc tả này có hai nửa ngang nhau: **sửa những gì đã
biết là hỏng**, và **dựng vòng kiểm để lần sau "không dùng được" trở thành một file gửi lại được**.

## 2. Hiện trạng đã kiểm chứng

| Điều | Mức chắc chắn | Nguồn |
|---|---|---|
| Đăng nhập không bao giờ xong, ở mọi bản Windows native (1.7.0 và `develop`): relay không gửi khoá trong danh sách máy nên lõi trả `fingerprint: null`, còn mô hình Windows bắt buộc là chuỗi. Người dùng thấy `machines.list: invalid type: null, expected a string`. | Đã chứng minh, tái hiện bằng mã nguồn thật | R4 Blocker 1 |
| Bản `develop` chỉ còn đăng nhập Google; relay production không có đường Google; bản build chéo không mang mã ứng dụng Google nên báo `not_configured`. | Đã chứng minh | R4 Blocker 3 |
| Không app nào tạo được tài khoản mới. Mã email và Google tạo tài khoản ở lần đăng nhập đầu, nhưng chỉ khi relay mới được deploy. | Đã chứng minh | R4 Blocker 4 |
| Chưa bản Mac công khai nào trả lời yêu cầu từ PC (`remoteMachines = false`); PC chờ 300 giây rồi hết hạn, không có lời giải thích. | Đã chứng minh | R4 Blocker 2, M |
| Chữ gõ qua Unikey / EVKey có thể bị lặp đôi hoặc kèm ký tự rác: GPUI gọi `TranslateMessage` thêm một lần ở lúc nhả phím `VK_PACKET`. | Đường code đã chứng minh; kết quả trên Windows suy ra (~50%) | R2 F1 |
| Cửa sổ đầu tiên 1200×760 không vừa màn hình ở 1920×1080 tỉ lệ 150% (mặc định của laptop 13–14") và 1366×768: dấu nhắc lệnh nằm sau thanh taskbar. | Đã chứng minh | R1 F2 |
| Mọi lỗi đều im lặng: không panic hook, không log, không file crash; cửa sổ biến mất không dấu vết. | Đã chứng minh | R1 F3 |
| Không có đường lùi khi GPUI không dựng được bộ vẽ DirectComposition; luồng vsync của GPUI chia cho 0 khi DWM báo chu kỳ dưới 1 ms; mất thiết bị GPU lúc đổi cỡ có thể làm sập. | Cơ chế đã chứng minh; tần suất chưa biết | R1 F4, F6, F5 |
| Cuộn bằng touchpad gần như không nhúc nhích (làm tròn từng sự kiện, không cộng dồn). | Đã chứng minh phần làm tròn | R2 F2 |
| Chỉ có Windows PowerShell 5.1; không chọn được PowerShell 7, cmd, Git Bash, WSL. Shell không khởi động được thì ô terminal thành ngõ cụt. | Đã chứng minh | R3 M1 |
| Bộ cài và exe chưa ký; trang tải không hướng dẫn gì; exe không có thông tin phiên bản/nhà phát hành. | Đã chứng minh | R1 F1 |
| Relay giả dùng trong test trả lời khác relay thật, nên lỗi đăng nhập ở dòng đầu qua được mọi test. | Đã chứng minh | R4, kế hoạch Mac Ruling 33 |

Điều đã biết là chạy được: bản 1.5.3 (cùng dây chuyền build chéo) từng mở cửa sổ trên máy người dùng; code gõ
phím thường và lệnh khởi động shell không thấy lỗi khi đọc (R1 "found sound", R2 §11, R3).

## 3. Mục tiêu, không mục tiêu, phản mục tiêu

Mục tiêu (Phần 1, đặc tả này):
1. Một người cài, mở, **thấy trọn cửa sổ**, gõ được (kể cả tiếng Việt qua Unikey, EVKey và bộ gõ Telex của
   Windows), có shell chạy được, cuộn được, dán được.
2. **Đăng nhập xong được** với relay thật: email và mã 6 số là cách chính ("email trước"); Google chỉ hiện khi
   bản build có cấu hình Google.
3. App **không còn nút nào dẫn vào ngõ cụt**: chỗ nào chưa làm được thì nói thật và nói bước tiếp theo.
4. Khi có gì hỏng, app **để lại bằng chứng**: file log, file crash, và một báo cáo chẩn đoán tạo bằng một thao tác.
5. Mỗi thay đổi có test chạy được trên máy Mac này; phần chỉ dành cho Windows ít nhất **biên dịch được** bằng một
   lệnh; và có một **bản cài thử** cho người dùng kiểm trên máy thật theo danh sách 10 bước.

Không mục tiêu: PC mở terminal của Mac (Phần 2, đặc tả riêng, mục 7.2); PC làm máy chủ cho điện thoại; ký số
(người dùng làm sau); các đợt giống Mac 2–5 (bảng lệnh, thông báo, nhóm workspace, Git Graph); giao diện sáng;
trình đọc màn hình; hỗ trợ proxy; phát hành bản Windows mới (người dùng quyết sau khi kiểm).

Phản mục tiêu (làm xong vẫn thất bại nếu xảy ra): test xanh trong khi relay thật trả lời khác; sửa một lỗi gõ
phím làm hỏng gõ thường; nhật ký hay báo cáo chẩn đoán chứa token, địa chỉ email, mã OTP hoặc nội dung terminal;
bản cài thử đè lên bản công khai hoặc tự cập nhật người dùng thật; một nút mới chỉ có thể thất bại.

## 4. Thiết kế

Nguyên tắc chung **[người viết]**: mọi quy tắc là hàm thuần trong `shellx-model` (hoặc `shellx-core`) có test
chạy trên Mac; `shellx-app` chỉ nối dây. Phần gọi Win32 gói nhỏ, không chứa quyết định.

### 4.1 Đăng nhập

- **Sửa lỗi chặn** (R4 Blocker 1): mô hình Windows nhận `fingerprint` là null (không dùng nó để quyết định gì).
- **Email trước**: hộp đăng nhập mở ra với ô email và nút Gửi mã, dòng "hoặc", rồi Google, rồi Huỷ; bước nhập mã
  6 số; mọi phản ứng với relay theo bảng D2, bàn phím theo D3, quy tắc ASCII và chữ số theo D4, câu chữ theo D5
  của `.superpowers/sdd/2026-11-11-shellx-email-code-signin/desktop-decisions.md`. Phần này đã được thiết kế và
  soát trong kế hoạch `plans/2026-11-11-shellx-email-code-signin-windows.md` (đang tạm dừng): kế hoạch mới dùng
  lại nội dung đó, không thiết kế lại. Nó cần hai RPC `auth.email.begin` / `auth.email.finish` của lõi (kế hoạch
  Mac, task 1–3).
- **Google chỉ hiện khi dùng được** **[người viết]**: lõi cho biết bản build có mã ứng dụng Google hay không; không
  có thì không vẽ nút và dòng "hoặc". Không bao giờ hiện `not_configured` cho người dùng.
- **Hộp đăng nhập không tự bật** **[người viết]** (R2 F12): khi server kết thúc phiên, app hiện một dòng báo có
  nút "Đăng nhập lại" ở chân thanh bên và trong Cài đặt › Tài khoản; hộp thoại chỉ mở khi người dùng bấm. Phím
  đang gõ cho shell không bao giờ rơi vào hộp thoại.
- **Đăng xuất có ở mọi trạng thái có phiên**, kể cả trạng thái lỗi (R4 Major 6).
- **Câu báo lỗi là câu**, không phải mã hay văn bản thô của server (R4 Minor 9, 10); lỗi không có câu riêng dùng
  câu chung "ShellX đang gặp sự cố. Thử lại sau."
- Tài khoản mới: không cần màn riêng; mã email tạo tài khoản ở lần đầu. Hộp thoại có một dòng nhỏ nói điều đó.

### 4.2 Mở app: cửa sổ, lỗi không im lặng, chế độ hiển thị tương thích

- **Cửa sổ đầu vừa màn hình** (R1 F2): kích thước đầu = 1200×760 thu lại cho vừa vùng làm việc (không tính
  taskbar) của màn hình đang dùng, không nhỏ hơn 720×420; không vừa thì mở phóng to. Test cho bốn cấu hình của R1.
- **Không lỗi nào im lặng** (R1 F3): panic ở bất kỳ luồng nào ghi file crash (thông điệp, vị trí, backtrace, phiên
  bản, commit, bản Windows). Hộp thoại báo lỗi **không** được vẽ từ trong panic hook của luồng giao diện (lúc đó
  đang ở trong thủ tục cửa sổ của GPUI, vẽ hộp thoại sẽ gọi ngược vào GPUI): hook chỉ ghi file rồi khởi chạy
  chính exe này ở chế độ "báo lỗi" (một tiến trình riêng, không có GPUI) để hiện hộp thoại nêu tên file và hỏi có
  mở thư mục không. Lỗi không phải panic (ví dụ truy cập bộ nhớ sai, mã 0xc0000005) được bắt bằng bộ lọc ngoại lệ
  chưa xử lý của Windows, ghi một file crash tối thiểu (mã lỗi, địa chỉ, module) và dùng cùng tiến trình báo lỗi;
  chưa cần minidump. Không mở được cửa sổ thì cũng hiện hộp thoại nêu lý do, không thoát lặng lẽ.
- **Chế độ hiển thị tương thích** (R1 F4): khi mở cửa sổ thất bại, hoặc lần chạy trước chết trước khung hình đầu
  (dấu "đang khởi động" chưa được xoá), app tự chạy lại một lần với `GPUI_DISABLE_DIRECT_COMPOSITION=1` và ghi
  điều đó vào log; cả hai cách đều thất bại thì hiện hộp thoại kèm đường dẫn log. Không lặp vô hạn. Khi chế độ
  tương thích đã vẽ được khung hình đầu, app **ghi nhớ** lựa chọn đó cho các lần mở sau (không thử lại cách thường
  mỗi lần). Cài đặt hiện chế độ đang dùng và có nút "Thử lại chế độ hiển thị thường"; thử mà hỏng thì quay về
  chế độ tương thích như trên.
- **Cờ dòng lệnh in ra console** (R1 F12): `--version`, `--smoke`, `--diagnose` gắn vào console của tiến trình
  cha.
- **Bản vá GPUI qua một cơ chế duy nhất** **[người viết]**: chép gpui 0.2.2 vào repo (`windows/vendor/`, giấy phép
  Apache-2.0 giữ nguyên) và trỏ `[patch.crates-io]` tới đó; commit đầu là bản gốc không sửa, mỗi bản vá là một
  commit riêng có ghi lý do. Vòng này gồm đúng bốn bản vá: (a) `VK_PACKET` chỉ dịch ở lúc nhấn phím (R2 F1);
  (b) vsync không chia cho 0 (R1 F6); (c) đổi cỡ khi mất thiết bị không để lại trạng thái thiếu đích vẽ, và khôi
  phục không giải phóng hai lần (R1 F5); (d) bước biên dịch shader khi build chéo, hiện đang vá bằng script trong
  container, chuyển vào bản chép (script `patch-gpui-build-rs.py` bị bỏ và `build-in-container.sh` thôi gọi nó; ảnh
  container vì thế được dựng lại một lần). Mọi bản build (Mac, CI, build chéo) dùng cùng một bản; `Cargo.lock` của
  `windows/` đổi đúng một mục (gpui mất nguồn và checksum) và được commit; để được vậy, thư mục chép phải bị loại
  khỏi workspace (`exclude`), nếu không nó thành một thành viên và kéo theo thay đổi khác. Mỗi file GPUI bị sửa mang một dòng
  ghi chú "đã sửa bởi ShellX" ở đầu file, theo điều 4(b) của giấy phép Apache-2.0.
  Lý do chọn chép thay cho cách rẻ hơn: riêng bản vá (a) có thể làm ở tầng app bằng cách chặn thông điệp nhả
  phím `VK_PACKET` trước khi GPUI thấy, nhưng (b), (c) và phần lớn mục "để sau" về bàn phím và bộ gõ (R2 F3, F8,
  F9; R1 F14) đều nằm trong code Windows của GPUI, không sửa được từ ngoài. Một cơ chế cho tất cả.

### 4.3 Gõ phím, bộ gõ, chuột

- Unikey / EVKey: bản vá (a) ở 4.2. Đây là mục kiểm số một trên máy thật (mục 5.3).
- **Cuộn touchpad** (R2 F2): cộng dồn phần lẻ theo từng ô terminal, đổi chiều thì bỏ phần dư.
- **Bánh xe trong chương trình toàn màn hình** (R2 F13, R3): khi terminal ở màn hình phụ và chương trình không bật
  chuột, bánh xe gửi phím mũi tên lên/xuống.
- **Phím tắt**: Alt+Shift+= và Alt+Shift+- chia ô được theo đúng dạng phím GPUI trên Windows báo (R2 F5); Alt+F4
  và Alt+Space trả về cho Windows (R2 F7).
- **Chuột phải**: dán (hoặc chép khi đang có vùng chọn), như console của Windows (R2 F10). Bấm chuột phải hay
  giữa lên ô **chưa** có tiêu điểm chỉ chuyển cả bàn phím lẫn tiêu điểm của app sang ô đó, không dán, để không dán
  nhầm và để lệnh đóng ô không đóng nhầm (R2 F4); bấm lần nữa mới dán.
- **Dán nhiều dòng** vào shell chưa bật chế độ dán có ngoặc: hỏi xác nhận trước, vì mỗi dòng sẽ chạy ngay (R2 F18).
  "Nhiều dòng" là có một dấu xuống dòng mà sau nó còn ký tự không phải khoảng trắng (một dòng kèm xuống dòng cuối
  không tính). Quy tắc áp dụng cho mọi đường dán (Ctrl+Shift+V, Shift+Insert, chuột phải) và mọi loại ô.
- **Bỏ khỏi giao diện những thứ chỉ để trưng** **[người viết]**: ô tìm kiếm trên thanh tiêu đề và chuông (R2 F15,
  R5 K12) không vẽ cho tới khi chúng làm được việc.

### 4.4 Terminal cục bộ

- **Chọn shell** (R3 M1): mặc định "Tự động" = PowerShell 7 nếu có, không thì Windows PowerShell (đường dẫn tuyệt
  đối), không thì Command Prompt. Cài đặt › Terminal cho chọn trong các shell tìm thấy (thêm Git Bash, WSL nếu có)
  hoặc một dòng lệnh tuỳ chỉnh có tham số. `SHELLX_SHELL` vẫn là cách ghi đè và nhận cả dòng lệnh có tham số.
  Dòng lệnh tuỳ chỉnh là một ô chữ, tách theo quy tắc dòng lệnh của Windows (đường dẫn có dấu cách phải nằm trong
  ngoặc kép; ô báo ngay khi không tìm thấy chương trình). Lựa chọn lưu trong file cài đặt hiện có của app.
- **Shell không khởi động được**: ô hiện câu báo bằng ngôn ngữ của app, có "Thử lại" và "Mở Command Prompt"; app
  tự thử shell kế tiếp một lần trước khi báo.
- **Thư mục trên thẻ workspace** (R3): móc dấu nhắc gửi đường dẫn đã mã hoá phần trăm theo UTF-8, để tên thư mục
  tiếng Việt không phụ thuộc bảng mã console. Shell không có móc (cmd, Git Bash, WSL, tuỳ chỉnh) vẫn chạy; thẻ
  chỉ hiện tên.
- **Không việc chậm nào trên luồng giao diện**: đọc nhánh git chuyển sang luồng nền, có nhớ đệm (R1 F15, R5 K6).

### 4.5 Máy khác trong tài khoản: nói thật cho tới Phần 2

**[người viết]** Hôm nay không máy nào trả lời được PC, nên nút "Xin quyền truy cập" chỉ có thể thất bại. Thiết kế:
- Danh sách máy vẫn hiện (tên, trực tuyến hay không), nhưng nút xin quyền chỉ vẽ cho máy mà relay báo
  `can_host: true`. Trường này hôm nay không có, nên mặc định là không; khi Phần 2 thêm nó vào relay và có bản Mac
  nhận kết nối, nút tự xuất hiện mà không cần bản Windows mới. Để lời hứa đó đúng, Phần 1 sửa cả **lõi**: lõi đọc
  `can_host` (tuỳ chọn, thiếu là false) trong danh sách máy của relay và chuyển tiếp trong kết quả `machines.list`;
  mô hình Windows nhận trường này với mặc định false. App Mac bỏ qua khoá lạ nên không bị ảnh hưởng.
- Không bao giờ mời xin quyền tới một máy Windows khác (R4 Major 5).
- Trong bảng "+" và ở danh sách trống có một câu nói thật: ShellX cho Mac hiện chưa nhận kết nối từ máy tính
  Windows; terminal trên máy này vẫn dùng bình thường. Danh sách trống thêm bước cần làm: đăng nhập ShellX trên Mac
  bằng cùng tài khoản.
- Để người dùng thử Phần 2 sớm với bản Mac thử: biến môi trường bật lại nút cho mọi Mac (chỉ đọc khi được đặt).

### 4.6 Bộ cài và trang tải

- Exe có thông tin phiên bản: tên sản phẩm, mô tả, nhà phát hành, số phiên bản (R1 F1).
- App giữ một mutex có tên; bộ cài khai báo `AppMutex` cùng tên để yêu cầu đóng ShellX trước khi cập nhật (R1 F9).
  Mutex chỉ phục vụ bộ cài: app **không** thành một-phiên-duy-nhất, mở nhiều cửa sổ vẫn như hôm nay; tiến trình
  chẩn đoán và tiến trình báo lỗi không cần giữ mutex.
- Build luôn nhắm CPU cơ sở cho thư viện terminal, ở cả CI lẫn build chéo (R1 F8, R3 M2).
- Trang tải (tiếng Anh và tiếng Việt) thêm: cách vượt cảnh báo SmartScreen có ảnh, ghi chú Smart App Control không
  vượt được khi chưa ký, mã SHA-256. Làm trên `develop`, cho người dùng xem ở localhost trước; trang chỉ lên khi
  người dùng push `main` (quy tắc web hiện có).
- Mã SHA-256 trên trang tải lấy từ cùng nguồn với đường dẫn tải (cấu hình trang, điền lúc phát hành từ file
  SHA256SUMS). Vòng này chỉ có hướng dẫn bằng chữ; ảnh chụp cảnh báo thêm sau, khi người dùng gửi ảnh từ máy thật.
- Bản cài thử: tên file `ShellX-Setup-<phiên bản>-test-<commit ngắn>.exe`, không đưa lên đường tải công khai, không
  đổi con trỏ cập nhật. Số phiên bản **bên trong** app giữ dạng `x.y.z` thuần (relay từ chối đăng ký máy có phiên
  bản dạng khác); nhãn thử và commit chỉ nằm ở tên file, mục Giới thiệu và báo cáo chẩn đoán. Bản thử dùng cùng
  mã ứng dụng của bộ cài nên cài đè lên bản đang có trên máy người thử: đó là chủ ý.

### 4.7 Chẩn đoán

- **Log**: `%LOCALAPPDATA%\ShellX\native\logs\shellx.log`, xoay vòng ở 1 MB, giữ 3 file; ghi cả thông điệp của
  GPUI (tên GPU, mức tính năng, mất thiết bị, lỗi phông).
- **Báo cáo chẩn đoán**: `shellx-desktop.exe --diagnose`, mục "Tạo báo cáo chẩn đoán" trong menu trợ giúp, và một
  lối tắt trong Start "ShellX – Chẩn đoán". Kết quả là một file văn bản trong thư mục log, và thư mục được mở ra.
  Nội dung: phiên bản, commit, kiểu build; bản Windows; CPU và các tập lệnh; từng màn hình (độ phân giải, tỉ lệ,
  vùng làm việc) và kích thước cửa sổ đã chọn; từng bộ điều hợp GPU (tên, driver, mức tính năng), bộ nào được
  chọn, đang ở chế độ vẽ nào; số đo thời gian của DWM (để biết máy có rơi vào lỗi vsync không); các bố cục bàn
  phím và bộ gõ đang cài, có thấy tiến trình Unikey / EVKey không; các shell tìm thấy và shell được chọn; kết quả
  chạy thử shell (khởi động, in một dòng, vòng tiếng Việt, đổi cỡ) kèm thời gian; thư mục trạng thái có ghi được
  không; đã đăng nhập hay chưa và bằng cách nào; có tới được relay không (mã trả lời của `/v1/version`, độ trễ);
  200 dòng cuối của log; danh sách file crash.
- **Không bao giờ có trong log, file crash hay báo cáo**: token, khoá, địa chỉ email, mã OTP, mã thử thách, nội
  dung terminal, chữ người dùng gõ, tên máy khác trong tài khoản. Cách bảo đảm, cả ba lớp: (1) mọi dòng ghi ra
  (log của app, của GPUI, của lõi, thông điệp panic) đi qua một bộ che: địa chỉ email, chuỗi giống token
  (base64url dài), dãy 6 chữ số đứng cạnh chữ "code", khoá dạng `re_…`; (2) các kiểu dữ liệu tài khoản không in
  email khi được định dạng để gỡ lỗi (hiện `Debug` tự sinh của luồng tài khoản có in); (3) báo cáo chạy bộ che
  thêm một lần trên phần log nó chép vào. Test: bộ che với từng mẫu; một dòng log và một thông điệp panic có cài
  sẵn bí mật phải ra sạch; định dạng gỡ lỗi của kiểu tài khoản không chứa email.
- Nguồn dữ liệu: không thêm thư viện ngoài nào chưa có trong `Cargo.lock` (`windows` và `log` đã có qua GPUI, được
  phép thành phụ thuộc trực tiếp). Bản Windows lấy bằng `RtlGetVersion`; bộ điều hợp GPUI chọn lấy từ dòng log của
  chính GPUI; "tới được relay" là kết quả và thời gian của lời gọi `version.check` sẵn có (không thêm RPC).

### 4.8 Chống lệch giữa relay giả và relay thật

Với mỗi lời gọi mà app Windows dùng (`GET/POST /v2/machines`, heartbeat, `/v2/pairings`, `/v2/relay/tickets`,
`/v1/version`, `/v1/auth/email/code|verify`, `/v1/account/identities`): hình dạng câu trả lời (tập khoá và kiểu,
kể cả null) **và quy tắc relay kiểm trên yêu cầu** (ví dụ mẫu của `app_version`, `os_version`, giới hạn độ dài
tên) có **một nguồn duy nhất** mà test của relay và test của lõi cùng đọc. Nguồn đó nằm dưới `relay/` (ảnh relay
được dựng với ngữ cảnh `relay/` và chạy test của relay ngay lúc dựng, nên không đọc được file ngoài thư mục này);
test của lõi đọc nó qua đường dẫn tương đối; không code nào được biên dịch trong container build chéo đọc nó
(container chỉ có `windows`, `cmux-tui`, `shellx-core`). Relay giả trả đúng hình dạng đó và từ chối đúng những
yêu cầu relay từ chối. Lệch ở một bên là có test đỏ.

Riêng danh sách máy **[người viết]**: mặc định relay giả trả như relay thật, tức không có `noise_public_key_b64`,
`os_version`, `app_version`; lõi vẫn giữ quy tắc cũ (không bao giờ tin `fingerprint` do server gửi; chỉ tính từ
khoá nếu relay có gửi khoá), nên với relay thật kết quả là `fingerprint: null`. Ba test của lõi đang giả định có
khoá được viết lại: hai test kỳ vọng null theo hình dạng thật; phần tính vân tay từ khoá được giữ bằng một tuỳ
chọn của relay giả chỉ bật trong đúng test đó. Không đổi relay trong Phần 1.

Thêm một test chạy trọn luồng đăng nhập của Windows qua lõi thật với relay giả đã sửa. Với relay giả hôm nay (có
gửi khoá) test này xanh, và đó chính là cách lỗi đã lọt; nó phải đỏ ngay khi relay giả trả đúng hình dạng thật và
trước khi mô hình được sửa. Thứ tự commit phải cho thấy điều đó.

## 5. Cách kiểm chứng

### 5.1 Trên máy Mac này
`cargo test --locked -p shellx-model` và test của `shellx-core` (đã chạy được); `cargo test --release --locked -p
shellx-app` và bản build cửa sổ cho Mac (chạy được từ 2026-11-12: submodule `ghostty` và zig 0.16 đã có; không bao
giờ dùng bản debug). Ảnh chụp cửa sổ cần quyền Ghi màn hình cho terminal: có thì chụp, không thì ghi "chưa chụp".

### 5.2 Biên dịch cho Windows
Code chỉ dành cho Windows không biên dịch trên Mac. Cần **một lệnh chạy từ máy này** biên dịch `shellx-app` cho
đích Windows mà không tạo bộ cài, mục tiêu dưới 10 phút khi bộ nhớ đệm còn ấm. Nó biên dịch commit đang đứng
(không phải file chưa commit), như script build chéo hiện có.
- **Ưu tiên chạy ngay trên máy này** **[người viết]**: Docker đang chạy ở đây (kiến trúc arm64). Một ảnh "chỉ biên
  dịch" không cần wine (clang, lld, cargo-xwin, zig đều biên dịch chéo được từ arm64). Lệnh kiểm tra dùng cấu hình
  build "dev": ở cấu hình đó GPUI không biên dịch shader (nó chỉ làm khi tắt debug assertion), nên không cần wine
  và không cần thêm bản vá nào.
- **Không được thì dùng container trên VPS** như script hiện có, thêm chế độ không tạo bộ cài và giữ bộ nhớ đệm
  giữa các lượt. VPS dùng chung với dịch vụ đang chạy thật: giữ giới hạn 4 CPU và 10 GB như hiện nay, kiểm dung
  lượng đĩa trước (việc deploy cần còn trống 4 GB), không chạy hai lượt cùng lúc, chỉ thao tác trong thư mục build
  của ShellX, đăng nhập bằng khoá của máy này.
- **Bản cài thử** (có wine để biên dịch shader thật và đóng gói) luôn build trên VPS bằng đường đã dùng cho các
  bản phát hành; số lượt ít.

### 5.3 Trên máy Windows thật (người dùng)
Người viết build bản cài thử (5.2, có tạo bộ cài), để ở `~/Desktop/ShellX-windows-test/` kèm SHA-256. Người dùng
làm 10 bước; bước nào hỏng thì chạy "ShellX – Chẩn đoán" và gửi lại file:
1. Cài (ghi lại cảnh báo nào hiện ra). 2. Mở: cửa sổ nằm trọn trong màn hình, thấy dấu nhắc lệnh. 3. Gõ `dir` rồi
Enter. 4. Bật Unikey hoặc EVKey kiểu Telex, gõ `aa dd tieengs`: phải ra `â đ tiếng`. 5. Bộ gõ Telex của Windows:
cùng dòng chữ. 6. Chạy `1..500`, cuộn lên chậm bằng touchpad, rồi bằng chuột. 7. Chép một dòng ở Notepad, chuột
phải để dán; chép ba dòng, dán: phải hỏi trước. 8. Alt+Shift+= chia ô; Alt+F4 đóng cửa sổ. 9. Cài đặt › Terminal:
đổi shell, mở tab mới. 10. Cài đặt › Tài khoản › Đăng nhập: nhập email, nhận mã, vào được (chỉ làm được sau khi
relay mới lên production; trước đó phải thấy câu "chưa dùng được", không phải mã lỗi).
Danh sách này thay cho 45 mục cũ trong vòng này; các mục cũ còn lại chuyển xuống "kiểm sau".

### 5.4 Nếu GitHub Actions được mở lại
Job `app` của `shellx-windows.yml` chạy test, `--smoke`, `--version` và thêm `--diagnose` trên Windows Server thật
mỗi lần push `develop`. Đây là quyết định về thanh toán của người dùng; thiết kế không phụ thuộc vào nó.

## 6. Thứ tự làm

0. **Công cụ** (làm trước, song song với nhóm 1): lệnh biên dịch cho Windows (5.2); chép gpui 0.2.2 bản gốc vào
   repo, trỏ `[patch.crates-io]`, chuyển bước shader vào bản chép, chứng minh bản build cho Mac và bộ test của
   `shellx-app` vẫn xanh.
1. **Ngay** (hàm thuần, test trên Mac; hai RPC email của lõi và các đường email của relay giả đã có trên `develop`
   từ d847812117): sửa `fingerprint`, `can_host` trong lõi, relay giả đúng hình dạng và nguồn
   duy nhất (4.8), đăng xuất khi lỗi, câu báo lỗi, chỉ mời Mac và `can_host`, quy tắc cỡ cửa sổ, cộng dồn cuộn,
   phím tắt, quy tắc chọn shell và mã hoá đường dẫn, quy tắc dán nhiều dòng, mẫu báo cáo chẩn đoán và test quét bí mật.
2. **Luồng đăng nhập "email trước"** trong mô hình và lời gọi lõi (phần mô hình dùng lõi giả nên làm song song
   với nhóm 1 được).
3. **Nối dây trong `shellx-app`** (build trên Mac và biên dịch cho Windows bằng lệnh của nhóm 0): hộp đăng nhập, dòng báo đăng nhập lại,
   Cài đặt › Terminal, chuột phải, tiêu điểm, bỏ ô tìm kiếm và chuông, đọc git ở luồng nền.
4. **Phần chỉ có trên Windows** (cần nhóm 0): panic hook, bộ lọc ngoại lệ, tiến trình báo lỗi, log và bộ che,
   `--diagnose`, console, chế độ tương thích, mutex, thông tin phiên bản, bộ cài, ba bản vá GPUI còn lại (a, b, c).
5. **Bản cài thử và 10 bước** trên máy người dùng; sửa theo file chẩn đoán gửi về.
6. **Tài liệu**: README Windows, danh sách kiểm mới, trang tải (xem ở localhost).
Mỗi nhóm là một nhánh từ `develop`, review rồi merge `--no-ff` và push `develop`.

## 7. Để sau, và Phần 2

### 7.1 Để sau (không thuộc vòng này), xếp theo mức đáng làm
Phím tắt Ctrl/Alt trên bố cục không phải Latin (R2 F3); phím chết của bố cục US-International (R2 F8); các ca rìa
của IME ngoài tiếng Việt (R2 F9, R5 K10); thứ tự định dạng clipboard (R2 F11); đổi cỡ từ cạnh trên (R2 F14); dán
lớn làm đứng giao diện (R5 K5); bề rộng ô chữ bám điểm ảnh và phông Nerd Font (R1 F11, R3); gửi chuột cho chương
trình terminal; cỡ chữ; hỏi trước khi đóng tab đang chạy lệnh; khôi phục phiên; proxy hệ thống (R4 Major 7); bảo vệ
file khoá bằng DPAPI/ACL (R5 K4); người đến từ bản Flutter (mục 10, câu 2); nghi vấn hỏng bộ nhớ khi liên kết thư
viện zig (R3 §3, R5 K7): thêm một bước kiểm vào báo cáo chẩn đoán nếu rẻ, còn điều tra thì để sau.

### 7.2 Phần 2: Mac trả lời PC (đặc tả riêng, cần người dùng quyết)
Khảo sát M cho thấy đây là một dự án, không phải một công tắc: code phía Mac có nhưng chưa nối giao diện, chưa
từng chạy trọn; chưa có chỗ xem và thu hồi quyền của PC đã duyệt; bật lên là bật cho mọi Mac và khiến việc phục vụ
điện thoại phụ thuộc vào một tiến trình nền mới; và từ khi có mã email, ai giữ hộp thư là vào được tài khoản.
Danh sách 17 việc và ba rủi ro lớn nằm trong M. Phần 1 chỉ chuẩn bị chỗ nối (`can_host`, mục 4.5).

## 8. Rủi ro

- **Không có máy Windows để chạy thử.** Mọi bản sửa gõ phím và hiển thị chỉ được chứng minh khi người dùng làm 10
  bước. Giảm rủi ro: quy tắc là hàm thuần có test; báo cáo chẩn đoán; mỗi bản vá GPUI nhỏ và tách riêng.
- **Bản vá `VK_PACKET` dựa trên suy luận.** Nếu Unikey trên máy thật không gửi cặp nhấn/nhả, bản vá vô hại; nếu
  nguyên nhân là chỗ khác, bước 4 của danh sách sẽ cho thấy và file chẩn đoán cho biết bộ gõ nào.
- **Chép GPUI vào repo** thêm khoảng 8 MB và một nghĩa vụ theo dõi bản gốc. Chấp nhận vì bốn lỗi nằm trong GPUI.
- **Đăng nhập thật chưa kiểm được trên Windows** cho tới khi relay mới lên production (quyết định deploy của người
  dùng). Trước đó chỉ có test với relay giả đã sửa hình dạng, và kiểm sống phần lõi trên Mac với relay chạy tại máy.
- **Tài khoản còn mật khẩu** sẽ nhận 409 khi dùng mã email trên thiết bị mới chừng nào relay còn bật đăng nhập mật
  khẩu, và chưa bản app công khai nào có nút chuyển đổi mà câu báo nhắc tới (R4 Major 8). Thứ tự phát hành và việc
  tắt mật khẩu là quyết định triển khai, nằm ngoài đặc tả này nhưng phải được quyết trước khi phát hành bản Windows.
- **Build trên VPS dùng chung** có thể làm chậm dịch vụ đang chạy: giữ giới hạn tài nguyên, chạy lúc vắng.

## 9. Việc để lại cho người làm

Tên hàm, tên file, hình dạng "nguồn duy nhất" ở 4.8 (file JSON dùng chung hay danh sách khoá); cách lõi báo có cấu
hình Google; nơi đặt dấu "đang khởi động" và điều kiện xoá; cách đo "khung hình đầu"; bố cục Cài đặt › Terminal;
câu chữ tiếng Việt và tiếng Anh cho các câu mới (theo giọng của các chuỗi hiện có); hình dạng lệnh biên dịch trên
VPS; có tách phần Win32 thành crate riêng không; chi tiết từng bản vá GPUI; ảnh cho trang tải.

## 10. Quyết định của người viết cần người dùng xem, và câu hỏi mở

Quyết định của người viết (đang làm theo, đổi được):
1. Chia hai phần; Phần 1 không bật gì phía Mac (mục 7.2).
2. Ẩn nút xin quyền cho tới khi relay báo máy đó nhận kết nối, thay vì giữ nút kèm lời nhắc (4.5).
3. Chép GPUI vào repo để vá (4.2).
4. Hộp đăng nhập không tự bật; thay bằng dòng báo có nút (4.1).
5. PowerShell 7 là mặc định khi máy có (4.4).
6. Bỏ ô tìm kiếm và chuông khỏi giao diện cho tới khi chúng hoạt động (4.3).
7. Danh sách 10 bước thay cho 45 mục cũ trong vòng này (5.3).
8. Hộp thoại báo lỗi do một tiến trình riêng vẽ; lỗi không phải panic cũng để lại file (4.2).
9. Chế độ hiển thị tương thích được ghi nhớ sau khi nó cứu được một lần mở (4.2).
10. Chuột phải lên ô chưa có tiêu điểm chỉ chuyển tiêu điểm, không dán (4.3).
11. Danh sách máy của relay giả theo đúng relay thật; lõi vẫn không tin vân tay của server (4.8).
12. Biên dịch cho Windows ưu tiên chạy bằng Docker trên máy này; chỉ bản cài thử mới build trên VPS (5.2).

Câu hỏi mở cho người dùng (không chặn việc đang làm):
1. Trên máy Windows của bạn, app dừng ở đâu? (Nếu là dòng lỗi `machines.list…` hoặc chữ tiếng Việt bị lặp thì đã
   nằm trong vòng này.)
2. Người đến từ bản Flutter: bộ cài mới có nên đề nghị gỡ bản cũ (đánh dấu sẵn) không? Hiện hai bản cài cạnh nhau
   theo quyết định 2026-10-21, và gỡ bản Flutter sẽ xoá lối tắt duy nhất của bản mới (R1 F7).
3. Có mở lại GitHub Actions không? Có thì mỗi lần push có một máy Windows thật chạy thử (5.4).
4. Bản cài thử: để trên Desktop của Mac này, hay đưa lên một đường dẫn không công bố trên máy chủ tải để tải thẳng
   từ PC?
5. Phần 2 (Mac trả lời PC): có làm ngay sau Phần 1 không, và với hàng rào nào (mục 7.2)?
6. Tôi sẽ dùng VPS để build bản cài thử (giới hạn 4 CPU, 10 GB, chạy lúc vắng), như các bản phát hành trước đã
   làm. Nếu không muốn VPS bị dùng cho việc này thì nói, tôi sẽ tìm cách khác hoặc chờ.
