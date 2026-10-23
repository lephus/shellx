# Tab đang chọn rõ ràng và hiệu ứng agent trên desktop Mac: đặc tả thiết kế

Ngày 23/10/2026. Phạm vi là app ShellX trên macOS. Bản phác người dùng đã chọn nằm ở
`docs/superpowers/design/2026-10-23-tab-selection-agent-effects/`, mở thẳng bằng trình duyệt là xem được.

## 1. Vấn đề và lý do

Người dùng chạy nhiều agent cùng lúc và hay không biết mình đang làm việc ở phiên nào, tab nào:

- Phiên đang chọn ở sidebar chỉ đổi nền từ `panel` (`#100b1d`) sang `raise` (`#171128`). Tương phản giữa hai màu khoảng 1.05:1, gần như không thấy.
- Tab đang chọn trên thanh tab của pane chỉ sáng hơn nền thanh một chút, kèm một vạch 1.5 pt màu nhấn của hệ thống.

Người dùng cũng muốn app "nhìn đẹp và có vẻ chuyên nghiệp", giống chữ "ultracode" trong Claude Code: tên phiên chạy màu khi agent đang làm việc, và sáng lên khi agent gọi skill hoặc workflow.

## 2. Mục tiêu

1. Liếc qua là biết phiên nào đang chọn ở sidebar, và tab nào đang nhận phím gõ.
2. Liếc qua là biết agent nào đang làm việc, agent nào đang chạy skill hoặc workflow.
3. Đẹp, chuyên nghiệp, không mỏi mắt và không làm app chậm đi.

**Tiêu chí thành công** (mức số do người viết spec chọn):

- Nền phiên đang chọn tương phản ít nhất 1.4:1 với nền sidebar, và tên phiên in đậm.
- Mỗi cửa sổ có đúng một tab màu xanh: tab đang chọn của pane đang focus.
- Mọi màu dùng cho tên đang chạy hiệu ứng đạt tương phản ít nhất 4.5:1 với nền của dòng đó, kể cả nền xanh của phiên đang chọn.
- Có 8 phiên cùng chạy hiệu ứng mà độ trễ gõ phím không tăng so với trước khi đổi (sai khác nằm trong nhiễu đo), và main thread không phải vẽ lại theo từng khung hình của hiệu ứng.

## 3. Không làm

- App Windows (Rust, `windows/`) và app iOS. Hai app này làm sau, mỗi app là một việc riêng.
- Giao diện sáng. Spec gốc chỉ có giao diện tối; khi sidebar sáng (theme terminal sáng) thì giữ nguyên cách tô hiện nay.
- Đổi màu hay chữ của nhãn trạng thái (chờ bạn, chạy, xong, lỗi).
- Tiến độ workflow kiểu "3/8 agent". Bản phác có dòng này để minh hoạ, nhưng hiện app không có dữ liệu đó.
- Thêm mục cài đặt bật/tắt hiệu ứng. Ai cần tắt thì dùng "Giảm chuyển động" của macOS (§6.4). Đây là lựa chọn của người viết spec.

## 4. Điều tuyệt đối tránh

- **Mỏi mắt.** Không màu chói, không nhấp nháy liên tục, không quầng sáng hay bóng mờ (blur, glow). Lóe sáng chỉ xảy ra một nhịp, lúc skill hoặc workflow bắt đầu.
- **App chậm đi.** Không được làm tăng độ trễ gõ phím, làm giật sidebar, hay tốn CPU khi cửa sổ không hiện.
- **Lẫn "đang chọn" với "chờ bạn".** Cả hai đều dùng màu xanh chủ đạo. "Chờ bạn" vẫn là nhãn có viền; "đang chọn" là nền phủ cả dòng hoặc cả tab.
- **Tên không đọc được** khi đang chạy màu.
- **Sidebar nhảy chiều cao** mỗi lần agent bắt đầu hay xong một lượt.

## 5. Quyết định của người dùng (23/10/2026)

Người dùng chọn trên bản phác:

