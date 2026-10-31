# ShellX mobile: màn chính xếp theo việc cần làm và nút đóng agent — đặc tả thiết kế

Ngày: 29/10/2026. Nguồn: phiên brainstorm cùng ngày; mockup ở
`.superpowers/brainstorm/15486-1793251125/content/home-focus.html` (thư mục bị gitignore, chỉ có trên máy
người dùng). Nhãn **[người dùng]** là điều người dùng nói hoặc chọn; **[người viết]** là lựa chọn của
người viết spec, người dùng chưa duyệt riêng.

Spec này sửa mục 6.1 (màn chính "Workspace") của
`2026-10-28-shellx-mobile-workspaces-design.md` (gọi tắt "spec đợt 1"). Chỗ nào hai spec khác nhau về màn
chính thì spec này thắng; phần còn lại của spec đợt 1 giữ nguyên.

## 1. Ý định và lý do

Người dùng mở app iOS và thấy **nhiều dòng cùng tên**: "tôi sẽ nhìn thấy nhiều pane giống tên nhau". Họ
xác nhận nguyên nhân người viết đoán: mỗi dòng mang tên workspace, mà nhiều agent chạy trong cùng một
workspace ("shellx"), nên năm, sáu dòng trùng tên; dòng đang chạy và dòng đã kết thúc trông như nhau, phải
mở từng dòng mới biết. Lời gốc: "nhiều session ended rồi vẫn còn hiện gây nhiễu, chưa có tính focus hay
group thông minh" **[người dùng]**.

Nguồn của các dòng đã kết thúc: Mac cố ý gửi kèm tối đa 20 phiên đã kết thúc còn đọc được chat
(`ShellXLinkSessionSource.maxEndedSessions`), và iPhone cho chúng vào "Phiên agent khác" lẫn với phiên
đang chạy (`MachineHub.otherSessions`).

Người dùng chọn **hướng A, "Xếp theo việc cần làm"** trong mockup (so với B gộp theo workspace, C khung
"Đang diễn ra" + workspace gọn) **[người dùng]**. Về phiên đã kết thúc, họ nói: "session nào đã tắt và
không còn hiện trên desktop app nữa thì ở mobile cũng nên xoá đi", rồi chốt "đóng rồi thì đưa vào ended,
tab quá 12h tự remove", và 12 giờ là **trên điện thoại**, không đóng tab trên Mac **[người dùng]**.

Cuối phiên họ thêm: "cho phép có button đóng agent", và "đóng là tắt hẳn": agent bị tắt trên Mac, không
chỉ ẩn khỏi điện thoại **[người dùng]**.

### 1.1 Hai phần [người viết]

- **Phần 1: màn chính** (mục 6.1–6.4). Chỉ sửa iOS, chạy được với Mac 1.5.1 đang dùng. Cài lên iPhone ngay
  khi xong.
- **Phần 2: nút Đóng agent** (mục 6.5). Thêm một lệnh vào ShellX Link, phần Mac và nút trên iOS. Cần một bản
  ShellX desktop mới; với Mac chưa có lệnh này, nút không hiện.

## 2. Mục tiêu

- **G1. Mở app là thấy cái cần làm trước**: trên cùng là ba nhóm theo trạng thái, **Cần bạn → Đang chạy →
  Vừa xong** **[người dùng chọn A]**.
- **G2. Mỗi dòng phân biệt được**: tên dòng là **việc agent đang làm** (tiêu đề phiên); workspace chỉ là
  dòng phụ **[người dùng chọn A]**.
- **G3. Phiên đã kết thúc không chen vào**: gấp vào một dòng **"Đã kết thúc · N"** ở cuối; mỗi phiên tự
  biến mất khỏi điện thoại sau **12 giờ** kể từ lúc kết thúc **[người dùng]**.
- **G4. Workspace vẫn tới được từ màn chính**: danh sách workspace nằm dưới ba nhóm **[người dùng chọn A]**.
- **G5. Tắt một agent từ điện thoại**: nút Đóng tắt hẳn agent trên Mac; phiên chuyển vào "Đã kết thúc"
  **[người dùng]**.

Thành công nghĩa là, với cảnh trong mockup (một Mac, workspace "shellx" có ba agent sống và bốn phiên đã
kết thúc, "toknix" có một agent chạy):

- phần trên chỉ có các agent sống, mỗi dòng một tên khác nhau;
- không phiên đã kết thúc nào hiện ngoài dòng "Đã kết thúc · N";
- một phiên kết thúc quá 12 giờ không hiện ở bất kỳ đâu trên điện thoại;
- tất cả vẫn đúng khi Mac chạy ShellX 1.5.1 (bản công khai hiện tại, chưa có `workspaces`).

