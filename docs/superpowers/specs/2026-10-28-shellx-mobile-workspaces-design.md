# ShellX mobile: quản lý và dùng workspace từ iPhone — đặc tả thiết kế

Ngày: 28/10/2026. Nguồn: phiên brainstorm cùng ngày, mockup ở
`.superpowers/brainstorm/56669-1793188282/content/` (`structure.html`, `workspace.html`,
`workspace-v2.html`). Nhãn **[người dùng]** là điều người dùng nói hoặc chọn; **[người viết]** là lựa chọn
của người viết spec, người dùng chưa duyệt riêng.

Spec này nối tiếp `2026-10-22-shellx-ios-agent-remote-design.md` (gọi tắt "spec iOS") và sửa giao thức
`shellx-link/spec/PROTOCOL.md`. Chỗ nào hai spec khác nhau về màn hình iOS thì spec này thắng.

## 1. Ý định và lý do

Ngày 28/10 người dùng ghép cặp iPhone thật với ShellX 1.5.1 qua mã QR và chạy được. Ngay sau đó họ thấy
thiếu: "đã ghép đôi xong, nhưng chưa quản lý được các workspace trên shellX". App iOS hiện chỉ thấy các
phiên Claude Code, không thấy workspace, không xem hay gõ được terminal.

Yêu cầu của người dùng **[người dùng]**:

- App mobile **lấy ý tưởng gióng desktop** hiện tại;
- **cắt bớt tính năng không cần** trên điện thoại;
- nhưng mobile **cũng quản lý và sử dụng các workspace như desktop app**;
- **giữ voice chat và gửi file, ảnh**;
- chưa biết điều gì sẽ làm mình khó chịu: "cứ lên app trước để dùng trải nghiệm". Vì vậy bản này nhắm
  tới một bản chạy được trên iPhone của người dùng sớm nhất có thể, rồi sửa theo trải nghiệm thật.

### 1.1 Hai đợt [người dùng]

Người dùng chọn chia hai đợt để có bản dùng thử sớm:

- **Đợt 1** (mục tiêu: nửa ngày đến 1 ngày tới bản cài trên iPhone): màn danh sách workspace; tạo, đổi
  tên, đóng workspace; màn workspace với hàng chip; pane agent dạng chat có mic và gửi ảnh / file. Feature
  `workspaces` và `workspace_control` (mục 7). Pane shell ở đợt này chỉ hiện một ô giữ chỗ "Xem và gõ
  terminal có ở bản sau" **[người viết]**; chip `＋` (mở terminal) và "Đóng pane này" cũng chờ đợt 2.
- **Đợt 2** (thêm khoảng 1 ngày): pane shell là terminal thật, xem và gõ được; mở / đóng terminal. Feature
  `terminal` (mục 7.2, 8.3, 10).

Mỗi đợt kết thúc bằng một bản cài lên iPhone của người dùng và một bản Mac build cục bộ có phần host;
phát hành công khai là quyết định riêng của người dùng.

## 2. Mục tiêu và tiêu chí thành công

### 2.1 Mục tiêu

- **G1. Màn chính là danh sách workspace**, như sidebar desktop phóng ra cả màn (hướng A trong
  `structure.html`) **[người dùng]**.
- **G2. Vào một workspace là dùng được nó**: hàng chip pane trên cùng, vuốt ngang để chuyển pane (hướng A
  trong `workspace.html`) **[người dùng]**. Pane có agent hiện dạng chat; pane shell là terminal thật, xem
  trực tiếp và gõ được **[người viết, người dùng xem mockup `workspace-v2.html` không phản đối]**.
- **G3. Quản lý workspace từ điện thoại**: tạo workspace mới (thư mục chọn **giống cách desktop mở**
  **[người dùng]**), đổi tên, đóng workspace; mở thêm terminal trong workspace, đóng một pane
  **[người viết]**.
- **G4. Giữ mic nói (tiếng Việt) và nút gửi ảnh / file** trong ô nhắn agent **[người dùng]**.
- **G5. Không mất gì của luồng "cần bạn" hiện có**: thanh "Cần bạn · N", trang yêu cầu, các sheet duyệt
  quyền / câu hỏi / plan giữ nguyên hành vi.

### 2.2 Tiêu chí thành công (đo được) [người viết]

Đo trên iPhone 11 Pro của người dùng, qua relay thật (`relay.shellx.pro`), Mac và iPhone khác mạng (4G):