- **Tab đang chọn: phương án B, "nền xanh dịu".** Áp dụng cho cả dòng phiên ở sidebar lẫn tab trên thanh tab của pane. Xem `tab-dang-chon.html` và `tab-dang-chon-b.html`.
- **Hiệu ứng: phương án C, "tên phiên đổi màu".** Đây là bản giống "ultracode" nhất: chính tên phiên và tên tab chạy màu. Xem `hieu-ung-trang-thai.html`.
- **Làm cho desktop Mac trước.**
- Lý do người dùng muốn hiệu ứng: "nhìn đẹp và có vẻ chuyên nghiệp".

Spec gốc §7.4 cấm gradient và quầng sáng trên mọi thành phần giao diện. Quyết định trên tạo một ngoại lệ có chủ đích: chỉ chữ tên phiên và tên tab được chạy màu (vàng lướt hoặc cầu vồng dịu) trong lúc agent hoạt động. Nút, nền và nhãn vẫn theo §7.4.

Những điểm dưới đây do người viết spec chọn. Người dùng đã nghe tóm tắt và đồng ý: tab xanh chỉ có ở pane đang focus; nhãn trạng thái có nền tối khi nằm trên dòng đang chọn; cách tô khi chọn nhiều phiên và khi rê chuột; màu theo màu nhấn của ShellX; khi app không ở phía trước thì màu dịu đi; dòng hoạt động dưới tên phiên; mỗi tab có trạng thái riêng và dòng phiên lấy trạng thái mạnh nhất; cách nhận biết qua hook (tính cả `/tên-skill`); agent khác Claude Code chỉ có vệt vàng; thời điểm skill và workflow kết thúc; "Giảm chuyển động"; hiệu ứng chỉ chạy khi cửa sổ đang hiện; Windows làm sau.

## 6. Thiết kế

### 6.1 Phiên đang chọn ở sidebar

Áp dụng cho sidebar tối, khi người dùng chưa đặt màu chọn riêng (`sidebarSelectionColorHex`) và chưa chọn kiểu chỉ báo `solidFill`. Nếu người dùng đã đặt một trong hai thì cài đặt của họ vẫn thắng.

| Trạng thái dòng | Nền | Tên | Dòng phụ |
|---|---|---|---|
| Đang chọn | màu nhấn 22% trên `panel`, màu đặc (mặc định ra khoảng `#222d4e`) | đậm (semibold), `#f1f5ff` | `#b4c6e6` |
| Đang chọn, app không ở phía trước | màu nhấn 16% | như trên | như trên |
| Chọn thêm bằng ⌘-click | màu nhấn 10% | thường | như dòng thường |
| Rê chuột (chưa chọn) | xám tím `#1b1530`, không dùng màu xanh | như dòng thường | như dòng thường |
| Thường | trong suốt | `text-hi` | `muted` |

Nhãn trạng thái trên dòng đang chọn có thêm một lớp nền tối (`bg` khoảng 55%) dưới lớp màu 12%. Viền của nhãn "chờ bạn" sáng hơn (`#93c5fd` khoảng 80%), để nhãn vẫn đọc được trên nền xanh.

"Màu nhấn" ở đây là màu nhấn của ShellX: mặc định `primary` `#60a5fa`, đổi theo màu nhấn người dùng chọn trong Cài đặt.

### 6.2 Tab đang chọn trên thanh tab của pane

| Tab | Nền | Tên | Vạch dưới |
|---|---|---|---|
| Tab đang chọn của pane đang focus | màu nhấn 16% trên nền thanh tab | đậm, `#f1f5ff` | 2 pt màu nhấn, nằm ở cạnh dưới, nối vào terminal |
| Tab đang chọn của pane khác | `text-hi` 7% | đậm, `text` | 2 pt xám tím `#5b5478` |
| Tab khác | không | `muted` | không |

Khi app không ở phía trước, tab xanh dịu đi giống dòng phiên ở §6.1. Rê chuột lên tab chưa chọn thì nền xám nhạt, không dùng màu xanh.

### 6.3 Trạng thái hoạt động của agent

Mỗi tab terminal có một trạng thái hoạt động riêng:

