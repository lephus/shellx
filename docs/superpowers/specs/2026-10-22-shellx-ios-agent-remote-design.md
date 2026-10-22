# ShellX iOS: điều khiển agent bằng giọng nói + skill một chạm

- **Ngày:** 2026-10-22
- **Trạng thái:** bản thiết kế, chờ người dùng duyệt
- **Phạm vi:** app iOS native mới của ShellX, cộng phần Mac cần thêm để phục vụ app đó (kết nối điện thoại, trạng thái agent, cửa sổ tạo skill, thông báo đẩy). Không gồm Android.
- **Mockup** (mở bằng trình duyệt, chạy local): `docs/superpowers/design/2026-10-22-ios-agent-remote/home-layout.html` (chọn kiểu **C**), `docs/superpowers/design/2026-10-22-ios-agent-remote/desktop-skill-creator.html`.

Quy ước trong tài liệu: **[người dùng]** là điều người dùng đã nói hoặc đã chọn. **[người viết]** là quyết định của người viết spec, người dùng chưa bàn riêng, builder có thể xem lại.

## 1. Vì sao làm

Người dùng hay ra ngoài, thường là ngồi cafe, **không mang theo laptop**. Trong lúc đó các agent (Claude Code, Codex) vẫn chạy trên Mac ở nhà, với ShellX đang mở. Người dùng cần điện thoại để:

- biết agent nào đang chạy, cái nào kẹt, cái nào chờ mình;
- duyệt hoặc trả lời agent;
- giao việc mới.

Tất cả phải **dễ dùng nhất có thể**, và **nói thay cho gõ** [người dùng].

Người dùng cũng muốn tạo skill ngay trên desktop, với AI hỗ trợ (skill-creator của Anthropic). Tạo xong là dùng được ngay, tự đồng bộ sang điện thoại, **bấm một nút là chạy** [người dùng].

Bối cảnh khi dùng: ngồi cafe, có chút thời gian rảnh, nhìn được màn hình [người dùng]. Không phải lúc lái xe, nên không cần chế độ rảnh tay hoàn toàn.

## 2. Mục tiêu, không làm, và điều coi là thất bại

**Mục tiêu**

- G1. Mở app là thấy ngay: việc đang chờ mình, agent nào đang chạy, việc nào vừa xong.
- G2. Duyệt quyền (Cho phép / Từ chối), trả lời câu hỏi và duyệt plan của agent ngay từ điện thoại, kể cả từ thông báo trên màn hình khoá.
- G3. Giao việc bằng giọng nói: bấm giữ mic rồi nói. Gõ phím là đường phụ.
- G4. Skill tạo trên desktop hiện thành chip trên điện thoại. Bấm là chạy trên Mac.
- G5. Tạo skill trên desktop bằng cách mô tả cho AI, chạy thử, rồi lưu.
- G6. Phát hành **công khai trên App Store cho khách hàng ShellX** [người dùng].
- **Agent hỗ trợ:**
  - Bản đầu chỉ hỗ trợ **Claude Code** [người dùng]: trạng thái, duyệt quyền, câu hỏi, plan, skill và AI điều phối đều chỉ cần chạy với Claude Code.
  - **Codex** là agent tiếp theo [người dùng]. Vì vậy giao thức và mô hình dữ liệu phải trung lập với agent: thêm Codex sau này chỉ cần thêm adapter trên Mac, không phải đổi giao thức.
  - Chỉ tính agent chạy trong workspace ShellX có hook [người viết].

**Không làm trong dự án này**

- Android. Làm sau, là dự án riêng.
- iPad, Apple Watch, widget, CarPlay.
- Chế độ rảnh tay hoàn toàn (wake word, tự đọc to mọi kết quả).
- Xếp hàng việc khi Mac tắt (xem §7.5).
- Chạy agent trên cloud. Agent luôn chạy trên Mac của người dùng.
- Dùng bất kỳ dịch vụ nào của Manaflow: cmux.com, Stack Auth, iroh broker, presence, CodeRouter, billing.
- Tương thích với app Flutter 1.0.0 cũ hoặc relay v1 (giống quyết định U9 của spec desktop).
- Điều khiển máy Windows từ điện thoại. Có thể đến miễn phí tuỳ giao thức được chọn (§6.1), nhưng không phải mục tiêu.