1. Mở app (đã ghép cặp, Mac online) → danh sách workspace hiện đủ: p95 < 1,5 s.
2. Đổi trên Mac (tạo, đổi tên, đóng workspace; agent đổi trạng thái) → điện thoại thấy: p95 < 500 ms.
3. Chạm một pane shell → màn terminal hiện đúng nội dung đang có trên Mac: p95 < 1 s.
4. Gõ một phím trên điện thoại → ký tự hiện lại trên màn điện thoại (vòng Mac): p95 < 300 ms.
5. Lệnh in nhiều (ví dụ `yes | head -100000`, `cat` một file 5 MB) không làm app treo hay Mac chậm đi; điện
   thoại có thể bỏ khung trung gian nhưng màn cuối cùng phải đúng.
6. Thao tác trên điện thoại **không bao giờ** đổi workspace hay pane đang chọn trên Mac, không kéo cửa sổ
   Mac lên trước.

## 3. Không làm trên điện thoại (non-goals)

Cắt theo ý "cắt bớt tính năng không cần" **[người dùng]**; danh sách cụ thể là của **[người viết]**,
người dùng xem trong buổi brainstorm và không phản đối:

- pane trình duyệt, pane markdown, Git Graph, file explorer / sidebar phải, pane todo: **ẩn** khỏi hàng
  chip (không phá, không đóng chúng trên Mac);
- chia khung: điện thoại hiện **một pane mỗi lúc**, không vẽ bố cục split;
- command palette, chia sẻ phiên, chỉnh theme / font terminal, phím tắt, cài đặt của Mac;
- kéo thả sắp xếp workspace, nhóm workspace, đổi màu workspace (chỉ hiện, không sửa);
- thông báo đẩy khi app đóng: thuộc P4 (APNs) của spec iOS, không nằm trong spec này;
- agent khác Claude Code ở dạng chat (terminal thì dùng được với mọi chương trình);
- bố cục riêng cho iPad (chạy kiểu iPhone là đủ);
- máy ở xa (remote machines, VPS qua SSH) trong danh sách: chỉ các Mac đã ghép cặp qua ShellX Link.

## 4. Điều tuyệt đối tránh (anti-goals)

Người dùng chưa nêu **[người dùng]**. Mang sang từ spec iOS: điện thoại và desktop lệch trạng thái nhau;
lag. Thêm **[người viết]**:

- điện thoại làm phiền người đang ngồi ở Mac: giật focus, đổi workspace đang chọn, cửa sổ nhảy lên;
- một thao tác phá huỷ (đóng workspace, đóng pane) chạy mà không hỏi lại;
- chữ gõ từ điện thoại rơi vào một terminal khác với terminal đang hiện trên điện thoại.

## 5. Ràng buộc

- **Ranh giới giấy phép iOS** (`scripts/shellx/check-ios-license.sh`): app chỉ dùng Apple frameworks, code
  của chính nó và package MIT `shellx-link/`. Không code GPL (`Sources/`, `Packages/`, `ios/`,
  `cmux-tui/`, `shellx-core/`), **không package tải từ mạng**, không chữ "Manaflow". Muốn dùng thư viện
  ngoài (ví dụ SwiftTerm, MIT) thì phải chép mã nguồn vào repo kèm LICENSE và nới allowlist của script,
  có ghi lý do.
- **Giao thức**: ShellX Link v1, frame JSON tối đa 65 519 byte, mọi phần thêm là **cộng thêm** và được
  báo qua `welcome.features`. Mac 1.5.1 và app iOS đang có trên máy người dùng phải tiếp tục chạy với
  nhau như hôm nay.
- **Mac**: code liên kết vào app giữ tương thích Swift 6.0; mọi lệnh tới từ điện thoại theo
  `skills/cmux-socket-policy` (không cướp focus, không chặn main thread ở đường gõ phím).
- **An toàn**: phần thêm phải có phân tích an toàn viết lại trong PROTOCOL.md §10 (mục 9 bên dưới).
  `RemoteRelayCommandPolicy` của `cmux ssh` **không đổi**, không method socket v2 nào được thêm vào
  allowlist của nó.
- **Phát hành**: phần Mac cần một bản desktop mới (1.5.2 trở đi; không bao giờ ghi đè 1.5.1). Người dùng
  quyết định khi nào phát hành.

## 6. Thiết kế trải nghiệm

Bộ màu, chữ, nút theo spec desktop §7.4 và gu đã chốt: nền tối `#0b0716`, khối `#17122a`, màu chủ đạo
`#60a5fa`, *chờ bạn* = xanh dương, *chạy* = vàng dịu `#e8c468`, *xong* = xanh lá `#6fd49a`, *lỗi* =
`#e88a8a`; nút màu đặc dịu, không gradient, không quầng sáng. Giao diện sáng / tối / theo iPhone giữ như
Cài đặt › Giao diện hiện có.

### 6.1 Màn chính "Workspace" [người dùng chọn bố cục; chi tiết của người viết]