| Trạng thái | Bắt đầu | Kết thúc |
|---|---|---|
| Không hoạt động | mặc định | — |
| Đang làm việc ("Đang nghĩ…") | agent bắt đầu một lượt: người dùng gửi lời nhắn, hoặc có lần gọi tool đầu tiên | agent hết lượt (`Stop` hoặc `StopFailure`), hoặc dừng lại hỏi người dùng (cần quyền, chờ trả lời) |
| Skill | agent gọi tool `Skill`, hoặc người dùng gửi lời nhắn bắt đầu bằng `/tên` và Claude Code chuyển lời nhắn đó cho model | agent hết lượt |
| Workflow | agent gọi tool `Workflow` | workflow chạy xong (xem §6.6) |

Skill và workflow luôn nằm "bên trên" đang làm việc. Khi lượt kết thúc, tab trở về không hoạt động. Nếu agent đang chờ người dùng thì tên đứng yên và nhãn "chờ bạn" hiện như hiện nay.

Dòng phiên ở sidebar lấy trạng thái mạnh nhất trong các tab của phiên, theo thứ tự workflow = skill > đang làm việc > không hoạt động. Nếu nhiều tab cùng chạy skill hoặc workflow thì lấy cái bắt đầu gần nhất.

Agent không phải Claude Code (Codex, v.v.) chỉ có trạng thái đang làm việc, lấy từ đúng nguồn mà nhãn "chạy" của nó đang dùng.

### 6.4 Hiệu ứng

**Đang làm việc: vệt vàng lướt qua tên.** Chữ tên đổi sang vàng đậm (`#b39550`). Một vệt sáng `#fff3cf` lướt từ trái sang phải, mỗi lượt khoảng 2.2 giây, lặp liên tục.

**Skill hoặc workflow: lóe sáng rồi cầu vồng dịu.**

- Lóe sáng chỉ một nhịp, lúc bắt đầu. Cả dòng phiên (hoặc cả tab) phủ một lớp tím nhạt (`rgba(214,196,255,.26)`) trong khoảng 150 ms, rồi mờ dần hết trong khoảng 800 ms.
- Sau đó chữ tên chạy dải màu pastel `#f4a7c0 → #f2c879 → #8fd9a8 → #7cc8e8 → #9fb0f5 → #c9a7f2 → #f4a7c0` từ trái sang phải, mỗi vòng khoảng 3 giây, cho tới khi trạng thái kết thúc.

**Ký hiệu ✻.** Đầu tên tab, và đầu dòng hoạt động ở sidebar, có ký hiệu đổi hình liên tục `· ✢ ✳ ✶ ✻ ✽`, giống Claude Code, mỗi hình khoảng 180 ms. Ký hiệu màu vàng `running` khi đang làm việc, và đổi dần qua các màu pastel khi chạy skill hoặc workflow.

**Dòng hoạt động** (chỉ ở sidebar). Dòng nhỏ dưới tên phiên ghi "Đang nghĩ…", "Skill · ‹tên skill›" hoặc "Workflow · ‹tên workflow›". Chữ dòng này đứng yên, màu chữ phụ; chỉ ký hiệu ✻ chuyển động. Dòng này không được làm sidebar nhảy chiều cao mỗi lượt (§4); người làm chọn cách giữ chỗ.

**Giảm chuyển động.** Khi bật "Giảm chuyển động" (Reduce Motion) trong macOS thì không có gì chuyển động. Đang làm việc: tên màu `running`. Skill hoặc workflow: tên tô dải pastel đứng yên. Không lóe sáng. Ký hiệu đứng yên ở hình ✻.

**Chỉ chạy khi nhìn thấy.** Hiệu ứng tạm dừng khi cửa sổ bị thu nhỏ, bị che hoàn toàn, hoặc dòng và tab nằm ngoài vùng nhìn thấy. App không ở phía trước nhưng cửa sổ vẫn hiện thì hiệu ứng vẫn chạy.

### 6.5 Chữ mới trên giao diện

Có ba chuỗi mới: "Đang nghĩ…", "Skill · %@" và "Workflow · %@". Bản tiếng Anh là "Thinking…", "Skill · %@" và "Workflow · %@". Các chuỗi này đi theo quy trình bản địa hoá của repo (skill `cmux-localization`).