## 3. Không làm (non-goals)

- **Phần 1 không đổi phía Mac** **[người viết]**. Mac vẫn gửi tới 20 phiên đã kết thúc; iPhone tự lọc 12
  giờ. Lý do: chạy được ngay với Mac 1.5.1 đã phát hành, không chờ một bản desktop mới. Phía Mac chỉ đổi
  cho lệnh đóng agent ở phần 2.
- **Không tự đóng tab trên Mac** sau 12 giờ **[người dùng]**.
- Không có trang lịch sử cho phiên quá 12 giờ.
- Không đổi luật nút ＋. Nó tắt vì Mac 1.5.1 không báo `workspace_control`; nó sẽ bật khi Mac chạy bản có
  đợt 1. Người dùng đã được giải thích.
- Không đổi màn workspace (hàng chip, pane) và đợt 2 (terminal thật).
- Không lưu trạng thái "Vừa xong" qua các lần mở app (giống `finishedSessionIds` hiện nay).

## 4. Điều tuyệt đối tránh (anti-goals)

- Điện thoại hiện một phiên đã kết thúc quá 12 giờ.
- Ba nhóm trên cùng đầy dòng cũ hoặc trùng tên: mất đúng thứ người dùng xin, "focus".
- Mất đường tới một phiên **đang sống**: mọi phiên chưa kết thúc phải tới được từ màn chính, qua ba nhóm,
  qua workspace của nó, hoặc qua "Agent ngoài workspace".
- Nút gradient, quầng sáng, màu gắt (gu màu đã chốt ở spec đợt 1 §6).

## 5. Ràng buộc

- Mã nằm trong `shellx-ios/` (app `ShellX/`, model `Packages/ShellXAppCore`). Màn chính phải tiếp tục dựng
  được từ giá trị thuần, như `WorkspaceListScreen` hôm nay, để `ShellXTests/WorkspaceListRenderTests.swift`
  chụp được mọi trạng thái.
- Dữ liệu có sẵn cho mỗi phiên (giao thức hiện tại, không thêm trường): `title` (có thể vắng: Mac bỏ nó
  đầu tiên khi frame quá lớn), `agent`, `workspaceTitle`, `workspaceId`, `state` (`idle`, `working`,
  `needs_input`, `ended`), `stateSinceMs` (với `ended` là lúc kết thúc, có thể vắng), `lastActivityMs`.
- Chữ mới có cả tiếng Anh và tiếng Việt trong `ShellX/Localizable.xcstrings` (skill cmux-localization).
- Màu theo spec đợt 1 §6: chờ bạn = `#60a5fa`, chạy = vàng dịu, xong = xanh lá dịu, nền `#0b0716`, khối
  `#17122a`; giao diện sáng giữ như hiện có.

## 6. Thiết kế

### 6.1 Bố cục màn chính, từ trên xuống [người dùng chọn A; chi tiết theo mockup]

- **Thanh trên**: tiêu đề "ShellX" **[người viết]**, vì màn này không còn chỉ là workspace. Bên phải giữ
  chuông (đếm và mở trang yêu cầu), ＋, Cài đặt như hiện nay.
- **Bỏ thanh "Cần bạn · N"** ở màn chính: nhóm "Cần bạn" thay vai nó; chuông vẫn mở trang yêu cầu. Thanh
  "Cần bạn" trong màn agent / workspace giữ nguyên **[người viết; người dùng nghe đề xuất, không phản đối]**.
- **Nhóm "Cần bạn · N"**: mỗi agent đang chờ bạn một thẻ viền xanh; tên việc, nhãn "Cần bạn", dòng phụ,
  và câu hỏi trong ngoặc kép khi có. N đếm thẻ (phiên), không đếm yêu cầu; chuông vẫn đếm yêu cầu.
  `PendingItem` không có `sessionId`, nên ghép yêu cầu với phiên theo (Mac, `workspaceId`, `agent`), giống
  `WorkspaceScreenModel.defaultChoice` **[người viết]**:
  - mỗi phiên `needs_input` là một thẻ; câu hỏi của yêu cầu gắn vào phiên khớp hoạt động gần nhất;
  - yêu cầu không có phiên `needs_input` nào khớp: đưa phiên sống khớp hoạt động gần nhất vào nhóm;
  - không có phiên nào khớp (ví dụ `workspaceId` là id workstream của phiên SSH): không có thẻ, yêu cầu
    vẫn ở chuông.