Thay màn chat "ShellX" gộp hiện nay. Từ trên xuống:

- **Thanh trên**: tiêu đề "Workspace"; bên phải chuông (đếm mọi việc "cần bạn" của mọi Mac, mở trang
  yêu cầu), nút ＋ (tạo workspace), nút cài đặt (mở Cài đặt, trong đó có "Mac của bạn").
- **Thanh mảnh "Cần bạn · N"** khi N > 0, bấm mở trang yêu cầu (như hiện nay).
- **Nhóm theo Mac**: đầu nhóm là chấm online, tên Mac, số workspace. Mac ngoại tuyến hiện mờ, ghi
  "ngoại tuyến · lần cuối HH:MM", không có dòng bên dưới. Mac mặc định đứng đầu.
- **Mỗi workspace một dòng**, giống sidebar desktop:
  - tên workspace;
  - dòng phụ chữ mono: nhánh git · thư mục (rút gọn `~`) · cổng đang mở;
  - nhãn trạng thái bên phải: *chờ bạn* (dòng có viền xanh), *chạy*, *xong*, *lỗi*; rảnh thì không nhãn;
  - khi agent đang hỏi: thêm một dòng trích câu hỏi.
- **Thứ tự** các workspace giống thứ tự trên sidebar Mac.
- **Vuốt trái** một dòng: "Đổi tên", "Đóng". **Chạm**: mở màn workspace.
- **Dòng "Phiên agent khác · N"** ở cuối nhóm Mac, chỉ hiện khi N > 0 **[người viết]**: các phiên Claude
  Code không gắn được vào chip nào (chạy trong workspace SSH, `workspace_id` rỗng hay không có trong danh
  sách) và các phiên đã kết thúc còn đọc được lịch sử (Mac giữ tối đa 20). Chạm mở danh sách, chạm một
  phiên mở màn agent như hôm nay. Nhờ vậy bỏ màn chat gộp không làm mất đường tới phiên nào.
- Kéo xuống để làm mới (gửi lại yêu cầu danh sách).
- Mac chưa hỗ trợ workspace (bản 1.5.1): nhóm của Mac đó hiện dòng "Cập nhật ShellX trên Mac để quản lý
  workspace", và dòng "Phiên agent khác" chứa mọi phiên của Mac đó để vẫn chat được.

### 6.2 Màn workspace [người dùng chọn bố cục]

- **Thanh trên**: "‹ Workspace", giữa là tên workspace và nhánh git, phải là `•••`.
- **Hàng chip**: mỗi terminal của workspace là một chip, theo thứ tự trên Mac (pane trái→phải,
  trên→dưới; trong một pane theo thứ tự tab). Tên chip là tên tab trên Mac. Chấm màu trên chip là trạng
  thái agent nếu terminal đó có agent. Chip cuối là `＋` (mở terminal mới). Chip chọn sẵn khi vào: pane
  đang chờ bạn nếu có, rồi tới pane đang được chọn trên Mac, rồi tới chip đầu.
- **Vuốt ngang** trên nội dung để qua chip kế bên.
- **Pane có agent Claude Code** hiện dạng chat, chính là màn agent hiện có (tin nhắn, bước tool, thanh
  "Cần bạn" của riêng workspace, nút dừng), ô nhắn có **＋ gửi ảnh / file** và **mic**.
- **Pane shell** là terminal thật:
  - vẽ đúng màu, con trỏ, chương trình toàn màn hình (vim, htop, Claude TUI);
  - cuộn lên xem lại lịch sử (scrollback) có trên Mac;
  - **hàng phím phụ** trên bàn phím: esc, tab, ctrl (giữ trạng thái cho phím kế), ←, ↑, ↓, →;
  - chạm vào terminal thì hiện bàn phím iPhone; gõ là gửi thẳng từng phím (không có ô soạn riêng);
  - không mic, không gửi file ở pane shell **[người viết]**.
- **Menu `•••`**: Đổi tên workspace · Đóng pane này · Xem pane agent dạng terminal (khi chip đang là pane
  agent) · **Đóng workspace…** (chữ đỏ).
- Pane bị đóng trên Mac khi đang xem: chip biến mất, điện thoại sang chip kế, hiện một dòng báo ngắn.
  Workspace bị đóng trên Mac: quay về danh sách, báo ngắn.

### 6.3 Tạo, đổi tên, đóng

- **Tạo workspace** (＋ ở màn chính): có hơn một Mac online thì hỏi Mac nào trước. Mac tạo workspace
  **theo đúng quy tắc của desktop** **[người dùng]**: kế thừa thư mục của terminal đang chọn trong
  workspace đang chọn trên Mac (`working-directory-inheritance` của Ghostty), nếu tắt thì
  `working-directory` trong cấu hình, nếu không có thì `~`. Điện thoại **không gửi đường dẫn nào**.
  Workspace mới nằm cuối sidebar Mac, Mac **không** chuyển sang nó; điện thoại mở luôn màn workspace mới
  ở pane shell **[người viết]**.
