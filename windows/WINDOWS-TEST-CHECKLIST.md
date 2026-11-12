# ShellX Windows: danh sách kiểm trên máy thật

Việc của bạn trên một máy Windows 10 1809+ hoặc Windows 11, với **bản cài thử** (`ShellX-Setup-<phiên bản>-<nhãn>-<commit>.exe`, kèm file `.sha256`; người build đưa đường dẫn và mã SHA-256). Đây là bản thử, không phải bản phát hành; nó cài đè lên ShellX đang có trên máy (cùng mã ứng dụng), đó là chủ ý. Không có bước nào cần mật khẩu hay khoá của bạn gửi qua chat.

Kiểm mã SHA-256 trước khi cài: `Get-FileHash .\<tên file>.exe -Algorithm SHA256` (PowerShell) rồi so với file `.sha256`.

**Cách dùng.** Làm 10 bước ở Phần 1 theo đúng thứ tự, đánh dấu `[x]` khi đạt. Bước nào hỏng thì làm đúng một việc: mở Start, chạy **"ShellX – Chẩn đoán"** (bản cài tiếng Anh: "ShellX – Diagnostics"). Vài giây đến khoảng 70 giây sau, Explorer mở ra với file `diagnostics.<giờ>.<số>.txt` đã chọn sẵn: bấm một lần, đừng bấm lại. Gửi file đó kèm một dòng: bước mấy, thấy gì. File chẩn đoán không chứa token, khoá, địa chỉ email, mã đăng nhập hay nội dung terminal; nếu muốn chắc, mở nó bằng Notepad và tìm ký tự `@` (chỉ được thấy `<email>`). Nếu ShellX tự hiện hộp "ShellX gặp lỗi" hoặc "ShellX không mở được cửa sổ", bấm Yes (Có) để mở thư mục và gửi file `crash.*.txt` hoặc `start-failed.*.txt` ở đó.

**Một quy tắc.** Lệnh `--crash-test window` ở Phần 3 làm ShellX nhớ "chế độ hiển thị tương thích". Làm nó **cuối cùng**, rồi đổi lại chế độ thường (Cài đặt › Hiển thị) trước khi đánh giá bất cứ điều gì khác.