- **Nhóm "Đang chạy · N"**: chấm vàng, nhãn bên phải là thời gian đã chạy.
- **Nhóm "Vừa xong · N"**: chấm xanh lá, nhãn "Xong", dòng phụ kết thúc bằng "… trước".
- Nhóm nào trống thì ẩn cả tiêu đề. Cả ba trống thì một dòng chữ mờ "Không có agent nào đang chạy"
  **[người viết]**.
- **Mục "Workspace"**: theo từng Mac như hôm nay (đầu nhóm `MachineGroupHeader`, Mac mặc định trước). Mỗi
  workspace một dòng gọn: tên bên trái, nhánh git chữ mono bên phải (theo mockup A). Chạm mở màn workspace;
  vuốt trái Đổi tên / Đóng như hiện có. Thẻ "Cập nhật ShellX trên Mac" cho Mac chưa có workspace giữ nguyên.
- **Dòng "Agent ngoài workspace · N"** cuối mỗi nhóm Mac (đổi tên từ "Phiên agent khác"), chỉ hiện khi
  N > 0: các phiên **chưa kết thúc** không gắn được vào workspace nào. Với Mac 1.5.1 đó là mọi phiên sống.
- **Dòng gấp "Đã kết thúc · N"** ở cuối màn, gộp mọi Mac, chỉ hiện khi N > 0. Chạm mở một trang liệt kê
  các phiên đó, mới kết thúc trước; chạm một phiên mở màn agent (chỉ đọc, như hôm nay với phiên đã kết
  thúc).
- Kéo xuống để làm mới: giữ.

### 6.2 Tên và dòng phụ của một agent

Luật này dùng cho **mọi danh sách phiên** trên điện thoại: ba nhóm, "Agent ngoài workspace" và trang
"Đã kết thúc". Với Mac 1.5.1, các phiên rảnh đã xem chỉ nằm ở "Agent ngoài workspace", nên nếu danh sách
đó giữ tên workspace thì lỗi "shellx, shellx, shellx" vẫn còn.

- **Tên**: `title` của phiên khi có. Lưu ý: trên Mac, `title` là **câu đầu tiên người dùng gõ cho agent**,
  cắt 80 ký tự, đặt một lần (`AgentChatTranscriptTailer.title`); nó không đổi theo việc agent làm sau đó.
  Điện thoại làm sạch trước khi hiện **[người viết]**: lấy dòng đầu không trống, bỏ lệnh slash và thẻ kiểu
  `<…>` ở đầu, gọn khoảng trắng.
- Không có `title`, hoặc làm sạch xong còn rỗng: `<agent> · HH:mm` theo giờ hoạt động cuối **[người viết]**.
- Hai dòng trong cùng danh sách **hiện ra** giống nhau thì thêm ` · #2`, ` · #3`… vào các dòng sau, theo
  thứ tự `sessionId` để số không nhảy khi agent hoạt động **[người viết]**.
- **Dòng phụ**: `workspace · agent · thời gian`; có hơn một Mac đã ghép cặp thì thêm tên Mac
  **[người viết; người dùng nghe đề xuất, không phản đối]**.
- **Chạm**: mở màn agent của phiên đó (đường `SessionRef` hiện có).

### 6.3 Phiên nằm ở đâu

| Trạng thái của phiên | Nằm ở |
| --- | --- |
| `needs_input`, hoặc có yêu cầu đang chờ | Cần bạn |
| `working` | Đang chạy |
| `idle`, xong một lượt chưa quá 1 giờ và bạn chưa xem (`finishedSessionIds`) | Vừa xong |
| `idle`, đã xem | không ở ba nhóm; tới qua workspace hoặc "Agent ngoài workspace" |
| `ended`, kết thúc chưa quá 12 giờ | Đã kết thúc |
| `ended`, quá 12 giờ hoặc không biết lúc kết thúc | ẩn khỏi mọi nơi trên điện thoại |

- **Tuổi** của phiên đã kết thúc = bây giờ − `stateSinceMs`; vắng thì dùng `lastActivityMs`; vắng cả hai
  thì coi như quá 12 giờ **[người viết]**.