- **Mở terminal mới** (chip `＋`): Mac thêm một tab terminal vào pane đang chọn của workspace đó, thư mục
  theo quy tắc tab mới của desktop; không đổi lựa chọn trên Mac. Điện thoại chuyển sang chip mới.
- **Đổi tên**: ô nhập trong hộp thoại, tối đa 128 ký tự, bỏ ký tự điều khiển; tên rỗng là bỏ tên tự đặt
  (về tên tự động như desktop).
- **Đóng pane / đóng workspace**: luôn hỏi lại bằng hộp xác nhận ghi rõ "Các terminal trong workspace sẽ bị
  tắt trên Mac". Nếu desktop sẽ hỏi xác nhận khi đóng (ví dụ có tiến trình đang chạy) thì điện thoại vẫn
  chỉ cần hộp xác nhận của chính nó; Mac **không** hiện hộp thoại khi lệnh đến từ điện thoại.

### 6.4 Số phận các màn hiện có

- Màn chat "ShellX" gộp, chip agent ở màn chính, chip "Gửi tới:" và ghi chú "xong" trong cuộc trò chuyện
  gộp: **bỏ** (đã có nhãn trạng thái trên dòng workspace). Dữ liệu cuộc trò chuyện gộp đã lưu trên máy
  được xoá ở lần mở đầu tiên của bản mới.
- Màn agent (`AgentView`): thành **pane agent** trong màn workspace. Vẫn mở được trực tiếp từ trang "Cần
  bạn".
- Trang "Cần bạn", các sheet duyệt: giữ nguyên.
- "Mac của bạn", ghép cặp, đăng nhập, màn chưa có Mac (`FirstMacView`), Cài đặt: giữ nguyên; "Mac của bạn"
  vào từ Cài đặt và từ đầu nhóm Mac ở màn chính.
- Chế độ demo (`--demo`): có thêm Mac giả với vài workspace và terminal giả, để render test và để
  người dùng xem nhanh.

## 7. Giao thức: phần thêm vào ShellX Link

Ba nhóm, mỗi nhóm một tên trong `welcome.features` để hai bên biết nhau có gì **[người viết]**:

| Feature | Thêm gì |
| --- | --- |
| `workspaces` | đọc danh sách workspace và các pane terminal của chúng, nhận thay đổi |
| `terminal` | mở một terminal để xem (ảnh màn hình ban đầu + luồng thay đổi), gõ phím, đổi kích thước, đóng xem |
| `workspace_control` | tạo / đổi tên / đóng workspace, mở / đóng terminal |

Host chỉ báo feature nó phục vụ được; client không gọi những gì host không báo. Gọi thì vẫn bị
`unsupported` như §3.

### 7.1 `workspaces`

- `workspace.list.get` → `workspace.list` {`revision`, `workspaces`}; thay đổi đến bằng
  `workspace.changed` {`revision`, `upserted`, `removed`}. Quy tắc revision giống hệt danh sách phiên
  (§4): tăng đúng 1 mỗi lần, client thấy hở thì xin lại cả danh sách.
- Mỗi **Workspace**: `workspace_id` (ổn định; cùng giá trị với `AgentSession.workspace_id` và
  `PendingItem` của workspace đó), `title`, `order` (thứ tự trên sidebar Mac; nhiều cửa sổ thì theo thứ
  tự cửa sổ rồi tới thứ tự trong cửa sổ), `directory` (chuỗi hiển thị, đã rút `~`, chỉ để đọc), `branch`
  (tuỳ chọn), `ports` (mảng số, tuỳ chọn), `terminals` (mảng **Terminal**).
- Mỗi **Terminal**: `terminal_id` (ổn định, chính là id surface trên Mac), `title`, `order`, `selected`
  (bool: đang được chọn trên Mac, chỉ dùng để chọn chip mặc định), `session_id` (tuỳ chọn: phiên Claude
  Code đang chạy trong terminal này, khớp với `AgentSession.session_id`; nhờ nó điện thoại biết chip nào
  là pane agent).
- **Trạng thái và câu hỏi trên dòng workspace do điện thoại tự suy ra** từ danh sách phiên và danh sách
  việc chờ đã có (`AgentSession.state`, `PendingItem`, bộ dò "xong" `SessionFinishDetector` của app), nên
  giao thức không mang chúng **[người viết]**. Workspace không có agent thì không có nhãn.