Thư mục dữ liệu và log: `%LOCALAPPDATA%\ShellX\native` (log và file crash ở `logs\`).

---

## Phần 1: 10 bước

- [ ] **1. Cài.** Chạy bản cài thử và **ghi lại mọi cảnh báo hiện ra** (SmartScreen "Unknown publisher": bấm "More info" rồi "Run anyway"; Smart App Control; phần mềm diệt virus).
  - Đạt: cài xong mà không hỏi quyền quản trị; Start có hai mục "ShellX" và "ShellX – Chẩn đoán". Cảnh báo SmartScreen là bình thường (bản chưa ký); chỉ cần ghi lại.
  - Nếu Smart App Control chặn hẳn và không có nút "Run anyway": ghi "bị Smart App Control chặn" và dừng ở đây (bản chưa ký không vượt được).
  - Nếu hỏng: gửi ảnh chụp cảnh báo hoặc lỗi; nếu đã cài được thì chạy "ShellX – Chẩn đoán".
- [ ] **2. Mở.** Mở ShellX từ Start.
  - Đạt: cửa sổ nằm **trọn trong màn hình**, hai cạnh bên và cạnh dưới nằm trong vùng làm việc, thanh taskbar không che dấu nhắc lệnh, thấy dấu nhắc `PS …>` trong vòng vài giây. (Mép trên 3 đến 6 điểm ảnh có thể hơi bị cắt; nhiều hơn thế là lỗi.) Thử trên 1366×768 ở 100 % hoặc 1920×1080 ở 150 % nếu máy có.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" (phần `[displays]` ghi kích thước màn hình và cửa sổ).
- [ ] **3. Gõ thường.** Bấm vào vùng terminal, gõ `dir` rồi Enter (bộ gõ tiếng Việt tắt, bàn phím tiếng Anh).
  - Đạt: mỗi chữ hiện ngay, **đúng một lần**, và lệnh chạy ra danh sách thư mục.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" và ghi bàn phím đang dùng.
- [ ] **4. Unikey hoặc EVKey (kiểu Telex).** Bật Unikey hoặc EVKey, gõ `aa dd tieengs`.
  - Đạt: ra `â đ tiếng`, mỗi ký tự một lần, không thừa ký tự lạ. (Unikey/EVKey ở chế độ mặc định gõ rồi xoá lùi để sửa dấu; chỉ kết quả cuối cùng cần đúng.) Đây là bước quan trọng nhất của vòng này.
  - Nếu hỏng (chữ lặp đôi hoặc ký tự rác): chạy "ShellX – Chẩn đoán" khi bộ gõ còn đang chạy (phần `[keyboard]` ghi tên bộ gõ) và ghi bạn gõ ra gì.
- [ ] **5. Bộ gõ Telex có sẵn của Windows.** Tắt Unikey/EVKey, bật bàn phím Vietnamese Telex của Windows, gõ lại `aa dd tieengs`.
  - Đạt: ra `â đ tiếng`, như bước 4; chữ đang soạn nằm ngay tại con trỏ.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" và ghi bạn gõ ra gì.
- [ ] **6. Cuộn.** Chạy `1..500`. Kéo lên chậm bằng touchpad (hai ngón), rồi lăn chuột.
  - Đạt: touchpad cuộn được từng vài dòng (cuộn chậm thì nhích ít, không đứng yên); chuột cuộn 3 dòng mỗi nấc; cuộn xuống đáy thì về lại dấu nhắc.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" và ghi bạn dùng touchpad hay chuột.
- [ ] **7. Dán.** (a) Chép **một dòng** chữ ở Notepad, nhấp chuột phải vào terminal. (b) Chép **ba dòng**, dán lại (chuột phải hoặc `Ctrl+Shift+V`).
  - Đạt: (a) dán ngay một lần, không hỏi. (b) hiện thanh hỏi "Dán 3 dòng? Mỗi dòng sẽ chạy ngay như một lệnh." (Enter để dán, Esc để hủy); Esc hủy và không có gì chạy; làm lại rồi Enter thì dán đúng ba dòng.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" và ghi cách bạn dán.
- [ ] **8. Chia khung và đóng.** `Alt+Shift+=` chia khung sang phải; sau đó `Alt+F4`.
  - Đạt: khung được chia đôi, gõ vào được khung đang chọn; `Alt+F4` đóng cửa sổ ShellX (không phải việc khác). Mở lại ShellX để làm tiếp.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" và ghi phím nào không chạy.
- [ ] **9. Đổi shell.** `Ctrl+,` (Cài đặt) › **Terminal**: chọn Command Prompt (hoặc shell khác trong danh sách), đóng Cài đặt (`Esc`), `Ctrl+Shift+T`.
  - Đạt: tab mới chạy shell vừa chọn (Command Prompt hiện `C:\…>`), các tab đang mở không đổi. Chọn lại "Tự động" khi xong.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" (phần `[shells]` ghi shell tìm thấy và shell được chọn).
- [ ] **10. Đăng nhập bằng email.** Cài đặt › **Tài khoản** › "Đăng nhập…": gõ địa chỉ email của bạn, "Gửi mã", nhập mã 6 số nhận được.
  - Đạt, **sau khi relay mới đã lên production**: vào được, hộp thoại đóng, thanh bên hiện tên tài khoản và các máy.
  - Đạt, **trước đó**: ngay khi gửi hiện đúng câu "Bản này chưa dùng được cách đăng nhập này." dưới ô email (không phải mã lỗi hay dòng tiếng Anh như `machines.list…`), ShellX vẫn chưa đăng nhập, con trỏ vẫn ở ô email.
  - Nếu hỏng: chạy "ShellX – Chẩn đoán" (phần `[account]` và `[relay]`) và chép nguyên văn câu báo lỗi.

---

## Phần 2: kiểm thêm theo từng mảng (ngắn)

Mỗi mảng có một dòng "Nếu hỏng". Mục nào cần relay mới thì ghi rõ.

### A. Hộp đăng nhập

Mở từ Cài đặt › Tài khoản › "Đăng nhập…" (và một lần từ nút "+" cạnh "MÁY CỦA BẠN" khi chưa đăng nhập).

- [ ] **A1. Mở và gõ.** Đạt: dòng "Chưa có tài khoản? Lần đăng nhập đầu tiên sẽ tạo tài khoản cho bạn." dưới tiêu đề; con trỏ đã ở ô "Địa chỉ email"; gõ ngay được, mỗi chữ đúng một lần; `Ctrl+V` và `Shift+Insert` dán được địa chỉ; `Ctrl+A`, Backspace và hai mũi tên chạy đúng.
- [ ] **A2. Bộ gõ tiếng Việt.** Bật Unikey/EVKey/Telex của Windows, gõ một địa chỉ có "ex" (thành "ẽ"). Đạt: dưới ô hiện "Địa chỉ email này chưa đúng." và "Gửi mã" mờ đi; bấm (hoặc chạm touchpad) vào "Gửi mã" đang mờ rồi gõ tiếp: chữ vẫn vào ô email. Tắt bộ gõ, sửa lại: câu báo mất, "Gửi mã" sáng lên.
- [ ] **A3. Phím Tab.** Với địa chỉ đúng: Tab đi ô email → "Gửi mã" → ("Tiếp tục với Google", chỉ ở bản có Google) → "Hủy" → lại ô email; Shift+Tab đi ngược và bỏ qua nút đang mờ. Đạt: nút đang giữ phím có viền xanh bao ngoài, không nút nào nhảy hay đổi cỡ; Space trên "Hủy" đóng hộp một lần; mở lại, `Esc` cũng đóng; sau khi đóng gõ `dir` ngay: chữ vào shell mà không cần bấm chuột.
- [ ] **A4. Các tỉ lệ hiển thị.** Hộp ở 100 %, 125 %, 150 %. Đạt: không chữ nào bị cắt, câu dài xuống dòng trong khung, "Gửi mã" và "Xác nhận" thẳng hàng với ô ở trên (lệch tối đa vài điểm ảnh).
- [ ] **A5. Bước nhập mã** (cần relay mới). Đạt: "Đã gửi mã 6 chữ số tới …", con trỏ nằm sẵn trong ô mã; "Gửi lại mã sau N giây" đếm ngược từng giây rồi thành "Gửi lại mã"; gõ mã sai: "Mã chưa đúng. Xem lại email rồi thử lại.", ô mã trống, con trỏ vẫn trong ô; "Dùng email khác" quay về ô email và địa chỉ còn nguyên.
- [ ] **A6. Gửi lại mã rồi dán ngay** (cần relay mới). Làm hai lần: bấm "Gửi lại mã" bằng chuột, rồi bằng chạm nhẹ trên touchpad. Mỗi lần: sang thư mới, chép mã, quay lại bấm `Ctrl+V` ngay, không bấm vào ô. Đạt: mã hiện trong ô và tự đăng nhập (không cần "Xác nhận"), thử cả dạng "123 456"; hiện "Đang đăng nhập…", hộp tự đóng, thanh bên hiện các máy, phím gõ vào shell.
- [ ] **A7. Khi server kết thúc phiên** (cần đăng nhập được; thu hồi máy này từ một máy khác). Đạt: không hộp thoại nào tự bật lên, phím đang gõ vẫn vào shell; chân thanh bên hiện "Phiên đăng nhập đã hết hạn." với nút "Đăng nhập lại", Cài đặt › Tài khoản cũng vậy; bấm nút thì hộp mở; đăng nhập lại xong thì dòng báo mất.
- [ ] **A8. Nút "+" khi đã đăng nhập.** Đạt: danh sách nói "ShellX cho Mac hiện chưa nhận kết nối từ máy tính Windows. …" (thêm bước "Đăng nhập ShellX trên Mac …" nếu tài khoản chưa có Mac); không dòng Mac nào có nút xin quyền truy cập; một PC Windows không bao giờ có.

Nếu hỏng: chạy "ShellX – Chẩn đoán" ngay sau khi hộp còn ở trạng thái lỗi, chép nguyên văn câu báo lỗi.

### B. Shell, cuộn, chuột, dán (Phần A)

- [ ] **B1. Tab đầu.** Cài mới chưa có cài đặt: tab đầu hiện dấu nhắc trong khoảng 3 giây. `(Get-Process -Id $PID).Path` cho `…\PowerShell\7\pwsh.exe` (hoặc đường dẫn Store) nếu máy có PowerShell 7, không thì `…\System32\…\powershell.exe`. `cd` vào thư mục tên tiếng Việt: thẻ phiên hiện đúng tên; trong repo git thì hiện nhánh trong khoảng 2 giây.
- [ ] **B2. Tra cứu chậm.** Trong cmd: `set PATH=\\192.0.2.1\x;%PATH%` rồi chạy ShellX từ cmd đó. Đạt: cửa sổ hiện trong khoảng 2 giây, tab đầu là Windows PowerShell, cửa sổ vẫn phản hồi; mở Cài đặt › Terminal ngay thì lúc đầu chỉ có "Tự động" và dòng lệnh tùy chỉnh, rồi danh sách shell hiện ra; tab mở sau đó là PowerShell 7 (nếu có). `cd` vào một thư mục chia sẻ đang offline: cửa sổ vẫn phản hồi.
- [ ] **B3. Cài đặt › Terminal.** Chọn Command Prompt rồi `Ctrl+Shift+T`: tab mới là Command Prompt, các tab đang mở không đổi. Gõ vào ô dòng lệnh `.\pwsh.exe`: báo "Hãy ghi đường dẫn đầy đủ, ví dụ C:\…\pwsh.exe, thay cho .\pwsh.exe." Gõ `cmd.exe /k echo hi`: báo "Sẽ chạy C:\Windows\system32\cmd.exe." và tab mới in `hi`. Chọn lại "Tự động".
- [ ] **B4. Shell không khởi động được.** Trong cmd: `set SHELLX_SHELL=C:\nope.exe` rồi chạy ShellX từ đó: tab chạy PowerShell với dòng "Không khởi động được nope.exe, đang dùng …" (bản tiếng Anh: "nope.exe couldn't start, so … is running instead."). Rồi `set SHELLX_SHELL="` (một dấu ngoặc kép): ô báo "SHELLX_SHELL: Thiếu dấu ngoặc kép đóng." với hai nút "Thử lại" và "Mở Command Prompt"; một chữ cái bất kỳ thử lại và câu cũ trở lại; `Alt+Space` mở menu hệ thống; `Ctrl+Shift+W` đóng ô; "Mở Command Prompt" chạy Command Prompt trong ô.
- [ ] **B5. Cuộn trong chương trình toàn màn hình.** Trong `less` (Git Bash hoặc WSL) bánh xe cuộn trang; trong `vim` nó di con trỏ; sau `:set mouse=a` thì bánh xe không làm gì thêm. Nếu Windows đặt "cuộn một màn hình mỗi nấc" thì một nấc là một màn hình.
- [ ] **B6. Chuột.** Chia khung, bấm khung trái. Chuột phải lên khung phải: **chỉ chuyển tiêu điểm**, không dán; chuột phải lần nữa: dán đúng một lần. Có vùng chọn thì chuột phải **chép**. Chuột giữa chỉ chuyển tiêu điểm. Mở menu "+ ▾" hoặc menu `?` rồi chuột phải vào terminal: menu đóng và không dán gì.
- [ ] **B7. Thanh dán nhiều dòng.** Chép 3 dòng ở Notepad, chuột phải trong Command Prompt: thanh "Dán 3 dòng? …". Esc hủy; `Ctrl+Shift+V` rồi Enter dán đúng ba dòng; khi thanh đang hiện, gõ một chữ: thanh biến mất và chữ được gõ. Một dòng có xuống dòng ở cuối dán ngay.
- [ ] **B8. Thanh tiêu đề.** Không có ô tìm kiếm và không có chuông. Kéo từ giữa thanh để dời cửa sổ được; Snap layouts hoạt động. `Alt+F4` đóng cửa sổ khi đang ở trong terminal.
- [ ] **B9. Xin quyền truy cập khi mất mạng.** Tắt mạng rồi xin quyền tới một máy (cần máy hiện nút này): bảng báo "Không tới được relay.shellx.pro" (hoặc tương tự), không có mã và không có chữ thô của server.

Nếu hỏng: chạy "ShellX – Chẩn đoán" (phần `[shells]`, `[state]`) và ghi chính xác bước.

### C. Log, hộp thoại báo lỗi, `--crash-test panic` và `native`

Không làm `window` ở đây (xem mục H).

- [ ] **C1. Log.** Mở `%LOCALAPPDATA%\ShellX\native\logs\shellx.log`. Đạt: dòng đầu của lần chạy là `… ShellX 1.7.0 starting on Windows 10.0.<build>`, rồi các dòng `Using GPU:` và `Created device with Direct3D …`, rồi `render mode: standard (default)` và `first frame drawn in standard display mode`. Nếu mở hai ShellX cùng lúc, dòng của cái thứ hai kết thúc bằng `another ShellX is running`. Tìm ký tự `@` và mã đăng nhập của bạn trong file: không có.
- [ ] **C2. `--crash-test panic`.** Trong cmd mới: `start /wait "" "%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe" --crash-test panic`. Đạt: **một** hộp "ShellX gặp lỗi và đã lưu chi tiết vào: …crash.….txt" (ghi lại hộp có nổi lên trên cùng không); Yes mở Explorer với file được chọn (kể cả khi tên tài khoản Windows có dấu hoặc dấu cách). File `crash.*.txt` có `message:`, `location:` (…`ui\app.rs`…), `thread: … (main: yes)`, dòng `exe base: 0x…`, các dòng khung `0x…`, và dòng cuối `then: panic in a function that cannot unwind (the process aborts)`. Trong cmd, `echo %ERRORLEVEL%` cho `-1073740791`. Lần mở ShellX kế tiếp vẫn ghi `render mode: standard (default)`.
- [ ] **C3. `--crash-test native`.** Như trên với `native`. Đạt: một hộp của ShellX nêu `crash-native.*.txt`; file có `exception: 0xC0000005`, `address:`, `module: …\shellx-desktop.exe +0x…`, `thread:`. Ghi lại: Windows có hiện thêm hộp của nó không, và cửa sổ bị đơ bao lâu (tối đa khoảng 5 giây). Lần mở kế tiếp vẫn là chế độ thường.
- [ ] **C4. Cửa sổ vẫn dùng được sau khi đổi cỡ/đổi màn hình (tuỳ chọn).** Nhấn Win+Ctrl+Shift+B khi ShellX đang mở. Đạt: cửa sổ tiếp tục vẽ (một khung hình đen là chấp nhận được); log có `DirectX device lost detected` và `DirectX devices successfully recreated`, không có file crash mới. Nếu cửa sổ trắng mãi và log có `failed to recover`, hoặc ShellX hiện hộp báo lỗi với `the GPU device was lost and the window could not recover it`: gửi file.
- [ ] **C5. Báo cáo sau khi crash.** Chạy "ShellX – Chẩn đoán" sau C2: phần `[crash files]` liệt kê file crash và có dòng `windows error event:` với `c0000409` (suy ra, chưa chắc). Ghi lại phần đường dẫn thư mục người dùng đọc được hay hiện `�`.

Nếu hỏng (không có hộp, không có file): ghi "không có hộp" hoặc "không có file", chạy "ShellX – Chẩn đoán" và kiểm `%TEMP%` có file `crash*.txt` không (nếu thư mục log không ghi được, file nằm ở đó).

### D. Cài đặt › Hiển thị

- [ ] **D1. Chạy thường.** Cài đặt cuộn xuống mục **Hiển thị** (nằm dưới Terminal): đọc "Chế độ hiển thị thường", không có nút. Dòng đầu của mục Giới thiệu (About) là `ShellX 1.7.0 (<nhãn> <10 ký tự đầu của commit>)`.
- [ ] **D2. Biến môi trường.** Thoát ShellX. Trong cmd: `set GPUI_DISABLE_DIRECT_COMPOSITION=1` rồi `start "" "%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe"`. Đạt: Hiển thị đọc "Chế độ hiển thị tương thích" kèm câu nói về biến `GPUI_DISABLE_DIRECT_COMPOSITION` và **không có nút**; log có `render mode: compatible (set by GPUI_DISABLE_DIRECT_COMPOSITION)`; cửa sổ vẽ bình thường. Thoát ShellX và đóng cmd đó.

Nếu hỏng: chạy "ShellX – Chẩn đoán" (phần `[gpu]` ghi chế độ đang dùng).

### E. "ShellX – Chẩn đoán" và nội dung báo cáo

- [ ] **E1. Từ Start.** Chạy "ShellX – Chẩn đoán". Đạt: vài giây (tối đa khoảng 70 giây) không thấy gì, rồi Explorer mở ra với `diagnostics.<giờ>.<số>.txt` đã chọn; **chỉ một** file mới được tạo. Ghi lại số giây phải chờ.
- [ ] **E2. Nội dung.** Mở file bằng Notepad. Đạt: có đủ 12 phần `[app]`, `[windows]`, `[cpu]`, `[displays]`, `[gpu]`, `[keyboard]`, `[shells]`, `[state]`, `[account]`, `[relay]`, `[crash files]`, `[log: last 200 lines]`; không còn chữ `not run yet`; `[app]` ghi `version: ShellX 1.7.0 (<nhãn> <commit>)`; `[gpu]` có đúng một dòng `GPUI would use this one` và dòng `dwm timing: period …`; `[keyboard]` gọi tên Unikey/EVKey nếu đang chạy; `[shells]` có danh sách shell tìm thấy, `chosen`, và các dòng `… start: ok`, `… first output: ok` (với PowerShell còn echo, unicode, resize); `[crash files]` có dòng `windows error events:` hoặc các sự kiện. Tìm ký tự `@` và địa chỉ email của bạn: chỉ được thấy `<email>`, không thấy địa chỉ thật.
- [ ] **E3. Từ menu trợ giúp.** Menu `?` ở chân thanh bên có thứ tự: Cài đặt…, Kiểm tra cập nhật, Tạo báo cáo chẩn đoán, Tài liệu, GitHub. Bấm "Tạo báo cáo chẩn đoán" **một lần** rồi gõ vào terminal trong lúc báo cáo chạy: chữ vẫn hiện. Đạt: Explorer mở với đúng một file mới; trong file, dòng chế độ hiển thị khớp với chế độ bạn đang dùng. Log không có dòng `warn` về "diagnostics report did not start".
- [ ] **E4. Từ dòng lệnh.** Trong cmd: `start /wait "" "%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe" --version` in `shellx-desktop 1.7.0`. Với `--diagnose --no-open` thay cho `--version` in `Diagnostics report: <đường dẫn>` và không mở Explorer. (Không có `start /wait` thì dấu nhắc quay lại trước và chữ hiện sau: bình thường, xem README, mục Command line.)
- [ ] **E5. Nếu shell của bạn là PowerShell.** Sau khi tạo báo cáo, mở một PowerShell mới và bấm mũi tên lên: ghi lại có thấy dòng `Write-Output ('cols-' + …)` trong lịch sử không.

Nếu hỏng: gửi file báo cáo (nếu có) và ghi phần nào thiếu.

### F. Bộ cài: AppMutex, hai mục Start, thông tin phiên bản

- [ ] **F1. Thông tin phiên bản.** Trong PowerShell: `(Get-Item "$env:LOCALAPPDATA\Programs\ShellX Native\shellx-desktop.exe").VersionInfo | Format-List *`. Đạt: đủ các trường, kể cả `CompanyName` (Explorer, tab Chi tiết, **không** hiện Company, nên dùng lệnh này): File description ShellX, ProductName ShellX, FileVersion `1.7.0.0`, ProductVersion `1.7.0`, OriginalFilename `shellx-desktop.exe`. Chi tiết của file cài đặt: ShellX Setup, phiên bản `1.7.0.0`.
- [ ] **F2. Không có file PDB.** `dir "%LOCALAPPDATA%\Programs\ShellX Native"` không có file `.pdb`.
- [ ] **F3. AppMutex.** Khi ShellX đang mở, chạy lại file cài. Đạt: hiện câu hỏi "ShellX đã được phát hiện đang chạy…" với OK/Cancel; đóng ShellX, bấm OK, cài tiếp. Câu hỏi tương tự khi gỡ cài đặt (Cài đặt › Ứng dụng) lúc ShellX đang chạy. Mở nhiều cửa sổ ShellX cùng lúc vẫn được (mutex chỉ phục vụ bộ cài).
- [ ] **F4. Hai mục Start.** Có "ShellX" và "ShellX – Chẩn đoán" (cả hai biến mất sau khi gỡ cài đặt).
- [ ] **F5. Chạy với quyền quản trị.** Mở ShellX bằng "Run as administrator", rồi mở ShellX thường: dòng `render mode:` của lần thứ hai kết thúc bằng `another ShellX is running`.

Nếu hỏng: ghi lại câu hỏi hoặc lỗi nguyên văn; nếu app đã cài được thì chạy "ShellX – Chẩn đoán".

### G. Gõ tiếng Việt và tên tiếng Việt (ngoài bước 4 và 5)

- [ ] **G1. Emoji.** Bấm Win+. (dấu chấm), chọn một emoji. Đạt: emoji vào terminal **đúng một lần**.
- [ ] **G2. Thư mục tên tiếng Việt.** `mkdir "$HOME\Tài liệu"`, `cd` vào đó. Đạt: thẻ phiên hiện `~\Tài liệu` đúng dấu và dấu cách, không có `%C3` hay `%20`; trong thư mục git thì dòng nhánh hiện `⎇` đúng ký tự (không phải ô vuông).

Nếu hỏng: chạy "ShellX – Chẩn đoán" khi bộ gõ còn chạy (`[keyboard]` ghi tên bộ gõ và bố cục bàn phím) và ghi bạn đã gõ gì, ra gì.

### H. Làm cuối cùng: `--crash-test window`, rồi trả về chế độ thường

- [ ] **H1. Cứu bằng chế độ tương thích.** Thoát mọi ShellX. Trong cmd mới: `"%LOCALAPPDATA%\Programs\ShellX Native\shellx-desktop.exe" --crash-test window`. Đạt: không hộp thoại; **một** cửa sổ mở ra (chế độ tương thích) và dùng được; log có `relaunched in compatible display mode`, rồi `render mode: compatible (the standard mode could not open the window)` và `first frame drawn in compatible display mode`; `type %LOCALAPPDATA%\ShellX\native\render.json` in `{"mode":"compatible"}`.
- [ ] **H2. Chế độ được nhớ.** Thoát và mở ShellX từ Start. Đạt: cửa sổ mở, log có `render mode: compatible (remembered)`. Cài đặt › Hiển thị đọc "Chế độ hiển thị tương thích" kèm câu "ShellX dùng chế độ này vì chế độ thường không mở được cửa sổ trên máy này." và nút **"Thử lại chế độ hiển thị thường"**.
- [ ] **H3. Trả về thường.** Bấm nút đó. Đạt: nút đổi thành "Áp dụng khi mở lại ShellX."; `type …\render.json` in `{"mode":"standard"}`. Thoát ShellX, mở lại từ Start: Hiển thị đọc "Chế độ hiển thị thường" và dòng log mới nhất là `render mode: standard (default)`.

Chỉ sau H3 mới đánh giá các mục còn lại (hiển thị, tốc độ, độ nét). Nếu máy không có Cài đặt › Hiển thị (bản quá cũ), xoá `%LOCALAPPDATA%\ShellX\native\render.json`.

Nếu hỏng (ShellX báo không mở được cửa sổ ở mọi lần mở): xoá `%LOCALAPPDATA%\ShellX\native\render.json`, chạy "ShellX – Chẩn đoán" và gửi cả `start-failed.*.txt`. Nếu cửa sổ trắng trong khi log đã ghi `first frame drawn`: thoát, trong cmd `set GPUI_DISABLE_DIRECT_COMPOSITION=1` rồi chạy ShellX từ cmd đó, và báo lại.

---

## Kiểm sau

Các mục của danh sách cũ ([G1-G3-CHECKLIST.md](G1-G3-CHECKLIST.md), 45 mục) mà 10 bước và Phần 2 chưa bao gồm. Chưa cần làm trong vòng này; làm khi có bản phát hành thật. Khi làm, nhớ rằng hộp đăng nhập giờ là **email và mã 6 số** (không còn mật khẩu).

**Gõ, hiển thị, độ trễ**
- [ ] Độ nét ở 150 % và 200 %: chữ terminal và biểu tượng sắc nét, không mờ, không lệch ô.
- [ ] Độ trễ so với Windows Terminal bằng Typometer (README, mục "Latency procedure"): ghi median và p95 của cả hai.
- [ ] Narrator (dự kiến không đọc được lưới terminal): chỉ cần `Insert+T` đọc được `<dòng con trỏ> - ShellX` khi Narrator đang chạy; tắt Narrator thì tiêu đề không có chữ trên màn hình.
- [ ] Hai màn hình tỉ lệ khác nhau: cửa sổ tạo ở màn hình phụ vẫn vừa vùng làm việc.

**Cài đặt và dùng thật**
- [ ] Cài chung với ShellX Flutter: Flutter đang chạy, cài bản mới, Flutter không bị tắt; Start có cả hai. Gỡ bản mới: Flutter còn nguyên, `%LOCALAPPDATA%\ShellX\native` còn lại.
- [ ] Cài đè lên bản trước (ví dụ 1.5.3): dữ liệu cũ vẫn còn, không hỏi quyền quản trị.
- [ ] Phiên, tab và chia khung: `Ctrl+Shift+N` phiên mới, `Ctrl+Shift+T` tab mới, `Alt+Shift+-` chia dưới, `Alt+Mũi tên` đổi khung, `Ctrl+Shift+B` ẩn/hiện thanh bên; khung đang chọn có viền rõ.
- [ ] Thoát shell cuối: `exit` ở mọi khung, chỉ khung đó đóng; khung cuối của tab cuối mở tab PowerShell mới (app không thoát).
- [ ] Chọn và `Ctrl+Shift+C` dán vào Notepad đúng chữ; `Ctrl+C` chép khi có vùng chọn; `ping -t 127.0.0.1` rồi `Ctrl+C` dừng lệnh.
- [ ] Ngôn ngữ theo Windows (Anh/Việt, hai chiều, đăng xuất rồi đăng nhập Windows); `SHELLX_LANG=en|vi` ghi đè.
- [ ] Nút cửa sổ (thu nhỏ, phóng to, đóng; Snap layouts trên Windows 11).
- [ ] Back / Forward giữa hai phiên, kể cả sau khi đóng một phiên.
- [ ] Bấm từng nút: tab, ×, ba nút trên thanh tab, menu "+ ▾", menu `?`, viên thuốc cập nhật; `Esc` khi menu mở không tới shell.
- [ ] Từ 8 tab trở lên trong khung nửa màn hình: tab giữ bề rộng, thanh tab cuộn ngang, ba nút bên phải luôn hiện, × đóng đúng tab.
- [ ] oh-my-posh / starship: chỉ báo lỗi của theme hiện sau `cmd /c exit 1`; profile không định nghĩa `prompt` vẫn có dấu nhắc `PS <đường dẫn>> ` và thẻ vẫn cập nhật.
- [ ] `--smoke` từ thư mục cài: ``$p = Start-Process "$env:LOCALAPPDATA\Programs\ShellX Native\shellx-desktop.exe" -ArgumentList '--smoke' -Wait -PassThru -RedirectStandardOutput "$env:TEMP\shellx-smoke.txt" -RedirectStandardError "$env:TEMP\shellx-smoke-err.txt"; $p.ExitCode`` in `0`, và `shellx-smoke.txt` có `smoke: PASS …` (nó luôn tự chạy Windows PowerShell, bất kể lựa chọn trong Cài đặt).
- [ ] Ổ mạng hoặc thư mục chia sẻ (`cd Z:\`, `cd \\máy-chủ\thư-mục`): giao diện không đơ, thẻ phiên hiện đường dẫn.

**Mac từ xa** (chỉ khi một bản ShellX cho Mac nhận kết nối từ PC; hôm nay chưa có)
- [ ] Xin quyền truy cập: mã 6 số giống nhau trên hai máy, duyệt trên Mac, Windows hiện "Đã được chấp thuận".
- [ ] Mở từ bảng ghép cặp và từ thanh bên; "Mở" lần hai mở shell mới trên Mac; file `core\tickets\invite-*.uri` bị xoá sau lần nối đầu.
- [ ] Telex vào Mac (byte chính xác): trên Mac `cat | xxd`, gõ `tiếng Việt` bằng Telex của Windows, Enter, `Ctrl+D`: `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74 0a`.
- [ ] Dán có `ESC[201~`: ``Set-Clipboard "a`e[201~b`nc"``, trên Mac `cat -v`, dán: `ab` rồi `c`, không hiện `^[[201~`.
- [ ] Đổi cỡ (`stty size` đổi theo), chia khung và `Ctrl+Shift+T` trong khung Mac tạo shell mới trên Mac; `Ctrl+Shift+N` luôn mở phiên cục bộ.
- [ ] Mất mạng và nối lại: nhãn "đang kết nối lại…" rồi "ngoại tuyến", gõ chỉ hiện "Mất kết nối, tạm ngừng nhập", tự nối lại trong khoảng 30 giây.
- [ ] `Ctrl+Shift+W` trong khung Mac chỉ tách ra (shell còn chạy trên Mac); `exit` trong khung Mac chỉ đóng khung đó.
- [ ] Đăng xuất đóng mọi tab Mac; đăng nhập lại rồi "Mở" nối lại được.
- [ ] Dán quá lớn vào Mac (``Set-Clipboard ("a" * 9MB)``): hiện "Nội dung dán quá lớn (tối đa 8 MB)", khung vẫn dùng được.
- [ ] Nhìn bằng mắt ở 100 % và 150 %: nhãn trạng thái giữa khung và dòng báo ở đáy rõ ràng.
