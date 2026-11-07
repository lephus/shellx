# ShellX: terminal thật trên điện thoại (iPhone và Android) — đặc tả thiết kế

Ngày: 2026-11-07. Dự án 2/3 (thứ tự ở `2026-11-07-shellx-google-sign-in-design.md` §12). Nhãn:
**[người dùng]**, **[người viết]** như các đặc tả trước.

## 1. Ý định

Hôm nay pane shell trên iPhone chỉ là ô giữ chỗ (`shellx-ios/ShellX/UI/Workspaces/ShellPanePlaceholder.swift`:
"the terminal itself comes later"). Ngày 2026-11-07 người dùng yêu cầu "fix Terminal thật trong pane: iOS
và Android" **[người dùng]**: xem và gõ được terminal của Mac ngay trong pane, trên cả hai điện thoại.

Thiết kế cho phần này đã có và đã được duyệt: **"đợt 2"** trong
`docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md`. Đặc tả này giữ đợt 2 làm nền và chỉ
ghi lại những gì **thay đổi** hoặc **thêm** kể từ đó.

## 2. Phần giữ nguyên từ đặc tả 2026-10-28

Các mục sau vẫn có hiệu lực, trừ chỗ mục 3 sửa:

- §1.1 đợt 2; §2.2 tiêu chí 3, 4, 5 (mở terminal p95 < 1 s, tiếng vọng phím p95 < 300 ms, in nhiều không
  treo, màn cuối đúng); tiêu chí 6 (không đổi lựa chọn hay focus trên Mac).
- §6.2 pane shell: vẽ đúng màu, con trỏ, chương trình toàn màn hình; cuộn scrollback; **hàng phím phụ** esc,
  tab, ctrl (giữ cho phím kế), ←, ↑, ↓, →; chạm hiện bàn phím, gõ là gửi; không mic, không gửi file.
- §6.3 mở terminal mới bằng chip `＋` (Mac thêm tab vào pane đang chọn, không đổi lựa chọn trên Mac).
- §7.2 luồng xem: ảnh ban đầu (màn hiện tại + 240 dòng) rồi luồng thay đổi; bốn loại đơn vị gõ (chữ, phím
  có tên + bổ trợ, dán, cuộn); **mỗi lúc mở đúng một terminal**; host tự điều tốc, bộ nhớ có giới hạn cho
  mỗi client; dữ liệu là **lưới ô đã vẽ từ Ghostty**, không phải byte PTY; chia mảnh khi lớn hơn frame
  (65 519 byte). Phần xin lịch sử theo trang được thay ở 3.8c.
- §8.3 phía Mac (`MobileTerminalRenderObserver`, `MobileTerminalFramePacer`, `v2MobileTerminalReplay`,
  `v2MobileTerminalInput`, bộ chia kích thước chung).
- §9 an toàn (viết lại PROTOCOL.md §10, gõ chỉ vào terminal phiên đó đang mở, MDM, không log nội dung).
- §10 kích thước theo bên hoạt động gần nhất.
- §11 kiểm thử và dogfood.

## 3. Thay đổi và bổ sung

### 3.1 Phạm vi: hai điện thoại [người dùng]

Cùng một giao thức, cùng hành vi trên iPhone và Android. App iPhone làm trước và là bản tham chiếu; terminal
trên Android là một phần của dự án Android, làm sau khi bản iPhone đã vào `develop` **[người viết]**.

### 3.2 Tên message: tránh trùng `terminal.close` [người viết]

Đặc tả 2026-10-28 dùng `terminal.close` cho "thôi xem". Từ đó `terminal.close` đã được dùng cho việc **đóng
hẳn một tab trên Mac** (feature `terminal_close`, `shellx-link/spec/PROTOCOL.md` §4, đã phát hành). Vì
vậy luồng xem dùng một họ tên riêng dưới feature mới **`terminal_view`**, ví dụ:

| Hướng | Message | Ý nghĩa |
| --- | --- | --- |
| phone → host | `terminal.view.open` {`call_id`, `terminal_id`, `cols`, `rows`} | bắt đầu xem |
| host → phone | `terminal.view.frame` | ảnh ban đầu hoặc thay đổi, có thể chia mảnh |
| phone → host | `terminal.view.input` {`terminal_id`, `units`} | gõ |
| phone → host | `terminal.view.resize` {`terminal_id`, `cols`, `rows`} | đổi kích thước |
| phone → host | `terminal.view.close` {`terminal_id`} | thôi xem (tab trên Mac vẫn còn) |
| host → phone | `terminal.view.ended` {`terminal_id`, `reason`} | terminal biến mất, bị chặn, hay luồng phải mở lại |

Builder chốt tên và trường chính xác, miễn không đụng nghĩa của `terminal.close` hiện có.

### 3.3 Mở terminal mới: feature riêng [người viết]

`terminal.create` {`call_id`, `workspace_id`} → `terminal.create.result` {`call_id`, `outcome`,
`terminal_id`?} dưới feature **`terminal_create`**. Mac chưa có feature này thì điện thoại ẩn chip `＋`.

