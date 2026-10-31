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

- [ ] **Phiên, tab và chia khung**: `Ctrl+Shift+N` mở phiên (thẻ trong thanh bên) mới; `Ctrl+Shift+T` mở tab terminal mới trong khung đang chọn; `Alt+Shift+=` chia phải; `Alt+Shift+-` chia dưới; `Alt+Mũi tên` đổi khung. Đạt: bố cục đúng, khung đang chọn có viền rõ. (Các nút và menu tương ứng: xem mục "Wave 1 parity" bên dưới.)
- [ ] **Thoát shell cuối**: gõ `exit` ở mọi khung. Đạt: chỉ khung đó đóng, khung bên cạnh chiếm chỗ; khung cuối của tab cuối mở tab PowerShell mới (app không thoát).
- [ ] **Chọn và Ctrl+C**: chọn một đoạn chữ bằng chuột, `Ctrl+Shift+C` rồi dán vào Notepad (đạt: đúng chữ). Chọn lại, `Ctrl+C` cũng sao chép khi đang có vùng chọn.
- [ ] **Ctrl+C ngắt lệnh**: chạy `ping -t 127.0.0.1`, không chọn gì, bấm `Ctrl+C`. Đạt: lệnh dừng.
- [ ] **Dán nhiều dòng**: sao chép 3 dòng chữ từ Notepad, `Ctrl+Shift+V` (hoặc `Shift+Insert`). Đạt: dán nguyên 3 dòng, không tự chạy dòng nào ngoài ý muốn.

### Đăng nhập và ghép cặp

- [ ] **Đăng nhập**: mở Settings (`Ctrl+,`) > Tài khoản > "Đăng nhập…" (hoặc bấm "+" cạnh "Máy của bạn" khi chưa đăng nhập), nhập mật khẩu trực tiếp trong app (không gửi qua chat). Đạt: hiện tên tài khoản; sidebar liệt kê Mac đang chạy ShellX và online.
- [ ] **Xin quyền truy cập**: bấm "+" ở đầu danh sách máy (hoặc "Xin quyền truy cập") chọn Mac. Đạt: hiện mã 6 số và mã thiết bị của bạn; Mac hiện **cùng mã**; duyệt trên Mac; Windows hiện "Đã được chấp thuận". Báo: nếu mã khác nhau, từ chối trên Mac và báo ngay.

### Mac từ xa (cần relay v2, ShellX trên Mac đang chạy và đã đăng nhập)