**Vị trí dòng hoạt động và ký hiệu** (người viết spec chọn, để không thêm dòng mới):

- Ở sidebar, dòng hoạt động dùng lại dòng trạng thái của agent mà phiên đang hiện, tức dòng metadata của agent (ví dụ dòng "Running" của `claude_code`). Khi có hiệu ứng, dòng đó ghi chữ hoạt động. Nếu người dùng đang ẩn metadata, hoặc bật chế độ trạng thái gọn (một dòng), thì không có dòng hoạt động; chỉ tên chạy màu.
- Ở thanh tab, ký hiệu ✻ thế chỗ icon của tab trong lúc có hiệu ứng, nên tab không đổi bề rộng.

### 6.6 Nguồn dữ liệu

**Đang làm việc** lấy từ trạng thái agent theo từng pane mà app đang có: lifecycle `running` của pane, cùng work state `running`, `subagents` hoặc chưa có work state (`Workspace.agentLifecycleStatesByPanelId`, `Workspace.agentStatusEntriesByPanelId`). Đây chính là nguồn của nhãn "chạy". Mọi agent đều đi qua nguồn này, kể cả Codex.

**Skill và workflow** cần thêm một "dấu hoạt động" cho từng pane. Hiện app không lưu tên tool nào, và không có chỗ nào xét riêng tool `Skill` hay `Workflow`. Cách lấy dấu:

- App đọc sự kiện hook thô ngay lúc nhận, ở nhánh `agent.hook.enqueue` của `Sources/TerminalController.swift`. Phải đọc trước khi sự kiện vào hàng đợi giao, vì hàng đợi chỉ giữ một chỗ cho sự kiện tool của mỗi pane và có thể bỏ PreToolUse (`Sources/AgentHookDeliveryQueue.swift`). Mỗi sự kiện mang `subcommand`, `payload` là JSON thô (tối đa 256 KiB), cùng `CMUX_WORKSPACE_ID` và `CMUX_SURFACE_ID` trong `environment` (`Sources/AgentHookDeliveryEvent.swift`).
- Không lấy tên từ CLI: bản rút gọn trong `CLI/CMUXCLI+AgentHookPayload.swift` bỏ mất `tool_input.skill`.

| Sự kiện Claude (`subcommand`) | Dấu của pane sau sự kiện |
|---|---|
| `prompt-submit` | xoá dấu; nếu lời nhắn là một lệnh `/tên` (lời nhắn bắt đầu bằng `/tên`, hoặc có `<command-name>/tên</command-name>`) thì đặt dấu skill `tên` |
| `pre-tool-use`, `tool_name` = `Skill` | dấu skill, tên lấy từ `tool_input.skill` |
| `pre-tool-use`, `tool_name` = `Workflow` | dấu workflow, tên lấy từ `tool_input.name`; nếu không có thì lấy `name` trong khối `meta` của `tool_input.script`; nếu vẫn không có thì để trống tên |
| `stop`, `stop-failure` | dấu skill: xoá. Dấu workflow: giữ nếu payload còn việc chạy nền, theo đúng quy tắc của `hasActiveClaudeBackgroundWork` (`CLI/CMUXCLI+NotificationFormatting.swift`); nếu không thì xoá |
| `session-end` | xoá |

Mỗi lần đặt dấu mới thì tăng một bộ đếm của pane. Giao diện lóe sáng khi bộ đếm đổi.

**Hiệu ứng của một pane:**

- Pane đang chờ người dùng, bị lỗi hoặc rảnh: không có hiệu ứng.
- Pane đang chạy: theo dấu nếu có, nếu không thì là đang làm việc.
- Pane đang chờ việc chạy nền (work state `waiting`): là workflow nếu dấu là workflow, nếu không thì không có hiệu ứng.

Dòng phiên lấy hiệu ứng mạnh nhất trong các pane của phiên, theo §6.3.

Nếu payload quá lớn và đã bị cắt thì có thể mất tên skill hoặc workflow. Khi đó chỉ ghi "Skill" hoặc "Workflow".

## 7. Ràng buộc