**Điều coi là thất bại, dù về kỹ thuật app vẫn chạy** [người dùng]

- A1. **Thông báo lệch nhau giữa desktop và điện thoại.** Một việc đã được xử lý ở máy này mà máy kia vẫn báo, vẫn hiện nút, hoặc báo hai lần.
- A2. **Lag.** Bấm Cho phép mà agent không chạy tiếp ngay. Trạng thái cập nhật chậm. Chữ không hiện ra trong lúc đang nói.

## 3. Người dùng sẽ thấy gì: trò chuyện là màn chính

Người dùng đã chọn **kiểu C · Trò chuyện**, xem mockup `home-layout.html`. Lúc đầu người dùng có cân nhắc B (hộp thư "Cần bạn"). Ý hay của B được giữ lại ở mục 3.1, dòng "Ghim trên đầu" [người viết].

### 3.1 Màn chính: một cuộc trò chuyện với "ShellX"

- **Một cuộc trò chuyện duy nhất** dùng chung cho mọi Mac và mọi agent [người dùng].
- **Ghim trên đầu** [người viết]: việc nào đang chờ người dùng (xin phép, câu hỏi, duyệt plan) thì nằm ghim ở đầu cuộc trò chuyện cho tới khi được xử lý, không bị trôi đi. Xử lý xong thì gỡ ghim, và phần ghim cũng biến mất trên mọi thiết bị (A1).
- **Nút mic lớn** ở dưới cùng. Giữ để nói, thả ra là gửi. Vuốt lên để gõ [người dùng duyệt qua mockup].
- **Dải chip skill** ngay trên mic. Bấm một chip là chạy skill đó [người dùng duyệt]. Chip được sắp theo số lần dùng nhiều nhất [người viết].
- **Thẻ trạng thái** hiện trong chat mỗi khi chạy skill hoặc giao việc. Thẻ có tên việc, Mac nào, agent nào, trạng thái và một dòng cho biết agent đang làm gì. Màu trạng thái theo gu màu đã lưu của người dùng: đang chạy = vàng, cần bạn = xanh dương `#60a5fa`, xong = xanh lá, lỗi = đỏ. Dùng màu dịu, không có nút gradient.
- **Nút trong chat:** Cho phép / Từ chối. Với agent có hỗ trợ thì thêm "Luôn cho phép", theo `FeedPermissionActionPolicy`. Với câu hỏi thì có "🎙 Trả lời". Với plan thì có "Duyệt plan".
- **Kết quả:** agent xong việc thì ShellX nhắn một dòng tóm tắt (ví dụ "PR #128 đã tạo, test xanh"), kèm link tới chi tiết.

### 3.2 Chi tiết một agent

Bấm vào thẻ trạng thái thì mở trang của agent đó:

- cuộc trò chuyện riêng với agent (nhắn thêm bằng giọng nói hoặc gõ);
- nút chuyển sang **xem terminal** của workspace đó: xem và gõ được, vẽ bằng thư viện MIT, dữ liệu qua kênh `terminal` của ShellX Link (§7.2);
- nút **Dừng** (interrupt).

Thứ tự ưu tiên là chat trước, terminal sau [người viết].

### 3.3 Các màn khác (tối giản)

- **Lần đầu mở:** đăng nhập tài khoản ShellX, rồi quét QR hiện trên Mac. Mac phải đồng ý ngay tại máy, giống luật ghép cặp của spec desktop §8.5.
- **Máy của bạn:** danh sách Mac đã ghép cặp, cái nào đang online, đổi Mac mặc định, gỡ ghép cặp.
- **Cài đặt:** ngôn ngữ giọng nói, thông báo, đăng xuất.

### 3.4 Thông báo đẩy

