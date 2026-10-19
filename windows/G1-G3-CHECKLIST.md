# ShellX Windows: danh sách kiểm G1 và G3

Việc của bạn trên một máy Windows 10 1809+ hoặc Windows 11. Đánh dấu `[x]` khi xong, ghi kết quả (đạt / hỏng + ghi chú, ảnh chụp nếu hỏng) vào ledger `docs/superpowers/ledgers/native-desktop.md` hoặc nhắn lại cho Claude.

## Run id (điều phối viên cập nhật mục này)

Run mới nhất lúc viết: **39210284444** (head `c2087a601d`, nhánh `shellx/l6-windows`, cả 4 job xanh; commit sau đó chỉ sửa mục này; điều phối viên sẽ thay bằng run xanh mới hơn trong báo cáo cuối nếu có). Lấy run mới nhất bằng:
`gh run list -R lephus/shellx --branch shellx/l6-windows --workflow shellx-windows.yml -L 1`

```
gh run download 39210284444 -R lephus/shellx -n shellx-desktop
gh run download 39210284444 -R lephus/shellx -n ShellX-Setup-2.0.0-sprint
```

Artifact chỉ giữ 14 ngày; hết hạn thì nhờ điều phối viên chạy lại workflow.

Bản cài chưa ký: SmartScreen hiện "Unknown publisher", chọn More info, rồi Run anyway.

## G1: gõ tiếng Việt, độ nét, độ trễ, trình đọc màn hình

Dùng `shellx-desktop.exe` (bản portable) hoặc bản đã cài. Mở PowerShell trong app.

- [ ] **Telex có sẵn của Windows (TSF)**: bật bàn phím Vietnamese Telex của Windows, gõ `tiếng Việt` trong PowerShell. Đạt: chữ đã chốt đúng, không dư ký tự, không mất dấu; cửa sổ gợi ý/preedit nằm ngay tại con trỏ. Báo: ghi lại nếu cửa sổ gợi ý lệch vị trí. (Kiểm byte chính xác ở mục G3 "Telex vào Mac".)
- [ ] **Unikey**: gõ `tiếng Việt` (Telex). Đạt: chữ cuối cùng trên màn hình đúng, không mất, không lặp ký tự. Lưu ý: ở chế độ mặc định (SendInput/xoá lùi) Unikey gõ rồi xoá lùi để sửa dấu, nên đây là đặc tính của công cụ, không phải lỗi app; chỉ chữ cuối cùng cần đúng.
- [ ] **EVKey**: như Unikey (cùng lưu ý, cùng tiêu chí đạt).
- [ ] **Độ nét 150 %**: Settings > Display > Scale 150 %, đăng xuất/đăng nhập nếu cần. Đạt: chữ terminal và icon sắc nét, không mờ, không lệch ô.
- [ ] **Độ nét 200 %**: như trên với 200 %. Đạt như trên.
- [ ] **Độ trễ**: làm theo mục "Latency procedure" trong `windows/README.md` (Typometer, ShellX so với Windows Terminal, cùng máy, cùng cỡ chữ, 5 lần mỗi bên). Đạt: ghi median và p95 của cả hai; mục tiêu ShellX không tệ hơn Windows Terminal đáng kể. Báo: bảng 2 dòng.
- [ ] **Narrator (dự kiến KHÔNG đạt)**: bật Narrator (Win+Ctrl+Enter), duyệt app. Dự kiến: không đọc được lưới terminal và các nút (GPUI chưa có UI Automation). Chỉ cần xác nhận: khi Narrator đang chạy (Narrator tự bật chế độ trình đọc màn hình, app kiểm tra mỗi giây), `Insert+T` đọc được tiêu đề cửa sổ dạng `<dòng con trỏ, nếu trống thì tiêu đề terminal> - ShellX` (chỉ khung đang chọn ghi tiêu đề). Tắt Narrator: tiêu đề chỉ còn `<tiêu đề terminal> - ShellX` hoặc `ShellX`, KHÔNG có chữ trên màn hình (xem thanh tác vụ / Alt+Tab). Cần đọc terminal nhiều: dùng Windows Terminal. Báo: ghi "đúng dự kiến" hoặc có gì khác.