Lệnh tạo tab sẵn có `mobile.terminal.create` với `focus: false` **vẫn đổi tab đang hiện trên Mac**. Nó không
truyền `preserveBonsplitSelectionWhenUnfocused` (`Sources/TerminalController.swift:16187-16195`), mà
Bonsplit chọn mọi tab vừa chèn (`vendor/bonsplit/Sources/Bonsplit/Internal/Models/PaneState.swift:45-58`).
Chỉ cờ đó mới trả lại tab cũ (`Sources/Workspace.swift:9921-9928`). `terminal.create` phải giữ nguyên lựa
chọn trên Mac (tiêu chí 6), có test hành vi riêng.

### 3.4 Các mục menu đã có

- "Đóng pane này" (§6.2 cũ) **chính là** "Close Tab…" đã phát hành (part 3). Không làm thêm.
- "Xem pane agent dạng terminal" trong menu `•••` khi chip là pane agent: **giữ**, mở luồng xem trên đúng
  terminal của agent đó **[người viết]**.

### 3.5 Định dạng lưới viết hẳn vào PROTOCOL.md [người viết]

Điện thoại phải dựng được bộ vẽ **từ đặc tả**: app iPhone và app Android đều đóng nguồn và **không** được
chép `CMUXMobileCore` (GPL, ví dụ
`Packages/Shared/CMUXMobileCore/Sources/CMUXMobileCore/MobileTerminalRenderGrid.swift`) hay bộ vẽ iOS của
cmux (`Packages/iOS/CmuxMobileShell`). Theo quy tắc sẵn có ở `shellx-ios/README.md` (mục "Licence
boundary"), **đọc để tham khảo thì được, chép thì không**; không cần làm kiểu phòng sạch. Mac được dùng
`CMUXMobileCore` để dựng khung rồi dịch sang dạng của Link. Vì vậy:

- Một mục mới trong `shellx-link/spec/PROTOCOL.md` cho `terminal_view`: ô (chữ, độ rộng 1 hay 2), kiểu
  (đậm, nghiêng, gạch chân, đảo màu, mờ…), màu (chỉ số bảng màu và RGB, bảng màu mặc định gửi kèm ảnh ban
  đầu), con trỏ (vị trí, kiểu, ẩn hiện), màn chính hay màn phụ, delta theo dòng nối bằng `revision`, phong
  bì chia mảnh có số thứ tự, luật khi thiếu mảnh hay hụt revision (xin lại ảnh đầy đủ).
- Bộ vector mới `shellx-link/spec/vectors/terminal.json`: test Swift (`shellx-link`) và test Kotlin
  (`shellx-link/kotlin`, đặc tả Android) cùng đọc.
- Phân tích an toàn của §9 cũ đi kèm mục này.

### 3.6 Gõ tiếng Việt [người viết]

Người dùng viết tiếng Việt. Gõ qua bàn phím hệ thống bằng Telex / VNI phải ra đúng chữ có dấu: điện thoại
chỉ gửi **chữ đã chốt**; chữ đang soạn (marked text trên iOS, composing text trên Android) hiện tạm tại con
trỏ và không gửi đi. Backspace khi đang soạn sửa chữ đang soạn, không gửi phím backspace cho Mac.

### 3.7 Bàn phím rời [người viết]

Bàn phím Bluetooth: chữ, Enter, Backspace, Tab, Esc, mũi tên và Ctrl+chữ đi theo đúng đường phím có tên.
Không có phím tắt riêng của app.

### 3.8a Phía Mac: thêm điểm nối vào lõi cmux [người viết]

Đặc tả cũ (§8.3) coi các mảnh của cmux là dùng được ngay. Đọc code thì thấy phần **luồng** không tới được
ShellX Link:

- Mac chỉ chụp lưới khi `MobileHostService.hasEventSubscribers` đúng
  (`Sources/Mobile/MobileTerminalRenderObserver.swift:169-173,249-252`,
  `MobileTerminalByteTee.swift:121-122`), mà cờ này đọc từ một bộ đếm riêng (`MobileHostService.swift:36`).
- Khung chỉ đi qua `emitRenderGridEvent` tới `MobileHostConnectionRegistry` (`MobileHostService.swift:605`,
  `:693`). Mốc neo được khoá theo id kết nối iroh.
- ShellX tắt bộ nghe iroh (`MobileHostService.swift:763`, `ShellXFeatures.swift:3`), nên hôm nay bộ quan
  sát không bao giờ sinh khung.

Quyết định: **sửa lõi cmux một chút** bằng một điểm nối cho nơi nhận khung (ví dụ giao thức
`MobileTerminalFrameSink`). Điểm nối này nằm trong `MobileHostService`, `MobileTerminalRenderObserver` và
`MobileTerminalByteTee`:

- Mac chụp khi có người xem qua iroh **hoặc** qua Link, và gửi khung cho cả hai.
- Đường iroh giữ nguyên hành vi, có test chứng minh.

Không giả làm một kết nối iroh, vì làm vậy phải mã hoá rồi giải mã lại khung. Cũng không chép bộ quan sát
thành một bản riêng cho Link. Repo này không theo dõi upstream, nên chi phí hợp nhất về sau thấp.

Đầu vào đi bốn đường riêng:

- chữ qua `v2MobileTerminalInput` (`TerminalController.swift:16553-16588`, chỉ nhận chữ);
- phím có tên qua `sendNamedKeyResult` (`TerminalController+ControlTerminalBinding.swift:57`);
- cuộn qua đường `mobile.terminal.scroll` có `delta_lines` (`TerminalController.swift:16494-16524`).
  `mobile.terminal.mouse` mà đặc tả cũ §7.2 nêu là cú bấm tại cột và dòng, không phải cuộn;
- dán qua đường dán của Mac.

### 3.8b Kích thước: phải sửa bộ chia [người viết]

Đặt kiểu `latest` thôi không đủ để điện thoại lấy được kích thước của nó:

- điện thoại nhường một Mac cùng người dùng đang được tính kích thước (`TerminalSizingEngine.swift:98-112`,
  `docs/shared-terminal-sizing.md` dòng 70-74);
- điện thoại được gán chính user id của Mac (`TerminalController+SharedSizing.swift:104-110`);
- mọi lần gõ được nhận đều tính là hoạt động trên Mac, kể cả gõ từ điện thoại
  (`Workspace+AttentionFlashRouting.swift:21-27`).

Vì vậy, người xem qua Link là **một bên tham gia riêng** trong bộ chia kích thước. Gõ từ điện thoại được
ghi là hoạt động của điện thoại, không phải của Mac. Như vậy luật "bên hoạt động gần nhất" (§10 cũ) đúng
thật. Hành vi với các client khác không đổi.

### 3.8c Lịch sử: nạp nền một lần, không phân trang [người viết]

Mac chỉ xuất được "N dòng scrollback mới nhất" (`TerminalController+MobileScrollPrefetch.swift:6-14`;
replay `TerminalController.swift:16285-16299`). Phân trang theo `before` cần địa chỉ dòng ổn định trong lúc
chữ vẫn chạy và khi scrollback dàn lại mỗi lần đổi khổ, nên bỏ phân trang:

- ảnh ban đầu mang màn hiện tại + 240 dòng (như cũ);
- ngay sau đó Mac **nạp nền một lần** thêm tới một ngân sách cố định, như cmux đang làm. Mức là giá trị mặc
  định của cmux (`MobileTerminalScrollbackPreference.swift`), có trần theo byte;
- sau mỗi lần đổi khổ làm scrollback dàn lại, điện thoại nhận ảnh mới theo đúng cách đó;
- không có message `terminal.view.history`. "Cài đặt Mac" mà đặc tả cũ §7.2 nêu không tồn tại:
  `screenAnchorScrollbackRowBudget` là hằng số (`MobileTerminalRenderGridFrame+Emission.swift:11`).

### 3.8d PROTOCOL.md §10 phải viết lại

`shellx-link/spec/PROTOCOL.md` dòng 870-872 hôm nay vẫn cấm điện thoại mở terminal, và cấm gõ phím hay chữ
vào bất cứ gì ngoài agent đang sống. Bản viết lại theo §9 cũ là điều kiện để làm `terminal_view` và
`terminal_create`.

### 3.9 Phiên bản

Cần một bản desktop có `terminal_view` (sau bản 1.8.0 của dự án đăng nhập). Điện thoại nói chuyện với Mac
cũ vẫn chạy: không có feature thì pane shell hiện "Cập nhật ShellX trên Mac để xem terminal".

## 4. Không làm

- Chọn và sao chép chữ từ terminal (để sau) **[người viết]**.
- Terminal của máy Windows: desktop Windows không phục vụ ShellX Link.
- Mở nhiều terminal cùng lúc (§7.2 cũ).
- Đổi theme / font terminal từ điện thoại (§3 cũ).

## 5. Kiểm thử

Như §11 cũ, thêm:

- vector `terminal.json` xanh ở cả Swift và Kotlin;
- test bộ gom mảnh và luật revision ở `ShellXAppCore` (iPhone) và `core` (Android);
- render test (iPhone) / screenshot test (Android) cho màn chính thường, vim / htop (màn phụ), chữ rộng
  (CJK, emoji), sáng / tối;
- gõ Telex trên máy thật cả hai điện thoại;
- đo tiêu chí 3, 4, 5 trên iPhone 11 Pro của người dùng và một máy Android thật, qua relay thật, khác mạng.

## 6. Để lại cho người làm

- Tên và trường chính xác (3.2, 3.3); phong bì chia mảnh; dạng delta.
- Cách vẽ trên mỗi điện thoại (Core Text / SwiftUI Canvas; Compose Canvas / `android.graphics`), miễn đạt
  tiêu chí và nằm trong ranh giới giấy phép.
- Cỡ chữ mặc định, cử chỉ phóng to, cách hiện hàng phím phụ trên mỗi hệ.
- Dữ liệu Mac giả cho chế độ demo và render test.