- Thông báo đẩy được gửi khi agent **cần bạn** (xin phép, hỏi, duyệt plan) và khi **xong** hoặc **lỗi**.
- Thông báo xin phép có sẵn nút **Cho phép / Từ chối** ngay trên màn hình khoá. Thông báo câu hỏi có nút "Trả lời", bấm vào thì mở app với mic sẵn sàng.
- **Đồng bộ (A1):** khi một việc được xử lý ở bất kỳ đâu (Mac, điện thoại, trong app hay ngoài thông báo, hoặc agent tự hết chờ), mọi thông báo còn lại về việc đó trên điện thoại phải bị gỡ, và trên Mac cũng vậy. Bấm vào một thông báo đã cũ thì không được gửi quyết định lần hai: Mac trả lời "đã xử lý rồi" và app hiển thị đúng như vậy.
- Người dùng đang ngồi ở Mac thì điện thoại vẫn nhận thông báo. Không có logic "đoán xem người dùng đang ở máy nào" [người viết]. Đổi lại, việc gỡ thông báo phải nhanh, để điện thoại không còn kêu cho việc đã xử lý ở Mac.

## 4. Giọng nói

- Giữ mic để nói. Chữ hiện ra **ngay trong lúc nói** (A2). Thả tay ra là gửi, hoặc kéo sang bên để huỷ [người viết].
- Người dùng nói **tiếng Việt, có xen thuật ngữ tiếng Anh** (tên nhánh, PR, CI). Nhận dạng phải chịu được kiểu nói này.
- Phần nhận giọng được viết mới (§7.1). Để tham khảo: app cmux iOS (`ComposerDictation*`) dùng `SFSpeechRecognizer`, ưu tiên chạy trên máy, và **tắt mic** khi ngôn ngữ không được hỗ trợ. ShellX không được lặp lại lỗi đó. Builder phải:
  - kiểm tra `vi-VN` có chạy trên máy được không, trên iOS mục tiêu. Có thể thử API nhận giọng nói mới hơn nếu iOS mục tiêu có;
  - nếu không chạy trên máy được thì cho phép dùng nhận dạng qua máy chủ Apple, và nói rõ cho người dùng trong Cài đặt;
  - không bao giờ được tắt mic chỉ vì ngôn ngữ đó không chạy được trên máy.
- Chỉ dùng speech-to-text của Apple, không gửi giọng nói tới máy chủ của ShellX hay bên thứ ba [người viết].
- Không tự đọc to kết quả. Có thể thêm nút 🔊 để đọc một tin nhắn, nhưng đó là phần thêm, không bắt buộc [người viết].

## 5. Skill

### 5.1 Tạo skill trên desktop

Xem mockup `desktop-skill-creator.html` [người dùng duyệt].

- ShellX trên Mac có thêm cửa sổ **Skill**, chia ba cột:
  - bên trái: danh sách skill;
  - ở giữa: chat với AI;
  - bên phải: xem trước "thẻ trên điện thoại".
- **Tạo:** bấm "＋ Skill mới", rồi nói hoặc gõ mô tả. **Claude Code trên Mac** dùng skill **skill-creator** của Anthropic để viết skill, và hỏi lại nếu còn thiếu thông tin.
  - Builder tự chọn cách nhúng: một phiên Claude Code chạy ngầm, hay một pane Agent Chat có sẵn của cmux.
  - Nếu máy chưa có skill-creator thì hướng dẫn cài.
- **Chạy thử:** chạy skill thật với tham số mẫu. Mọi lệnh push, deploy, hoặc ghi ra bên ngoài máy đều bị chặn trong lúc chạy thử, ví dụ bằng luật deny của Claude Code cho riêng phiên đó [người viết]. Kết quả chạy thử hiện ngay trong chat.
- **Lưu & đồng bộ:** lưu thành **skill Claude Code thật**, nên gõ trong terminal vẫn dùng được [người viết, người dùng duyệt]. Skill hiện lên điện thoại ở lần kết nối tới.
- Danh sách cũng hiện các skill Claude Code người dùng đã có sẵn. Người dùng bật "Hiện trên điện thoại" cho skill nào thì skill đó mới thành chip [người viết].
- Sửa skill cũng làm trong khung chat đó ("đổi để nó chờ CI xanh").

### 5.2 Thẻ skill (những gì điện thoại cần biết)

Mỗi skill hiện trên điện thoại có các trường sau [người viết]:

| Trường | Ví dụ |
| --- | --- |
| Tên, biểu tượng | 📝 Làm issue… |
| Bấm xong hỏi gì (0..n tham số, mỗi cái có câu hỏi) | "Số issue?" (nói hoặc gõ) |
| Chạy trên Mac nào, thư mục nào | MacBook Pro · `~/…/shellx`, hoặc "hỏi khi chạy" |
| Agent | Claude Code (bản đầu chỉ cần Claude Code) |
| Hỏi lại trước khi chạy | có / không. Skill có push hoặc deploy thì mặc định là "có" |
| Câu nói kích hoạt | "làm issue…" |

Builder chọn chỗ lưu các trường này. Có thể là frontmatter của `SKILL.md`, nếu Claude Code bỏ qua được field lạ, hoặc một file đi kèm trong thư mục skill. Yêu cầu là không làm hỏng skill khi Claude Code đọc nó.

### 5.3 Chạy skill

- **Nguồn kích hoạt:** bấm chip, hoặc câu nói trùng câu kích hoạt / tên skill.
- **Hỏi tham số:** app hỏi từng tham số. Người dùng trả lời bằng giọng nói hoặc gõ.
- **Hỏi lại trước khi chạy:** nếu thẻ bật "hỏi lại trước khi chạy" thì app hiện một bước xác nhận.
- **Trên Mac:** Mac mở một **workspace mới** ở thư mục của skill, rồi chạy agent với lời gọi skill kèm tham số.
- **Theo dõi:** thẻ trạng thái trong chat bám theo workspace và agent đó cho tới khi xong.
- **Một lối duy nhất:** chạy skill từ điện thoại, từ cửa sổ Skill trên desktop hay từ Command Palette đều phải đi chung một đường code (theo `skills/cmux-shared-behavior`).

### 5.4 Đồng bộ skill

- Đồng bộ đi **thẳng từ Mac sang điện thoại** qua kết nối ShellX. Không lưu skill lên relay hay cloud [người viết, người dùng duyệt].
- Điện thoại giữ bản sao để hiển thị khi Mac offline. Khi đó chip bị làm mờ và có ghi "Mac đang offline".
- Nhiều Mac: chip ghi tên Mac nếu tên skill bị trùng.

## 6. AI điều phối ("ShellX" hiểu câu nói)

- Câu nào **trùng tên skill hoặc câu kích hoạt** thì chạy thẳng, không cần AI (nhanh, không tốn lượt).
- Câu tự do (ví dụ "xem giúp sao web build lỗi", "hôm nay thế nào?", "nhắn agent ở relay là giữ route v1") thì do **một AI điều phối chạy trên Mac, dùng Claude Code của chính người dùng** xử lý [người dùng đồng ý]. ShellX không có máy chủ AI, dữ liệu không đi qua đâu khác, và việc này tốn lượt dùng gói Claude của người dùng.
- Công cụ tối thiểu AI điều phối cần dùng được [người viết]:
  - liệt kê Mac, workspace và agent cùng trạng thái;
  - chạy skill có tham số;
  - mở workspace mới và giao việc cho agent;
  - nhắn vào một agent đang chạy;
  - tóm tắt tình hình.
- AI điều phối **không tự duyệt quyền** thay người dùng.
- AI điều phối chạy trên **Mac mặc định** (đặt trong "Máy của bạn"). Nếu Mac đó offline thì báo ngay, không chờ.
- Câu trả lời của AI điều phối phải đến dạng luồng: chữ hiện dần, không chờ trả lời xong mới hiện (A2).

## 7. Kỹ thuật

### 7.1 Nền móng: app iOS viết mới, không chứa code GPL của Manaflow

App iOS hiện có trong repo là app cmux gốc, chưa đổi thương hiệu: `ios/`, `Packages/iOS/*` và `Packages/Shared/*`, khoảng 300 nghìn dòng Swift. Toàn bộ là GPL-3.0 với bản quyền của Manaflow.

Người dùng muốn phát hành công khai trên App Store (G6). Điều khoản App Store xung đột với GPL khi ShellX không phải chủ bản quyền. Vì vậy app iOS của ShellX **không chép code từ `ios/`, `Packages/iOS/` hay `Packages/Shared/`** [người viết, suy ra từ G6]. Lúc brainstorm, người viết từng đề xuất "dùng lại app cmux iOS". Đề xuất đó **bị thay** bằng quyết định này.