- Chỉ liệt kê workspace cục bộ của Mac (không liệt kê workspace SSH / máy ở xa) và chỉ surface terminal;
  trình duyệt, markdown, todo… không xuất hiện. Nhóm workspace của Mac không hiện: danh sách phẳng theo
  thứ tự sidebar.
- Danh sách quá lớn cho một frame thì cắt theo §6: builder chọn thứ tự bỏ trường (gợi ý: `ports`, rồi
  `directory`, rồi `branch`, rồi tên tab) và ghi vào §6.

### 7.2 `terminal`

Một luồng xem cho mỗi terminal mà điện thoại đang mở; nhiều điện thoại có thể cùng xem một terminal.

- `terminal.open` {`terminal_id`, `cols`, `rows`} → host gửi **ảnh màn hình ban đầu** (màn hiện tại và
  một phần scrollback, có thể nhiều frame) rồi **luồng thay đổi** cho tới khi `terminal.close` hoặc mất
  kết nối.
- `terminal.input` {`terminal_id`, `units`}: dãy đơn vị gõ theo thứ tự, tổng tối đa 4 096 byte mỗi frame.
  Bốn loại đơn vị **[người viết]**:
  - **chữ** (UTF-8) như gõ từng phím;
  - **phím có tên** kèm phím bổ trợ (`enter`, `backspace`, `tab`, `escape`, mũi tên, `ctrl`+chữ…);
  - **dán**: chữ dán từ clipboard iPhone (menu Dán khi chạm giữ terminal), đi theo đường dán của Mac
    (bracketed paste khi chương trình bật), để dán nhiều dòng không chạy từng dòng như gõ Enter;
  - **cuộn**: số nấc lăn chuột lên / xuống, đi theo đường chuột của Mac (`mobile.terminal.mouse`). Dùng
    khi terminal đang ở màn phụ (vim, less, htop, Claude TUI): Ghostty trên Mac tự quyết gửi sự kiện chuột
    hay phím mũi tên cho chương trình. Ở màn thường, vuốt chỉ cuộn scrollback trên điện thoại, không gửi gì. Không gửi chuỗi escape thô: API gõ của Mac đưa escape trong chữ vào
  bộ giải hiển thị chứ không vào stdin của chương trình (`TerminalSurface+Input.swift`,
  `parsedSocketInputEvents`). Chỉ được gõ vào terminal mà chính phiên Link này đang mở (`terminal.open`
  còn hiệu lực).
- `terminal.resize` {`terminal_id`, `cols`, `rows`}.
- `terminal.close` {`terminal_id`}.
- `terminal.history.get` {`terminal_id`, trước dòng nào, số dòng} → các dòng cũ hơn, để cuộn sâu quá ảnh
  ban đầu **[người viết]**. Ảnh ban đầu chỉ mang màn hiện tại + **240 dòng** gần nhất để đạt tiêu chí 3;
  cuộn tới đầu thì điện thoại xin thêm từng trang, tới giới hạn scrollback của Mac
  (`screenAnchorScrollbackRowBudget`, mặc định 4 000 dòng, chỉnh trong Cài đặt Mac).
- **Mỗi lúc điện thoại chỉ mở đúng một terminal**: terminal của chip đang hiện **[người viết]**. Vuốt sang
  chip khác thì đóng terminal cũ (nó về khổ Mac, mục 10) rồi mở terminal mới. Ra khỏi màn workspace hoặc
  đưa app xuống nền thì đóng luôn. Như vậy tối đa một terminal trên Mac bị co về khổ điện thoại.
- Host **tự điều tốc**: gộp thay đổi, bỏ khung trung gian khi điện thoại hay mạng chậm, không bao giờ
  dồn bộ nhớ không giới hạn cho một client chậm; khi bỏ quá nhiều thì gửi lại ảnh màn hình đầy đủ.
- **Dạng dữ liệu: lưới ô đã vẽ sẵn từ Ghostty** (định dạng `cmux.render-grid.v1` của Mac, hoặc một bản
  rút gọn tương đương), **không** phải byte PTY thô **[người viết]**. Lý do: điện thoại chỉ cần vẽ các ô
  chữ có kiểu, không cần bộ giải VT. App iOS không được dùng libghostty của cmux hay package tải từ mạng
  (mục 5), và tự viết một bộ giải VT đủ cho vim / htop / Claude TUI là việc lớn. Mac đã có sẵn lưới, bộ
  điều tốc và ảnh chụp ban đầu (mục 8.3).
- Một khung lưới hoặc ảnh ban đầu lớn hơn frame (65 519 byte) phải được **chia mảnh** theo một phong bì
  có số thứ tự; điện thoại gom đủ mảnh rồi mới vẽ, giống cách `attach.*` chia mảnh chiều lên. Tiền lệ:
  `ShareHost.chunkBytes` = 32 KiB.