- Phiên rời "Vừa xong" khi bạn mở màn agent của nó (mới), khi bạn mở workspace của nó (`markSeen` hiện
  có), khi nó chạy lại, hoặc **1 giờ sau khi xong** **[người viết; người dùng giao "bạn đề xuất đi"]**. Mac
  1.5.1 không gửi giờ xong (`idle` không có `stateSinceMs`), nên `MachineHub` tự ghi giờ điện thoại thấy
  phiên xong lượt, cùng chỗ với `finishedSessionIds`.
- Phiên tự biến mất đúng lúc đủ 12 giờ khi màn đang mở, không cần mở lại app **[người viết]**.
- Mac ngoại tuyến: phiên của nó không hiện ở ba nhóm (không làm gì được với nó); Mac đang kết nối lại thì
  hiện mờ, như dòng workspace hôm nay **[người viết]**.

### 6.4 Số phận các phần hiện có

- `NeedsYouBar` trên màn chính: bỏ (vẫn dùng ở nơi khác nếu có).
- `OtherSessionsView`: đổi tiêu đề thành "Agent ngoài workspace", **không** còn liệt kê phiên đã kết thúc,
  đặt tên dòng theo 6.2.
- `WorkspaceRowView` (thẻ có dòng mono, nhãn trạng thái, câu hỏi): màn chính dùng dòng gọn ở 6.1; thẻ cũ
  hết chỗ dùng thì xoá.
- Chế độ demo (`--demo`) và render test: thêm cảnh trong mockup để chụp.

### 6.5 Nút Đóng agent (phần 2)

- **Hành vi** **[người dùng]**: tắt hẳn agent trên Mac. Mac đóng tab terminal đang chạy agent, đúng như
  người dùng đóng tab đó trên desktop. Phiên thành `ended` và chuyển vào "Đã kết thúc" trên điện thoại.
- **Chỗ đặt nút** **[người viết]**:
  - vuốt trái một dòng agent ở ba nhóm: nút "Đóng", giống vuốt dòng workspace;
  - một mục "Đóng agent" trong màn agent.
  - Trang "Đã kết thúc" không có nút này: phiên đã tắt rồi.
  - "Agent ngoài workspace" cũng không có nút này (quyết định khi review cuối, 2026-10-31): đó là các phiên
    không terminal nào trong workspace của Mac ghi tên, nên Mac không bao giờ đóng được chúng (`not_found`).
- **Hỏi lại** **[người viết, theo spec đợt 1 §6.3]**: luôn có hộp xác nhận ghi tên agent và "Tab terminal
  của agent trên Mac sẽ bị đóng". Đã xác nhận trên điện thoại thì Mac **không** hỏi lại, kể cả khi agent
  đang chạy: Mac đóng tab như `surface.close` với `force=true`.
- **Luật của Mac giữ nguyên** **[người viết]**. Tab đó là tab cuối của pane hay workspace thì xảy ra đúng
  điều desktop làm khi đóng tab cuối. Mac từ chối (managed policy chặn điều khiển từ xa, tab không đóng
  được) thì điện thoại báo lý do bằng alert như các lệnh workspace.
- **Giao thức** **[người viết; tên chính xác để người làm chọn]**: một feature mới (ví dụ `agent_close`),
  một lệnh client `agent.close` (`call_id`, `session_id`), và trả lời `agent.close.result` (`call_id`,
  `outcome`). Bộ `outcome` giống `workspace.close.result`: `ok`, `not_found`, `refused`, `failed`. Mac chỉ
  đóng phiên nó đang liệt kê và có tab terminal **cục bộ** trên Mac. Phiên SSH hoặc phiên không có tab trả
  `not_found`. Không gửi lại lệnh sau khi mất kết nối, như các lệnh workspace.
- **An toàn**: lệnh chỉ tắt một tab mà điện thoại đã thấy trong danh sách, không chạy lệnh hay nội dung
  nào trên Mac. Cập nhật `shellx-link/spec/PROTOCOL.md` §10 theo cách spec đợt 1 §9 đã làm cho
  `workspace.close`.
- Mac chưa có feature này (gồm 1.5.1): không hiện nút vuốt, không hiện mục trong màn agent.

### 6.6 Đóng một tab bất kỳ (phần 3, thêm 2026-10-31)