- **Swift 6.0** cho mọi code nối vào app (skill `cmux-architecture`, `references/swift-6-0-compatibility.md`).
- **Kiến trúc** (skill `cmux-architecture`):
  - Mỗi file một kiểu chính. Không thêm hàm tự do (free function), không dùng enum chỉ để làm namespace.
  - Không làm phình `ContentView.swift` và `Workspace.swift`. Trạng thái mới nằm trong một model con riêng, `Workspace` chỉ giữ một thuộc tính trỏ tới model đó.
- **Ranh giới snapshot của sidebar** (skill `cmux-debugging`): ô sidebar chỉ nhận snapshot bất biến cộng closure. Giá trị mới đi qua `SidebarWorkspaceSnapshotBuilder.Snapshot` và `SidebarWorkspaceRowModel`, và phải có mặt trong phép so sánh bằng nhau.
- **Độ trễ gõ phím:**
  - Hiệu ứng chạy trên render server của Core Animation (`CAGradientLayer` có mask chữ, `CABasicAnimation`). Không dùng display link. Không có việc phải làm trên main thread mỗi khung hình. Không dùng animation `repeatForever` của SwiftUI trong thanh tab, vì Bonsplit vừa phải sửa lỗi render liên tục ở đó.
  - Tạm dừng như spinner hiện có (`Sources/Sidebar/GPUSpinnerNSView.swift`): khi view bị ẩn, cửa sổ bị che, `isPresentationActive` tắt, hoặc bật Giảm chuyển động.
- **Bonsplit là submodule** của `manaflow-ai/bonsplit`. Thay đổi đẩy lên fork `lephus/bonsplit` (sổ quyết định R1). Mọi hành vi mới chỉ bật khi app chọn, qua `BonsplitConfiguration.Appearance` hoặc trường mới của `TabItem`. Mặc định giữ hành vi upstream.
- **Bản địa hoá:** đủ 10 ngôn ngữ cho mỗi chuỗi mới (skill `cmux-localization`, `./scripts/localize-changes`). Bonsplit chỉ có tiếng Anh và tiếng Nhật, nên app truyền vào chữ đã bản địa hoá.
- **Kiểm thử:**
  - Test mới viết bằng Swift Testing. Thêm file vào `cmuxTests/` thì chạy `./scripts/sync-test-wiring`; thêm file vào `Sources/` thì chạy `./scripts/wire-app-sources.py`.
  - Các test đang ghim màu chọn cũ `#171128` sẽ đổi theo hành vi mới: `cmuxTests/ShellXThemeTests.swift` (`darkSidebarSelectionIsTheRaiseToken`) và `cmuxTests/WorkspaceUnitTests.swift` (`testSelectionStaysSolidUnlessSubtleSelectionIsEnabled`).
  - Test Bonsplit `testSharedBackdropActiveTabBackgroundIsClear` vẫn đúng với cấu hình mặc định.
- **Chạy thử:** chỉ dùng bản build có tag (`CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag <tag>`). Không đụng tới app ShellX người dùng đã cài.

## 8. Để lại cho người làm

- Kỹ thuật Core Animation cụ thể, và cách giữ chữ trong ô sidebar vẫn đọc được bằng VoiceOver khi lớp hiệu ứng phủ lên.
- Thời gian và độ mờ chính xác, được lệch khoảng ±20% so với §6.4 nếu nhìn đẹp hơn trên máy thật.
- Chỗ đặt model dấu hoạt động, cách chuyển sự kiện từ luồng socket sang main actor, và cách làm sidebar dựng lại snapshot khi dấu đổi. Nên đi theo đường mà `agentStatusEntriesByPanelId` đang dùng.
- Cách đổi `CMUX_SURFACE_ID` sang id panel và id tab của Bonsplit. App đã có sẵn ánh xạ, ví dụ `Workspace.panelIdFromSurfaceId`.
- Kiểm tra trên payload thật của Claude Code: lời nhắn `/tên` đến `prompt-submit` dưới dạng nào, và `background_tasks` có cho biết đâu là workflow không. Nếu có thì dùng để giữ dấu workflow chính xác hơn.