- **Viết mới bằng code của ShellX:**
  - giao diện;
  - client ShellX Link;
  - nhận giọng nói;
  - lưu trữ cục bộ;
  - thông báo đẩy và Notification Service Extension.
- **Được dùng:**
  - thư viện có giấy phép dễ dãi: libghostty / GhosttyKit (MIT), SwiftTerm (MIT);
  - SDK của Apple;
  - code do ShellX tự viết.
- **Phải xác nhận trước khi dùng:**
  - phần vá của cmux trong fork ghostty còn MIT không;
- **Chỗ đặt code:** một thư mục riêng, ví dụ `shellx-ios/`, có file LICENSE riêng do người dùng chọn. Lý do: `LICENSE` ở gốc repo mặc định mọi thứ là GPL. Builder chọn tên thư mục, nhưng ranh giới giấy phép phải rõ ràng và có kiểm tra tự động: một test hoặc script chặn import package GPL vào target iOS.
- **Đọc app cmux iOS để tham khảo cách giải bài toán thì được, nhưng không chép code.** Nếu có nghi ngờ thì viết lại từ mô tả hành vi.
- **Thương hiệu** [người viết]:
  - dùng lại app trên App Store Connect hiện có: bundle `com.shellx.prod`, team `W4RF3W4VTZ`;
  - app mới **thay thế** bản Flutter 1.0.0, lên version **2.0.0**;
  - tên ShellX, logo ShellX, ngôn ngữ vi + en.
- **Không đưa vào app:** bất cứ thứ gì của Manaflow (Cloud, VPN, Billing, Stack Auth, iroh, presence, analytics).

### 7.2 Kết nối điện thoại ↔ Mac

**Hiện trạng** (đọc code ngày 2026-10-22):

- ShellX Mac 1.2.0 **chưa phục vụ điện thoại nào**:
  - `ShellXFeatures.remoteMachines`, `shareLinks` và `upstreamDeviceMirroring` đều là `false`;
  - mobile host của cmux (`Sources/Mobile/MobileHostService*`) bị chặn ở `MobileHostService.swift:761`.
- Kết nối riêng của ShellX là quyết định **D-W0-1 = (b) cmux-tui-remote** (`docs/superpowers/ledgers/native-desktop.md`): Noise `XXpsk3`, mã hoá đầu-cuối, qua `relay+wss://relay.shellx.pro/v2/relay`. Ghép cặp và vé kết nối do relay v2 (`relay/src/v2/`) và `shellx-core` cấp. Noise nằm trong crate `cmux-remote` của cmux-tui, **không** nằm trong `shellx-core`. Hướng này hiện **chỉ mang terminal**.
- Các route v2 đều có `requireDesktop`, nên relay đang từ chối thiết bị điện thoại.
- Trạng thái agent và việc trả lời agent (`feed.permission.reply`, `feed.question.reply`, `feed.exit_plan.reply`, `mobile.chat.*`) hiện chỉ có trên **mobile RPC của cmux**, là thứ đang tắt.

**Quyết định: ShellX tự xây lớp tin nhắn riêng, tạm gọi là "ShellX Link"** [người dùng]. Mobile host của cmux vẫn tắt, và app iOS không nói mobile RPC của cmux.

- **ShellX Link mang mọi thứ mới:**
  - trạng thái agent, gồm danh sách workspace và agent cùng các thay đổi trạng thái;
  - việc đang chờ: xin phép, câu hỏi, plan, cùng quyết định trả lời và kết quả "đã xử lý";
  - chat với agent: gửi tin, nhận luồng trả lời, dừng;
  - skill: danh sách, thẻ, chạy, tham số;
  - AI điều phối;
  - tín hiệu gỡ thông báo;
  - thông tin máy.