### 7.3 `workspace_control`

- `workspace.create` {`call_id`} → `workspace.create.result` {`call_id`, `outcome`, `workspace_id`
  (khi `ok`)}. Không có tham số đường dẫn, lệnh hay tên chương trình.
- `workspace.rename` {`call_id`, `workspace_id`, `title`} → `.result`.
- `workspace.close` {`call_id`, `workspace_id`} → `.result`.
- `terminal.create` {`call_id`, `workspace_id`} → `.result` {…, `terminal_id`}.
- `terminal.close.surface` (tên do builder chốt) {`call_id`, `terminal_id`} → `.result`.
- `outcome`: `ok`, `not_found`, `refused` (Mac đang chặn điều khiển từ xa, ví dụ MDM; hoặc luật của Mac
  không cho, ví dụ đóng workspace cuối cùng hay terminal cuối cùng của workspace), `failed`. Điện thoại
  báo `refused` bằng một câu dễ hiểu ("Mac không cho đóng workspace cuối cùng").
- Mọi lệnh có `call_id` và idempotent theo `call_id` trong một phiên Link. **Điện thoại không tự gửi lại**
  lệnh quản lý sau khi mất kết nối **[người viết]**: nối lại thì xin lại danh sách và báo "Chưa rõ lệnh đã
  tới Mac chưa, hãy xem lại danh sách". Host không cần nhớ `call_id` qua các phiên.

## 8. Phía Mac

Mac (fork cmux) đã có gần đủ phần lõi, viết cho app mobile riêng của cmux (`Sources/Mobile/`, giao vận
iroh). Spec này **dùng lại lõi đó** và chỉ viết thêm lớp nối vào ShellX Link; không bật, không đụng host
iroh của cmux **[người viết]**.

### 8.1 Nối vào ShellX Link

`ShellXLinkHostController` phục vụ mỗi circuit bằng `LinkHost` (`shellx-link/Sources/ShellXLinkSession/
LinkHost.swift`), nối các nguồn ở `Sources/ShellX/Remote/ShellXRemoteService+App.swift`. Mỗi feature mới
theo đúng khuôn của `AgentSessionSource` / `AgentChatSource`:

- một protocol nguồn trong `ShellXLinkSession` (MIT, không phụ thuộc app) — ví dụ `WorkspaceSource`,
  `WorkspaceControl`, `TerminalSource`;
- các case `LinkMessage` mới, mã hoá / giải mã, golden vector trong `shellx-link/vectors/`;
- nhánh xử lý trong `LinkHost.converse`, và tên feature trong `welcome`;
- bản cài đặt phía app trong `Sources/ShellX/Remote/Link/` (ví dụ `ShellXLinkWorkspaceSource.swift`);
- client: hàm tương ứng trong `LinkClient`, dùng được từ `shellx-link-probe` để thử không cần iPhone.

### 8.2 Danh sách workspace và lệnh quản lý (đợt 1)

- **Danh sách**: lấy từ chỗ app mobile của cmux dựng hàng workspace: `MobileStateSync.buildRows()` /
  `workspaceRow` và bộ theo dõi Combine `MobileWorkspaceListObserver` (gộp 80 ms, chỉ chạy khi có người
  theo dõi). Hàng của cmux chưa có **nhánh git** và **cổng**; hai thứ này có trong `Workspace`
  (`Sources/Workspace.swift` ~3266), builder thêm vào. Surface lấy từ danh sách phẳng
  `TerminalController+MobileSurfaces.swift`, lọc `kind == terminal`. Builder chọn: gọi thẳng code dựng
  hàng hiện có, hay tách phần dựng hàng ra để hai host dùng chung; không sao chép logic.
- **Gắn terminal với phiên agent**: hàng terminal của cmux có `agent_source` / `agent_state`; nguồn phiên
  của Link (`ShellXLinkSessionSource`) biết terminal của từng phiên Claude Code. Builder nối hai thứ để
  điền `Terminal.session_id`.
- **Tạo workspace**: đường `workspace.create` của mobile cmux (`TerminalController.swift` ~15646,
  `TerminalController+WorkspaceCreate.swift`) đã ép `focus=false`; kế thừa thư mục từ workspace đang chọn
  kể cả khi không chọn workspace mới (`TabManager.addWorkspaceIfActive`). Không đi theo đường tạo của
  bridge ShellX (`TerminalControllerBridgeHost.swift:48`, `focus: true`).
- **Đổi tên**: `workspace.action` `rename` của mobile (`TerminalController.swift` ~15945).
- **Đóng workspace**: `v2MobileWorkspaceClose` (`TerminalController+MobileWorkspaceList.swift` ~320), đã từ
  chối workspace cuối cùng.