- **Hành vi** **[người dùng, 2026-10-31: "các tab đang running cũng nên cho phép đóng từ mobile", chọn "Đóng mọi
  tab"]**: điện thoại đóng được **mọi** tab terminal của một workspace cục bộ trên Mac, kể cả tab chỉ chạy shell
  hay một lệnh (dev server, build…). Mac đóng tab đó như người dùng đóng trên desktop, dừng mọi thứ đang chạy
  trong nó. Luật tab cuối giống 6.5: tab cuối của workspace thì đóng workspace (mặc định), Mac bật "Keep Workspace
  Open" thì từ chối.
- **Chỗ đặt** **[người dùng chọn "menu ••• + nhấn giữ tab"]**:
  - menu `•••` của màn workspace: mục "Đóng tab…" cho tab đang hiện (agent hay shell). Mục "Đóng agent…" của
    menu này gộp vào "Đóng tab…";
  - nhấn giữ một chip tab bất kỳ: menu ngữ cảnh có "Đóng tab…".
  - Vuốt đóng agent ở màn chính và mục "Đóng agent…" trong màn agent giữ như 6.5.
- **Hỏi lại**: luôn có hộp xác nhận ghi tên tab và "Tab và mọi thứ đang chạy trong nó trên Mac sẽ bị dừng".
  Đã xác nhận thì Mac không hỏi lại (`force=true`).
- **Giao thức**: feature `terminal_close`, lệnh `terminal.close` (`call_id`, `workspace_id`, `terminal_id`), trả lời
  `terminal.close.result` (`call_id`, `outcome`) với bộ `outcome` như `workspace.close.result`. Mac chỉ đóng một
  terminal có trong một workspace cục bộ nó đang liệt kê; khác đi thì `not_found`. Bị quản lý thiết bị chặn điều
  khiển từ xa thì `refused`. Không gửi lại sau khi mất kết nối.
- **An toàn**: lệnh chỉ mang hai id, không chạy lệnh hay nội dung nào; chỉ chạm tab mà điện thoại đã thấy trong
  `workspace.list`; không bao giờ là workspace SSH/từ xa. Cập nhật PROTOCOL.md §10 như 6.5.
- Mac chưa có `terminal_close`: không hiện "Đóng tab…" ở đâu cả.

## 7. Kiểm thử và dogfood

- **ShellXAppCore**: test cho phần chia nhóm (đầu vào: phiên, yêu cầu đang chờ, `finishedSessionIds`,
  bây giờ; đầu ra: ba nhóm, danh sách "Đã kết thúc"), gồm mốc đúng 12 giờ, phiên không có giờ, đặt tên khi
  thiếu `title` và khi trùng tên.
- **Render test** `WorkspaceListRenderTests`: cảnh mockup; Mac 1.5.1 (không workspace); không agent nào;
  hai Mac.
- **Dogfood**: cài lên iPhone bằng `shellx-ios/scripts/dev.sh device --device-id
  51B0EA4F-D2C2-56A2-AC2B-3CD87DBAC107` (máy phải mở khoá). Phần 1 dùng với Mac đang chạy 1.5.1 của
  người dùng, không cần build Mac.
- **Phần 2**:
  - shellx-link: test mã hoá và golden vector cho `agent.close`; test `LinkHost` với nguồn giả.
  - Mac: test hành vi cho các trường hợp đóng được, phiên lạ `not_found`, phiên SSH hoặc không có tab
    `not_found`, policy chặn `refused`. Chạy bằng `scripts/shellx/test-app.sh <Suite>`; thêm file test thì
    chạy `scripts/sync-test-wiring`. Commit test đỏ trước bản sửa (CLAUDE.md).
  - iOS: nút ẩn với Mac không có feature; xác nhận rồi mới gửi; alert theo `outcome`.
  - Dogfood: build Release cục bộ ở một thư mục DerivedData riêng. Người dùng đang chạy ShellX từ
    `build-shellx/…/Release/ShellX.app`; người làm **không** thoát, thay hay mở lại app đó mà đưa người
    dùng lệnh ngắn để tự đổi.

## 8. Để lại cho người làm

- Đặt logic chia nhóm ở đâu trong `ShellXAppCore` và tên kiểu, miễn test được không cần UI.
- Nhịp cập nhật thời gian và hết hạn 12 giờ (ví dụ `TimelineView` mỗi phút).
- Chữ chính xác của các nhãn mới, theo giọng các chuỗi hiện có.
- Tên chính xác của feature, message và chỗ đặt mã đóng tab phía Mac. Tìm tab của phiên từ
  `AgentChatSessionRecord.surfaceID` và dùng lại đường `surface.close` có sẵn, không viết logic đóng tab mới.
- Có cần Mac báo trước phiên nào đóng được (để ẩn nút sớm) hay để điện thoại hiện nút rồi nhận `not_found`.
- Mọi chi tiết UI chưa ghi ở mục 6 thì theo mockup hướng A và gu màu đã chốt.