- **Terminal đi qua kênh `terminal` của ShellX Link ngay từ bản đầu** [người dùng, 2026-10-22, thay quyết định "tạm dùng cmux-tui"]. Giấy phép của `cmux-tui` đang mơ hồ, và người dùng không muốn phải chờ Manaflow xác nhận.
  - **Mac:** lấy dữ liệu ra/vào của terminal qua các điểm móc Ghostty mà cmux có sẵn (ví dụ `ghostty_surface_set_pty_tee_cb`, `TerminalOutputTeeCallback`). Kênh gồm ảnh chụp màn hình ban đầu, luồng byte, phím gõ và đổi kích thước.
  - **iPhone:** vẽ bằng thư viện MIT, như SwiftTerm hoặc libghostty. Builder chọn.
  - App iOS **không nhúng** `cmux-tui` (kể cả `cmux-terminal-client`) và **không nhúng** `shellx-core`. Đăng nhập, ghép cặp và vé relay được viết lại bằng Swift, gọi thẳng API HTTP của relay v2.
  - Phần cmux-tui trên desktop (máy ở xa Mac↔Mac) và `cmux-relay` trên VPS giữ nguyên. Cả hai chạy ngoài app iOS.
- **ShellX Link có phiên Noise riêng, không đi chung phiên của cmux-tui** [người viết, sửa sau khi đọc code ngày 2026-10-22]. Có ba lý do:
  - enum `Service` của cmux-remote là enum đóng. Muốn thêm kênh ShellX vào thì phải vá fork;
  - client C ABI `cmux-terminal-client` không có API kênh hay tunnel nào;
  - giấy phép của cmux-tui đang mơ hồ: Cargo ghi MIT, nhưng `LICENSE` ở gốc ngầm hiểu là GPL.

  Vì vậy ShellX Link dùng **slot riêng trên cùng relay** (`cmux-relay` chỉ là ống chuyển byte, phía server). Mỗi máy có thêm một `link_slot`. Code Noise và code client relay của ShellX Link là code ShellX tự viết. Điện thoại chỉ cần một kết nối ShellX Link cho mọi thứ, kể cả terminal.
- **Ràng buộc thiết kế ShellX Link:**
  - **Một kết nối ShellX Link E2E cho mỗi Mac,** dồn mọi kênh vào đó, kể cả terminal.
  - **Mô tả độc lập với nền tảng:** đặc tả giao thức viết thành tài liệu, có test vector, để Windows (Rust) và Android sau này cài đặt theo. Giống cách `term/protocol/vectors.txt` từng làm cho P2a.
  - **Trung lập với agent:** Claude Code trước, Codex sau (G6).
  - **Có phiên bản giao thức:** điện thoại và Mac khác phiên bản thì báo lỗi rõ ràng, không treo.
  - **Mọi quyết định đều idempotent:** mỗi việc có id ổn định (A1).
  - **Đồng bộ trạng thái lại khi kết nối lại:** điện thoại lấy ảnh chụp trạng thái, rồi nhận phần thay đổi tiếp theo.
  - **Không có dịch vụ Manaflow nào.** Đăng nhập bằng tài khoản ShellX, và Mac đồng ý tại chỗ khi ghép cặp.
  - **Đáp ứng §7.4.**
  - **Relay v2 nhận điện thoại:** hiện các route chỉ cho desktop (`requireDesktop`). Phải cho thiết bị loại điện thoại ghép cặp và nhận vé kết nối, có test cho quyền: điện thoại chỉ thấy máy của tài khoản mình và đã ghép cặp.
- **Bước đầu tiên của dự án** (rủi ro cao nhất): viết đặc tả ShellX Link, rồi làm một spike. Spike chứng minh được hai điều thì đạt: Mac và một client thử nói ShellX Link qua relay thật; một quyết định duyệt quyền đi từ client tới hook Claude Code trong mục tiêu < 500 ms. Kế hoạch: `docs/superpowers/plans/2026-10-22-shellx-link-p1-spike.md`.

Nếu kênh mới cho phép điện thoại gọi lệnh trên Mac (chạy skill, mở workspace, gửi chữ vào agent) thì phải viết phần phân tích an toàn theo tinh thần `skills/cmux-socket-policy/references/remote-relay-authorization.md`:

- mặc định là chặn;
- chỉ cho phép đúng các lệnh cần;
- skill chỉ chạy những skill đã bật "Hiện trên điện thoại".

### 7.3 Thông báo đẩy (APNs)