- [ ] **Mở từ bảng ghép cặp**: sau khi được chấp thuận bấm "Mở". Đạt: bảng đóng, tab mới hiện "đang kết nối…" rồi shell của Mac; file `%LOCALAPPDATA%\ShellX\native\core\tickets\invite-*.uri` đã bị xoá.
- [ ] **Mở từ thanh bên**: Mac đã cấp quyền có nút "Mở". Đạt: tab mới dưới nhóm của Mac; bấm "Mở" lần hai mở shell MỚI trên Mac (cửa sổ ShellX trên Mac cũng thấy).
- [ ] **Telex vào Mac (byte chính xác)**: trên Mac chạy `cat | xxd`; bên Windows dùng Telex có sẵn của Windows (TSF), gõ `tiếng Việt` rồi Enter, rồi `Ctrl+D` (`xxd` chỉ in khi gặp EOF; hoặc dùng `od -An -tx1`, in ngay sau Enter). Đạt: đúng `74 69 e1 ba bf 6e 67 20 56 69 e1 bb 87 74 0a`. Với Unikey/EVKey (mặc định xoá lùi) Mac thấy chuỗi `e`, DEL, `ê`...: đây là đặc tính của công cụ, chỉ cần dòng cuối đúng và không mất/lặp ký tự.
- [ ] **Dán có `ESC[201~`**: đưa ký tự ESC thật vào clipboard bằng PowerShell: ``Set-Clipboard "a`e[201~b`nc"`` (`` `e `` là ESC, `` `n `` là xuống dòng). Trên Mac chạy `cat -v`; dán bằng `Ctrl+Shift+V`. Đạt: cả hai dòng tới nơi (`ab` rồi `c`), app XOÁ dấu kết thúc nên `cat -v` KHÔNG hiện `^[[201~` hay chuỗi ESC nào, không lệnh nào tự chạy; kéo chọn + `Ctrl+Shift+C` vẫn sao chép được.
- [ ] **Đổi cỡ và chia khung**: kéo đổi cỡ cửa sổ, `stty size` trên Mac đổi theo. `Alt+Shift+=` / `Alt+Shift+-` trong khung Mac tạo khung Mac mới (shell mới trên Mac); cùng phím trong khung cục bộ ra PowerShell cục bộ; `Ctrl+Shift+T` trong khung Mac mở thêm một terminal trên chính Mac đó (shell mới trên Mac), trong khung cục bộ mở PowerShell cục bộ; `Ctrl+Shift+N` luôn mở phiên cục bộ.
- [ ] **Mất mạng / nối lại**: tắt Wi-Fi của Mac (hoặc thoát ShellX trên Mac). Đạt: nhãn "đang kết nối lại…" (có lý do bên dưới) hoặc "ngoại tuyến"; gõ/Enter/dán chỉ hiện dòng "Mất kết nối, tạm ngừng nhập" và sau khi nối lại không có gì bị gửi trễ; bật lại: tự nối trong khoảng 30 giây, nhãn mất, gõ được; app không đơ. Giới hạn đã biết: chữ gõ trong khoảng 30 giây đầu của một lần relay chập chờn (lúc nhãn chưa hiện) có thể tới trễ.
- [ ] **`Ctrl+Shift+W` trong khung Mac**: khung đóng nhưng chỉ tách ra, shell VẪN chạy trên Mac (ghi chú phát hành: mỗi lần "Mở" thứ hai hoặc chia khung Mac tạo một workspace mới trên Mac; đóng chúng trên Mac). Đạt: đúng như vậy, app không lỗi.
- [ ] **`exit` trong khung Mac**: chỉ khung đó đóng, khung bên cạnh chiếm chỗ; `exit` ở khung cuối của tab cuối: mở tab PowerShell cục bộ mới, app không thoát.
- [ ] **Đăng xuất** (Settings): mọi tab Mac đóng, còn một tab cục bộ; đăng nhập lại rồi "Mở" kết nối lại được.
- [ ] **Bảng đang mở**: mở Settings, thử `Ctrl+Shift+T` và `Ctrl+Shift+N`: không có tab hay phiên mới; `Esc` đóng bảng, rồi bàn phím về terminal.
- [ ] **Tiêu đề / Narrator**: Narrator đang chạy, trong khung Mac `Insert+T` đọc `<dòng con trỏ> - ShellX`; Narrator không đọc lưới terminal (đúng dự kiến). Tắt Narrator: tiêu đề không còn dòng con trỏ.
- [ ] **Dán quá lớn vào Mac**: ``Set-Clipboard ("a" * 9MB)`` rồi `Ctrl+Shift+V` trong khung Mac. Đạt: hiện dòng "Nội dung dán quá lớn (tối đa 8 MB)", Mac không nhận gì, khung vẫn dùng được.
- [ ] **Nhìn bằng mắt ở 100 % và 150 %**: nhãn trạng thái ở giữa khung và dòng báo ở đáy khung rõ ràng, không có hiệu ứng sáng/bóng. Báo: ảnh chụp nếu lệch.

### Gỡ cài đặt

- [ ] Gỡ "ShellX 2" trong Settings > Apps. Đạt: ShellX Flutter vẫn còn, vẫn chạy, mục Start menu của nó còn nguyên; thư mục `%LOCALAPPDATA%\ShellX\native` còn lại (dữ liệu của bạn).

## Wave 1 parity (giao diện và gõ phím giống bản Mac)

Việc của bạn trên một máy Windows 10 1809+ hoặc Windows 11, với **bản cài thử** (`ShellX-Setup-1.5.3.exe` trong `dist/windows-parity`, kèm file `.sha256`; điều phối viên đưa đường dẫn và mã sha256). Đây là bản thử, không phải bản phát hành. Kiểm sha256 trước khi cài: `Get-FileHash .\ShellX-Setup-1.5.3.exe -Algorithm SHA256`. Mục 9 đến 16 là những chỗ chỉ kiểm được trên Windows thật. Đánh dấu `[x]` khi xong và ghi kết quả (đạt / hỏng + ghi chú, ảnh chụp nếu hỏng).

Quy ước: "phiên" là thẻ trong thanh bên; "tab" là tab trên thanh tab của một khung chia.