- **Đợt 2 — mở / đóng terminal**: `mobile.terminal.create` (focus false) và `mobile.terminal.close` (từ
  chối terminal cuối cùng của workspace).
- Mọi lệnh chạy trên main actor theo `cmux-socket-policy`: không đổi lựa chọn, không đưa cửa sổ lên trước,
  không mở hộp thoại trên Mac.

### 8.3 Terminal (đợt 2)

- **Đầu ra**: `MobileTerminalRenderObserver` dựng lưới theo nhịp Ghostty, `MobileTerminalFramePacer` điều
  tốc (sàn 90 ms, bỏ qua điều tốc cho tiếng vọng phím gõ), các khung là delta nối theo `renderRevision`.
  Ảnh ban đầu: `v2MobileTerminalReplay` (`TerminalController.swift` ~16206) với neo `screen` (điện thoại
  tự giữ scrollback, không cuộn theo Mac) **[người viết]**, giới hạn 240 dòng lịch sử qua tham số
  `max_scrollback_rows`; trang cũ hơn cho `terminal.history.get` (mục 7.2).
- **Đầu vào**: `v2MobileTerminalInput` → `TerminalSurface.sendInputResult`; phím có tên đi theo đường phím
  chứ không qua chữ.
- **Kích thước**: theo mục 10, qua bộ chia kích thước chung (`TerminalController+SharedSizing.swift`,
  `docs/shared-terminal-sizing.md`, `applyMobileViewportReport`).
- Mỗi phiên Link chỉ giữ một hàng đợi đầu ra có giới hạn cho mỗi terminal đang mở; đầy thì bỏ khung trung
  gian và gửi ảnh đầy đủ ở khung sau.

## 9. An toàn: viết lại PROTOCOL.md §10

Hôm nay §10 cấm điện thoại mở terminal, gõ vào bất cứ gì ngoài agent đang sống, và nói "không trường nào
gọi tên workspace hay terminal để host mở, chạy hay gõ vào". Spec này mở rộng có chủ đích, theo yêu cầu
của người dùng (G2, G3) và theo mô hình tin cậy đã chốt ở spec iOS §7.6: điện thoại đã ghép cặp được tin
như chính người dùng ngồi ở Mac; danh sách cho phép giới hạn **đối tượng** điện thoại chạm tới, không cắt
tính năng. Builder viết lại §10 với bảng cho phép mới, trả lời rõ ba câu hỏi của
`skills/cmux-socket-policy/references/remote-relay-authorization.md` cho từng lệnh:

| Câu hỏi | Trả lời trong thiết kế này |
| --- | --- |
| Chạy lệnh hoặc mở nội dung trên Mac? | **Có, có chủ đích**: gõ vào terminal (đợt 2), tạo workspace / terminal (chạy shell mặc định của người dùng). Không lệnh nào mang dòng lệnh, đường dẫn, thư mục, biến môi trường, URL hay tên chương trình: tạo workspace chỉ có `call_id`; thư mục do Mac chọn như khi người dùng bấm ＋ trên Mac. |
| Sửa / phá đối tượng không thuộc phiên? | Chỉ đối tượng **của chính Mac này**: workspace cục bộ trong cửa sổ chính, terminal của chúng. Id tra trong danh sách của host; không có là `not_found`. Workspace SSH / máy ở xa không liệt kê, không điều khiển được. Đóng workspace / terminal giữ luật của Mac (không đóng cái cuối cùng). |
| Đọc trạng thái mà điện thoại không cần? | Đọc tên, thư mục, nhánh, cổng, tên tab và **nội dung màn hình terminal**: đúng thứ người dùng thấy trên Mac. Không đọc cài đặt Mac, file, biến môi trường, scrollback ngoài số dòng giới hạn. |

Thêm các luật:

- `terminal.input` chỉ đi vào terminal mà chính phiên Link đó đang mở; gõ vào terminal chưa mở hoặc đã
  đóng là `not_found`, không bao giờ rơi sang terminal khác (khác với `chat.send`, ở đây gõ vào shell là
  mục đích, nên không có luật "agent còn sống").
- MDM `DisableRemoteControl` / chặn truy cập đến: Link host đã tắt hẳn (`MobileRemoteControlPolicy`); thêm
  vào đó mọi lệnh `workspace_control` và `terminal.input` trả `refused` nếu chính sách đổi giữa phiên.
- Gỡ ghép cặp trên Mac đóng ngay mọi phiên Link của điện thoại, kể cả các terminal đang mở.
- Host không ghi log nội dung terminal, phím gõ, tên workspace hay tên tab.
- Bộ nhớ có giới hạn cho mỗi client (8.3); một client chậm không làm Mac chậm.
- `RemoteRelayCommandPolicy` của `cmux ssh` không đổi. Không thêm method socket v2 nào; nếu builder buộc
  phải thêm thì method đó nằm ngoài allowlist relay, kèm test từ chối trong `RemoteCLIRelayPolicyTests`.