## G3: cài đặt và dùng thật

### Cài chung với ShellX Flutter

- [ ] Có sẵn ShellX Flutter đã cài và **đang chạy**. Chạy `ShellX-Setup-2.0.0-sprint.exe`. Đạt: cài xong không hỏi quyền quản trị, ShellX Flutter vẫn chạy (không bị tắt), Start menu có cả "ShellX" (Flutter) lẫn "ShellX 2 (thử nghiệm)".

### Terminal cục bộ

- [ ] **Tab và chia khung**: `Ctrl+Shift+T` mở tab; `Alt+Shift+=` chia phải; `Alt+Shift+-` chia dưới; `Alt+Mũi tên` đổi khung. Đạt: bố cục đúng, khung đang chọn có viền rõ.
- [ ] **Thoát shell cuối**: gõ `exit` ở mọi khung. Đạt: chỉ khung đó đóng, khung bên cạnh chiếm chỗ; khung cuối của tab cuối mở tab PowerShell mới (app không thoát).
- [ ] **Chọn và Ctrl+C**: chọn một đoạn chữ bằng chuột, `Ctrl+Shift+C` rồi dán vào Notepad (đạt: đúng chữ). Chọn lại, `Ctrl+C` cũng sao chép khi đang có vùng chọn.
- [ ] **Ctrl+C ngắt lệnh**: chạy `ping -t 127.0.0.1`, không chọn gì, bấm `Ctrl+C`. Đạt: lệnh dừng.
- [ ] **Dán nhiều dòng**: sao chép 3 dòng chữ từ Notepad, `Ctrl+Shift+V` (hoặc `Shift+Insert`). Đạt: dán nguyên 3 dòng, không tự chạy dòng nào ngoài ý muốn.

### Đăng nhập và ghép cặp

- [ ] **Đăng nhập**: mở Settings (`Ctrl+,`) hoặc ô đăng nhập ở thanh bên, nhập mật khẩu trực tiếp trong app (không gửi qua chat). Đạt: hiện tên tài khoản; sidebar liệt kê Mac đang chạy ShellX và online.
- [ ] **Xin quyền truy cập**: bấm "+" ở đầu danh sách máy (hoặc "Xin quyền truy cập") chọn Mac. Đạt: hiện mã 6 số và mã thiết bị của bạn; Mac hiện **cùng mã**; duyệt trên Mac; Windows hiện "Đã được chấp thuận". Báo: nếu mã khác nhau, từ chối trên Mac và báo ngay.

### Mac từ xa (cần relay v2, ShellX trên Mac đang chạy và đã đăng nhập)