- [ ] **1. Cài đè lên 1.5.3**: chạy bản cài thử khi ShellX 1.5.3 đã cài. SmartScreen vẫn hiện "Unknown publisher" (chọn More info, rồi Run anyway). Đạt: cài xong không hỏi quyền quản trị; app mở và KHÔNG còn thẻ nhập email / mật khẩu trong thanh bên (chỉ còn nhóm "Máy của bạn" với "máy này"); dữ liệu cũ (đã đăng nhập, Mac đã ghép) vẫn còn.
- [ ] **2. Gõ khi không có bộ gõ**: tắt Unikey / EVKey và dùng bàn phím tiếng Anh. Bấm vào vùng terminal, gõ `dir` rồi Enter. Đạt: chữ hiện ngay khi gõ và lệnh chạy.
- [ ] **3. Telex**: (a) bật Unikey kiểu Telex, gõ `tiếng Việt` trong PowerShell; (b) tắt Unikey, bật bàn phím Vietnamese Telex có sẵn của Windows, gõ lại `tiếng Việt`. Đạt: ở cả hai lần chữ cuối cùng đúng, không dư, không mất, không lặp ký tự. (Với Unikey kiểu xoá lùi, chỉ chữ cuối cùng cần đúng.)
- [ ] **4. Đăng nhập trong hộp thoại**: Settings (`Ctrl+,`) > Tài khoản > "Đăng nhập…". Gõ email và mật khẩu hai lần: một lần với Unikey tắt, một lần với Unikey bật (gõ mật khẩu trực tiếp trong app, không gửi qua chat). Đạt: cả hai ô nhận chữ (kể cả khi bộ gõ đang soạn chữ), `Tab` chuyển ô, Enter đăng nhập, hộp thoại đóng và hiện tên tài khoản; `Esc` đóng hộp thoại khi chưa đăng nhập.
- [ ] **5. Phím tắt và nút chia khung**: `Ctrl+Shift+T` thêm một tab terminal trong khung đang chọn; `Ctrl+Shift+W` đóng terminal đang chọn; `Ctrl+Shift+N` thêm một phiên mới (thẻ mới trong thanh bên); `Ctrl+Shift+B` ẩn / hiện thanh bên; trên thanh tab, nút "Chia sang phải" và "Chia xuống dưới" chia khung. Đạt: mỗi thao tác đúng như trên, khung đang chọn có viền rõ, gõ vào đúng khung đó, `Ctrl+N` / `Ctrl+T` thường vẫn tới shell. (Back / Forward: xem mục 9.)
- [ ] **6. Thư mục và nhánh trên thẻ phiên**: trong PowerShell `cd` vào một thư mục git. Đạt: thẻ phiên hiện `~\…` (đường dẫn rút gọn) và `⎇ <tên nhánh>`; `cd` sang thư mục khác thì thẻ đổi theo, ra ngoài repo thì dòng nhánh biến mất. Thử tiếp với profile PowerShell có `prompt` riêng (oh-my-posh nếu đã cài): dấu nhắc vẫn hiện đúng và lệnh vẫn chạy. Nếu làm được, thử cả profile KHÔNG định nghĩa `prompt` (comment tạm dòng `prompt` trong `$PROFILE`): dấu nhắc vẫn là `PS <đường dẫn>> ` và thẻ vẫn cập nhật. Đạt: cả ba trường hợp đúng.
- [ ] **7. Ngôn ngữ theo Windows**: Windows ở "English" thì giao diện app là tiếng Anh; đổi Windows display language sang "Tiếng Việt" (Settings > Time & language > Language & region), đăng xuất / đăng nhập Windows, mở lại app thì giao diện là tiếng Việt. Đạt: đúng cả hai chiều; Settings ghi "Theo ngôn ngữ hiển thị của Windows" / "Follows the Windows display language". (Đặt `SHELLX_LANG=en` hoặc `vi` thì ghi đè.)
- [ ] **8. Nút cửa sổ**: thu nhỏ, phóng to / khôi phục, đóng. Rê chuột lên nút phóng to. Đạt: ba nút chạy đúng, khung Snap layouts của Windows 11 hiện khi rê lên nút phóng to (khung này chỉ có trên Windows 11; trên Windows 10 ghi "không áp dụng").
- [ ] **9. Back / Forward giữa hai phiên**: tạo hai phiên (`Ctrl+Shift+N`), bấm vào phiên thứ nhất rồi phiên thứ hai trong thanh bên. Bấm Back ("Tiêu điểm trước") trên tiêu đề, rồi Forward ("Tiêu điểm sau"). Sau đó đóng phiên thứ hai và bấm Back. Đạt: Back về đúng phiên trước, Forward tới lại phiên sau, nút mờ khi hết bước; sau khi đóng một phiên, Back bỏ qua phiên đã đóng, không rơi vào khung trống và bàn phím vẫn gõ được vào terminal đang chọn.
- [ ] **10. Bấm chuột vào từng nút**: (a) một tab; (b) nút × của một tab; (c) ba nút trên thanh tab ("Terminal mới", "Chia sang phải", "Chia xuống dưới"); (d) menu "+ ▾" trên tiêu đề (bấm mở, hàng "Phiên mới" và "Tab mới (terminal)" chạy đúng, bấm ra ngoài thì menu đóng); (e) menu `?` ở chân thanh bên (Cài đặt…, Kiểm tra cập nhật, Tài liệu, GitHub; bấm ra ngoài thì đóng); (f) viên thuốc cập nhật "Có bản cập nhật: …" (chỉ hiện khi thật sự có bản mới; bấm mở trang tải). Đạt: mỗi nút chạy đúng, sau mỗi lần bấm bàn phím vẫn gõ vào terminal đang chọn. Báo: nút nào không bấm được; nếu không có bản mới thì ghi "không kiểm được (f)".
- [ ] **11. "+" cạnh "Máy của bạn"**: khi CHƯA đăng nhập, bấm "+" thì mở hộp thoại "Đăng nhập ShellX". Sau khi đăng nhập, bấm "+" thì hiện danh sách máy; bấm ra chỗ khác (terminal, tiêu đề) thì danh sách đóng, và cú bấm đó vẫn có tác dụng. Đạt: đúng cả hai trường hợp; danh sách mở không giữ bàn phím của terminal sau khi đóng.
- [ ] **12. Theme oh-my-posh / starship báo lỗi lệnh**: cài oh-my-posh hoặc starship, bật theme có chỉ báo lỗi, chạy lệnh thất bại `cmd /c exit 1`. Đạt: chỉ báo lỗi của theme hiện (đỏ / dấu lỗi), rồi chạy lệnh đúng thì chỉ báo hết. (Hook của ShellX chạy `prompt` gốc trước nên `$?` còn nguyên; nếu theme báo thành công sau lệnh thất bại thì là lỗi.) Nếu không cài được cả hai, ghi "không kiểm được".
- [ ] **13. Ký tự `⎇` và tên thư mục tiếng Việt**: tạo thư mục có dấu và dấu cách, ví dụ `mkdir "$HOME\Tài liệu"`, `cd` vào đó (và thử một thư mục git có dấu). Đạt: dòng nhánh hiện `⎇` đúng ký tự (không phải ô vuông) và đường dẫn trên thẻ hiện `~\Tài liệu` đúng dấu, đúng dấu cách, không có `%C3`/`%20`.
- [ ] **14. Mở từ 8 tab trở lên trong một khung nửa màn hình**: chia đôi cửa sổ (`Alt+Shift+=`), rồi trong khung nhỏ mở thêm tab bằng `Ctrl+Shift+T` cho tới khi có từ 8 tab. Đạt: các tab giữ bề rộng, không co lại đè lên nhau hay lên ×; khi hết chỗ, lăn chuột trên thanh tab thì dải tab cuộn ngang, còn ba nút bên phải ("Terminal mới" ("New Terminal"), "Chia sang phải" ("Split right"), "Chia xuống dưới" ("Split down")) luôn hiện; bấm × của một tab chỉ đóng đúng tab đó. Lưu ý: tab vừa mở có thể nằm ngoài phần đang thấy (thanh tab chưa tự cuộn tới tab đang chọn), lăn chuột để thấy. Báo: ảnh chụp nếu chữ hay × của tab này đè lên tab khác, hoặc bấm × đóng nhầm tab.
- [ ] **15. Tự kiểm `--smoke` từ thư mục cài**: mở PowerShell và chạy ``$p = Start-Process "$env:LOCALAPPDATA\Programs\ShellX Native\shellx-desktop.exe" -ArgumentList '--smoke' -Wait -PassThru -RedirectStandardOutput "$env:TEMP\shellx-smoke.txt" -RedirectStandardError "$env:TEMP\shellx-smoke-err.txt"; $p.ExitCode`` (không mở cửa sổ, chạy dưới một phút). Đạt: in ra `0`, và `shellx-smoke.txt` có dòng `smoke: OSC 7 working directory …` và `smoke: PASS …`. Báo: nếu khác `0`, gửi cả hai file; lỗi nhắc tới OSC 7 / ConPTY nghĩa là PowerShell không báo được thư mục đang làm việc qua ConPTY (thẻ phiên sẽ không hiện thư mục và nhánh).
- [ ] **16. Ổ mạng hoặc thư mục chia sẻ**: `cd` vào một ổ mạng đã map (ví dụ `cd Z:\`) hoặc một thư mục chia sẻ UNC (`cd \\máy-chủ\thư-mục`), thử cả khi mạng chậm. Đạt: giao diện không đơ (vẫn bấm được nút, gõ được ở khung khác), thẻ phiên hiện đường dẫn. Rủi ro đã biết: việc tìm nhánh git đọc file trên luồng giao diện, nên ổ mạng chậm có thể làm cửa sổ khựng; nếu đơ, ghi đơ bao lâu. Không có ổ mạng thì ghi "không kiểm được".