- PR của mỗi đợt mang phần phân tích này (CLAUDE.md, "Remote CLI relay").

## 10. Kích thước terminal (đợt 2)

Dùng lại quyết định T9 của spec chia sẻ terminal (`2026-10-01-desktop-terminal-sharing-design.md` §5.5):
**kích thước theo bên hoạt động gần nhất, như tmux** **[người viết, theo quyết định cũ của người dùng]**.

- Điện thoại mở terminal, gõ, hoặc xoay màn hình → terminal lấy kích thước điện thoại (số cột vừa bề ngang
  với cỡ chữ mặc định của app).
- Gõ phím trên Mac hoặc đổi kích thước cửa sổ Mac → terminal về khổ cửa sổ Mac. Lúc đó điện thoại vẽ lưới
  rộng hơn màn của nó bằng cách thu nhỏ chữ cho vừa bề ngang, chụm hai ngón để phóng to; gõ trên điện
  thoại thì lại về khổ điện thoại.
- Điện thoại đóng terminal / mất kết nối → về khổ Mac.
- Bộ chia kích thước của Mac đã có kiểu `latest` (bên hoạt động gần nhất); mặc định toàn cục là `smallest`.
  Builder làm cho terminal có điện thoại ShellX Link tham gia chạy theo `latest`, không đổi hành vi với
  các client khác.

## 11. Kiểm thử, dogfood, phát hành

- **shellx-link**: test mã hoá cho mọi message mới, golden vector, test `LinkHost` với nguồn giả (theo
  khuôn test hiện có), test chia mảnh và quy tắc revision. Lệnh `shellx-link-probe` mới để liệt kê
  workspace, tạo / đổi tên / đóng, và (đợt 2) xem / gõ một terminal từ dòng lệnh.
- **Mac**: test hành vi cho lớp nối — hàng workspace map đúng trường; tạo workspace không đổi workspace
  đang chọn; id lạ trả `not_found`; gõ vào terminal chưa mở bị từ chối; MDM chặn trả `refused`. Chạy bằng
  `scripts/shellx/test-app.sh <Suite>`; thêm file test thì chạy `scripts/sync-test-wiring`. Theo
  CLAUDE.md: commit test đỏ trước bản sửa với lỗi hành vi.
- **iOS**: test model trong `ShellXAppCore` (kho danh sách workspace theo revision, kết quả lệnh, suy ra
  trạng thái dòng workspace, bộ gom mảnh lưới ở đợt 2); render test PNG cho màn danh sách, màn workspace,
  ô giữ chỗ, terminal; Mac giả trong chế độ demo. `scripts/shellx/check-ios-license.sh` phải xanh.
- **Dogfood mỗi đợt**:
  - Mac: builder build Release cục bộ ở một thư mục DerivedData riêng. Người dùng đang chạy ShellX từ
    `build-shellx/…/Release/ShellX.app`; builder **không** thoát, thay hay mở lại app đó mà đưa người dùng
    lệnh ngắn để tự đổi.
  - iPhone: `shellx-ios/scripts/dev.sh device --device-id 51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107` (máy phải mở
    khoá).
  - Đo các tiêu chí 2.2 bằng `LatencyLog` sẵn có, ghi kết quả vào ledger.
- **Phát hành**: công khai bản desktop mới (1.5.2+) và bản iOS lên TestFlight là quyết định của người dùng,
  theo quy trình trong memory phát hành; spec này không tự phát hành.

## 12. Để lại cho người làm

- Tên chính xác và trường phụ của các message mới, ngoài những gì mục 7 đã chốt; thứ tự cắt khi quá
  frame.
- Dùng thẳng hay tách phần dựng hàng workspace của cmux (8.2), miễn không sao chép logic.
- Định dạng lưới gửi qua Link (nguyên `cmux.render-grid.v1` hay bản rút gọn) và phong bì chia mảnh.
- Cách vẽ lưới trên iOS (SwiftUI Canvas, Core Text…), miễn đạt tiêu chí 2.2 và nằm trong ranh giới giấy
  phép.
- Cỡ chữ terminal mặc định trên điện thoại và cử chỉ phóng to.
- Dữ liệu Mac giả cho chế độ demo.
- Cách lưu trạng thái "chip đang chọn" của từng workspace trên điện thoại (nếu có).
- Mọi chi tiết UI chưa ghi ở mục 6 thì theo mockup `workspace-v2.html` và gu màu đã chốt.