- **Ai gửi:** Mac là nguồn sự thật cho trạng thái agent. Mỗi khi có việc "cần bạn", "xong", "lỗi" hoặc "đã xử lý", Mac báo cho relay v2, rồi relay gửi APNs tới các điện thoại đã ghép cặp.
- **Nội dung mã hoá:** phần nội dung (tên workspace, lệnh xin phép) được mã hoá đầu-cuối từ Mac. Relay chỉ chuyển tiếp. Notification Service Extension của ShellX (viết mới) giải mã nội dung đó.
- **Đồng bộ (A1):** mỗi việc có một id ổn định, dùng làm id gom nhóm thông báo. Khi việc đó được xử lý, Mac gửi tín hiệu "đã xử lý", và điện thoại gỡ mọi thông báo của id đó. Builder chọn cơ chế: push nền hoặc push cập nhật. Trên Mac cũng gỡ thông báo tương ứng khi điện thoại xử lý.
- **Duyệt từ màn hình khoá:** quyết định đi qua kết nối E2E tới Mac nếu mở được trong thời gian ngắn. Nếu không, gửi qua relay dưới dạng tin đã ký hoặc mã hoá mà Mac kiểm tra được. Quyết định phải **idempotent**: gửi trùng hoặc gửi muộn thì Mac trả "đã xử lý rồi".
- **Việc người dùng phải tự làm:** tạo APNs key (.p8) trong Apple Developer của team `W4RF3W4VTZ` rồi đặt lên VPS. Không gửi key trong chat.

### 7.4 Mục tiêu độ trễ (A2)

Đo trên điện thoại thật, 4G/Wi-Fi bình thường, qua relay.shellx.pro. Các con số do người viết đề xuất; builder đo, nếu không đạt thì báo lại chứ không được lặng lẽ hạ mục tiêu.

| Thao tác | Mục tiêu (p95) |
| --- | --- |
| Bấm Cho phép trong app → hook agent trên Mac nhận quyết định | < 500 ms |
| Trạng thái agent đổi trên Mac → thẻ trên điện thoại đổi | < 1 s |
| Xử lý ở một máy → thông báo / ghim ở máy kia biến mất | < 2 s (trong app), push tuỳ APNs |
| Đang nói → chữ đầu tiên hiện ra | < 300 ms |
| Mở app (đã có cache) → thấy cuộc trò chuyện | < 1 s; kết nối lại chạy nền, không chặn giao diện |
| Bấm chip skill (không có tham số) → thẻ "đang chạy" | < 1 s |

### 7.5 Mac offline

- Mac chỉ kết nối được khi ShellX đang mở. Đây là quyết định U14 của spec desktop: không có daemon chạy nền.
- Khi Mac offline:
  - chat vẫn đọc được từ cache;
  - chip skill bị làm mờ;
  - nói một việc thì ShellX trả lời ngay "MacBook Pro đang offline", không xếp hàng.
- Gợi ý trong Cài đặt Mac: bật "giữ Mac thức" (đã có trong menu "Keep Mac Awake").

### 7.6 Phạm vi tin cậy, nhiều Mac, nhiều điện thoại, phiên bản iOS [người viết]

- **Điện thoại đã ghép cặp được tin như chính người dùng ngồi ở Mac.** Điều kiện: đã đăng nhập tài khoản ShellX và đã được Mac đồng ý tại chỗ. Với điều kiện đó, điện thoại được gõ vào terminal, giao việc tự do và chạy skill, đúng như quyền "Được gõ" của spec desktop. Danh sách cho phép (§7.2) nhằm giới hạn **đối tượng** điện thoại chạm tới: chỉ các máy của tài khoản đã ghép cặp, và chỉ workspace hoặc agent trên các máy đó. Nó không nhằm cắt bớt tính năng. Gỡ ghép cặp phải thu hồi quyền ngay.
- **Nhiều Mac:**
  - Mỗi Mac chạy AI điều phối của riêng nó, và AI đó chỉ tác động trên chính Mac đó. Không xây kênh agent giữa các Mac.
  - Điện thoại là bên định tuyến: chip skill đi thẳng tới Mac của skill đó, câu tự do đi tới Mac mặc định.
  - Câu "hôm nay thế nào?" thì điện thoại hỏi từng Mac đang online rồi gộp kết quả lại.
