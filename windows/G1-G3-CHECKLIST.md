# ShellX Windows: danh sách kiểm G1 và G3

Việc của bạn trên một máy Windows 10 1809+ hoặc Windows 11. Đánh dấu `[x]` khi xong, ghi kết quả (đạt / hỏng + ghi chú, ảnh chụp nếu hỏng) vào ledger `docs/superpowers/ledgers/native-desktop.md` hoặc nhắn lại cho Claude.

## Run id (điều phối viên cập nhật mục này)

Run xanh mới nhất lúc viết: **39176242679** (nhánh `shellx/l6-windows`). Lấy bản mới nhất bằng:
`gh run list -R lephus/shellx --branch shellx/l6-windows --workflow shellx-windows.yml -L 1`

```
gh run download 39176242679 -R lephus/shellx -n shellx-desktop
gh run download 39176242679 -R lephus/shellx -n ShellX-Setup-2.0.0-sprint
```

Bản cài chưa ký: SmartScreen hiện "Unknown publisher", chọn More info, rồi Run anyway.

## G1: gõ tiếng Việt, độ nét, độ trễ, trình đọc màn hình

Dùng `shellx-desktop.exe` (bản portable) hoặc bản đã cài. Mở PowerShell trong app.

- [ ] **Telex có sẵn của Windows**: bật bộ gõ Telex của Windows, gõ `tiếng Việt`. Đạt: chữ đã chốt đúng, không dư ký tự, không mất dấu; cửa sổ gợi ý/preedit nằm ngay tại con trỏ. Báo: ghi lại nếu cửa sổ gợi ý lệch vị trí.
- [ ] **Unikey**: gõ `tiếng Việt` (Telex). Đạt như trên.
- [ ] **EVKey**: gõ `tiếng Việt`. Đạt như trên.
- [ ] **Độ nét 150 %**: Settings > Display > Scale 150 %, đăng xuất/đăng nhập nếu cần. Đạt: chữ terminal và icon sắc nét, không mờ, không lệch ô.
- [ ] **Độ nét 200 %**: như trên với 200 %. Đạt như trên.
- [ ] **Độ trễ**: làm theo mục "Latency procedure" trong `windows/README.md` (Typometer, ShellX so với Windows Terminal, cùng máy, cùng cỡ chữ, 5 lần mỗi bên). Đạt: ghi median và p95 của cả hai; mục tiêu ShellX không tệ hơn Windows Terminal đáng kể. Báo: bảng 2 dòng.
- [ ] **Narrator (dự kiến KHÔNG đạt)**: bật Narrator (Win+Ctrl+Enter), duyệt app. Dự kiến: không đọc được lưới terminal và các nút (GPUI chưa có UI Automation). Chỉ cần xác nhận: `Insert+T` đọc được tiêu đề cửa sổ dạng `<dòng hiện tại> - ShellX`. Báo: ghi "đúng dự kiến" hoặc có gì khác.

## G3: cài đặt và dùng thật

### Cài chung với ShellX Flutter

- [ ] Có sẵn ShellX Flutter đã cài và **đang chạy**. Chạy `ShellX-Setup-2.0.0-sprint.exe`. Đạt: cài xong không hỏi quyền quản trị, ShellX Flutter vẫn chạy (không bị tắt), Start menu có cả "ShellX" (Flutter) lẫn "ShellX 2 (thử nghiệm)".

### Terminal cục bộ

- [ ] **Tab và chia khung**: `Ctrl+Shift+T` mở tab; `Alt+Shift+=` chia phải; `Alt+Shift+-` chia dưới; `Alt+Mũi tên` đổi khung. Đạt: bố cục đúng, khung đang chọn có viền rõ.
- [ ] **Thoát shell cuối**: gõ `exit` ở mọi khung. Đạt: chỉ khung đó đóng, khung bên cạnh chiếm chỗ; khung cuối của tab cuối mở tab PowerShell mới (app không thoát).
- [ ] **Chọn và Ctrl+C**: chọn một đoạn chữ bằng chuột, `Ctrl+Shift+C` rồi dán vào Notepad (đạt: đúng chữ). Chọn lại, `Ctrl+C` cũng sao chép khi đang có vùng chọn.
- [ ] **Ctrl+C ngắt lệnh**: chạy `ping -t 127.0.0.1`, không chọn gì, bấm `Ctrl+C`. Đạt: lệnh dừng.
- [ ] **Dán nhiều dòng**: sao chép 3 dòng chữ từ Notepad, `Ctrl+Shift+V` (hoặc `Shift+Insert`). Đạt: dán nguyên 3 dòng, không tự chạy dòng nào ngoài ý muốn.

### Đăng nhập và Mac từ xa (nếu bản build có)

- [ ] **Đăng nhập**: mở Settings (`Ctrl+,`) hoặc màn hình đăng nhập, đăng nhập bằng tài khoản ShellX (nhập mật khẩu trực tiếp trong app, không gửi qua chat). Đạt: hiện tên tài khoản.
- [ ] **Mac xuất hiện**: sidebar liệt kê Mac của bạn (Mac đang chạy ShellX và online). Đạt: thấy tên Mac, trạng thái online.
- [ ] **Xin quyền truy cập** (cần bản có giao diện ghép cặp, Task 12b): bấm "Xin quyền truy cập" ở Mac. Đạt: hiện mã 6 số dạng `123 456` và mã thiết bị của bạn; trên Mac hiện yêu cầu có **cùng mã**; bấm duyệt trên Mac; bên Windows hiện "Đã được duyệt". Báo: nếu mã khác nhau, từ chối trên Mac và báo ngay.
- [ ] **Mở terminal Mac** (cần bản có giao diện terminal từ xa, Task 13b): bấm Mở. Đạt: thấy shell của Mac trong tab mới.
- [ ] **Gõ tiếng Việt vào Mac**: trong terminal Mac gõ `tiếng Việt`. Đạt: Mac nhận đúng `tiếng Việt` (thử `echo tiếng Việt`).
- [ ] **Mất mạng**: rút mạng (tắt Wi-Fi). Đạt: khung hiện "đang kết nối lại…" (hoặc "ngoại tuyến"), gõ phím không bị gửi đi, app không đơ. Bật mạng lại: tự kết nối lại và dùng tiếp được.

### Gỡ cài đặt

- [ ] Gỡ "ShellX 2" trong Settings > Apps. Đạt: ShellX Flutter vẫn còn, vẫn chạy, mục Start menu của nó còn nguyên; thư mục `%LOCALAPPDATA%\ShellX\native` còn lại (dữ liệu của bạn).