- [ ] **Mở từ bảng ghép cặp**: sau khi được chấp thuận bấm "Mở". Đạt: bảng đóng, tab mới hiện "đang kết nối…" rồi shell của Mac; file `%LOCALAPPDATA%\ShellX\native\core\tickets\invite-*.uri` đã bị xoá.
- [ ] **Mở từ thanh bên**: Mac đã cấp quyền có nút "Mở". Đạt: tab mới dưới nhóm của Mac; bấm "Mở" lần hai mở shell MỚI trên Mac (cửa sổ ShellX trên Mac cũng thấy).
- [ ] **Telex vào Mac (byte chính xác)**: trên Mac chạy `cat | xxd`; bên Windows dùng Telex có sẵn của Windows (TSF), gõ `tiếng Việt` rồi Enter, rồi `Ctrl+D` (`xxd` chỉ in khi gặp EOF; hoặc dùng `od -An -tx1`, in ngay sau Enter). Đạt: đúng `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74 0a`. Với Unikey/EVKey (mặc định xoá lùi) Mac thấy chuỗi `e`, DEL, `ê`...: đây là đặc tính của công cụ, chỉ cần dòng cuối đúng và không mất/lặp ký tự.
- [ ] **Dán có `ESC[201~`**: đưa ký tự ESC thật vào clipboard bằng PowerShell: ``Set-Clipboard "a`e[201~b`nc"`` (`` `e `` là ESC, `` `n `` là xuống dòng). Trên Mac chạy `cat -v`; dán bằng `Ctrl+Shift+V`. Đạt: cả hai dòng tới nơi (`ab` rồi `c`), app XOÁ dấu kết thúc nên `cat -v` KHÔNG hiện `^[[201~` hay chuỗi ESC nào, không lệnh nào tự chạy; kéo chọn + `Ctrl+Shift+C` vẫn sao chép được.
- [ ] **Đổi cỡ và chia khung**: kéo đổi cỡ cửa sổ, `stty size` trên Mac đổi theo. `Alt+Shift+=` / `Alt+Shift+-` trong khung Mac tạo khung Mac mới (shell mới trên Mac); cùng phím trong khung cục bộ ra PowerShell cục bộ; `Ctrl+Shift+T` luôn mở tab cục bộ.
- [ ] **Mất mạng / nối lại**: tắt Wi-Fi của Mac (hoặc thoát ShellX trên Mac). Đạt: nhãn "đang kết nối lại…" (có lý do bên dưới) hoặc "ngoại tuyến"; gõ/Enter/dán chỉ hiện dòng "Mất kết nối, tạm ngừng nhập" và sau khi nối lại không có gì bị gửi trễ; bật lại: tự nối trong khoảng 30 giây, nhãn mất, gõ được; app không đơ. Giới hạn đã biết: chữ gõ trong khoảng 30 giây đầu của một lần relay chập chờn (lúc nhãn chưa hiện) có thể tới trễ.
- [ ] **`Ctrl+Shift+W` trong khung Mac**: khung đóng nhưng chỉ tách ra, shell VẪN chạy trên Mac (ghi chú phát hành: mỗi lần "Mở" thứ hai hoặc chia khung Mac tạo một workspace mới trên Mac; đóng chúng trên Mac). Đạt: đúng như vậy, app không lỗi.
- [ ] **`exit` trong khung Mac**: chỉ khung đó đóng, khung bên cạnh chiếm chỗ; `exit` ở khung cuối của tab cuối: mở tab PowerShell cục bộ mới, app không thoát.
- [ ] **Đăng xuất** (Settings): mọi tab Mac đóng, còn một tab cục bộ; đăng nhập lại rồi "Mở" kết nối lại được.
- [ ] **Bảng đang mở**: mở Settings, thử `Ctrl+Shift+T`: không có tab mới; `Esc` đóng bảng, rồi bàn phím về terminal.
- [ ] **Tiêu đề / Narrator**: Narrator đang chạy, trong khung Mac `Insert+T` đọc `<dòng con trỏ> - ShellX`; Narrator không đọc lưới terminal (đúng dự kiến). Tắt Narrator: tiêu đề không còn dòng con trỏ.
- [ ] **Dán quá lớn vào Mac**: ``Set-Clipboard ("a" * 9MB)`` rồi `Ctrl+Shift+V` trong khung Mac. Đạt: hiện dòng "Nội dung dán quá lớn (tối đa 8 MB)", Mac không nhận gì, khung vẫn dùng được.
- [ ] **Nhìn bằng mắt ở 100 % và 150 %**: nhãn trạng thái ở giữa khung và dòng báo ở đáy khung rõ ràng, không có hiệu ứng sáng/bóng. Báo: ảnh chụp nếu lệch.

### Gỡ cài đặt

- [ ] Gỡ "ShellX 2" trong Settings > Apps. Đạt: ShellX Flutter vẫn còn, vẫn chạy, mục Start menu của nó còn nguyên; thư mục `%LOCALAPPDATA%\ShellX\native` còn lại (dữ liệu của bạn).