- **Lịch sử cuộc trò chuyện:**
  - Lịch sử nằm **trên điện thoại**, trong kho lưu trữ cục bộ của app. Mất khi cài lại app thì chấp nhận được.
  - Trạng thái agent và các việc đang chờ thì luôn lấy lại từ Mac, vì Mac là nguồn sự thật. Do đó cài lại app không làm mất phần ghim "cần bạn".
- **Nhiều iPhone cho một tài khoản** thì được hỗ trợ. A1 áp dụng cho mọi điện thoại đã ghép cặp: xử lý ở một máy thì gỡ ở tất cả. Mỗi thiết bị có khoá mã hoá push riêng.
- **iOS tối thiểu là 17.0**, giữ như project hiện tại. Nhận giọng nói chạy theo hai đường:
  - iOS 26 trở lên: dùng API nhận giọng mới trên máy (SpeechAnalyzer) nếu nó hỗ trợ `vi-VN`;
  - còn lại: dùng `SFSpeechRecognizer`, chạy qua máy chủ Apple khi không chạy trên máy được, và ghi rõ điều này trong Cài đặt.

## 8. Ràng buộc

- iOS UI theo Apple HIG (`Packages/iOS/AGENTS.md`). Mọi chữ hiển thị phải có cả vi và en (`skills/cmux-localization`).
- Code dùng chung với app Mac giữ tương thích Swift 6.0.
- Build và kiểm tra iOS theo `ios/AGENTS.md`: cả simulator riêng lẫn iPhone thật, có đăng nhập. Các script hiện đang gắn với hồ sơ dev của Manaflow, nên builder phải đổi sang tài khoản ShellX.
- Phát hành iOS vẫn làm local như hiện tại, không làm CI cho mobile (`release/mobile/`). Script `ios.sh` cũ là của Flutter và phải viết lại cho app Swift.
- Không push, deploy hay tạo tài nguyên trả phí khi chưa hỏi người dùng.

## 9. Rủi ro còn mở

- **Giấy phép thư viện (§7.1).** App iOS không dùng `cmux-tui` và `shellx-core`, nên chỉ còn phải xác nhận phần vá ghostty của cmux, và chỉ khi builder chọn libghostty thay vì SwiftTerm. Nếu một trong số đó không dùng được trên App Store thì phải thay. Với `cmux-tui`, thay nghĩa là tự làm kênh terminal của ShellX Link ngay ở bản đầu (thêm vài tuần).
- **Viết mới app iOS** tốn công hơn nhiều so với dùng lại app cmux. Đó là cái giá của G6.
- **Tiếng Việt chạy trên máy:** có thể không có (§4).
- **Spike ShellX Link (§7.2)** có thể làm thay đổi lớn ước lượng.
- **skill-creator** là skill của Anthropic. Cần kiểm tra giấy phép và cách cài trên máy người dùng.

## 10. Thứ tự làm đề xuất [người viết]

1. Xác nhận giấy phép (§7.1). Viết đặc tả ShellX Link và làm spike (§7.2). Ghi kết quả vào ledger.
2. Mac: phía máy chủ ShellX Link cho Claude Code (trạng thái, việc đang chờ, chat), relay v2 nhận điện thoại, ghép cặp.
3. iOS (viết mới): khung app và ranh giới giấy phép, đăng nhập và ghép cặp, màn Trò chuyện cùng thẻ trạng thái và nút duyệt, giọng nói tiếng Việt. Kênh `terminal` của ShellX Link (Mac + iPhone) nằm trong P2/P3.
4. Thông báo đẩy và đồng bộ gỡ thông báo (A1).
5. Skill: cửa sổ tạo skill trên desktop, thẻ skill, đồng bộ, chip trên điện thoại.
6. AI điều phối.
7. Đo độ trễ (§7.4), dogfood trên iPhone thật, TestFlight 2.0.0.

## 11. Để builder tự quyết

- Bố cục mã nguồn: package nào giữ, package nào tách, và giao diện mới đặt ở đâu.
- Cách lưu metadata của skill (§5.2), cách nhúng skill-creator (§5.1), cơ chế push gỡ thông báo (§7.3).
- Prompt và cách chạy AI điều phối trên Mac, ví dụ chạy headless một phiên Claude Code dài hạn hay từng lần một.
- Chi tiết hình ảnh ngoài những gì mockup đã chốt, miễn là đúng HIG và gu màu đã nêu.
