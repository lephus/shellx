# Git Graph trên desktop Mac: đặc tả thiết kế

Ngày 26/10/2026. Phạm vi là app ShellX trên macOS. Mockup chỗ đặt mà người dùng đã chọn và ảnh chụp bản thử nằm ở
`docs/superpowers/design/2026-10-26-git-graph/`. File `placement.html` mở thẳng bằng trình duyệt là xem được.

## 1. Vấn đề và lý do

Người dùng muốn xem lịch sử repo ngay trong ShellX: cây branch, danh sách commit, và commit nào đổi file nào. Hiện họ phải mở
VS Code với extension Git Graph (mhutchie) chỉ để nhìn lịch sử. ShellX chưa có chỗ nào chạy `git log` hay hiển thị commit. App
chỉ biết tên branch và trạng thái bẩn của workspace (xem §6.7).

Đây là tính năng **chỉ để xem**. Người dùng đã xác nhận không cần thao tác git từ graph.

## 2. Mục tiêu

1. Từ terminal đang làm việc, mở được graph của repo đó bằng một thao tác.
2. Graph vẽ đúng hình nhánh và merge như `git log --graph --all`, kèm nhãn branch, remote và tag.
3. Bấm một commit thì biết ngay commit đó đổi những file nào. Bấm một file thì xem được diff của file đó trong commit.
4. Dùng được ở cả hai chỗ: tab hẹp trong sidebar phải và tab rộng trong workspace.

**Tiêu chí thành công** (mức số do người viết spec chọn):

- Trên chính repo ShellX (lịch sử cmux gộp vào, hàng chục nghìn commit), trang đầu hiện ra trong khoảng 500 ms kể từ lúc mở tab,
  đo trên máy dev. Cuộn xuống thì tải thêm từng trang, tới tối đa 5.000 commit.
- Khi đã tải đủ 5.000 commit, cuộn và chọn commit vẫn mượt, và độ trễ gõ phím không tăng.
- Không lệnh git nào chạy trên main thread. Độ trễ gõ phím trong terminal không tăng khi tab Git đang mở và repo đang đổi.
- Ở bề ngang sidebar 390 px vẫn đọc được graph, nhãn branch và message.
- Với một repo mẫu có merge, branch lồng nhau và parent nằm ngoài trang đầu, thứ tự dòng và mọi đường nối commit với parent
  khớp với `git log --all --date-order --parents`. Kể cả đường nối tới parent chưa tải. Không đòi mỗi commit nằm đúng cột như
  `git log --graph`, vì thư viện tự xếp cột.

## 3. Không làm

- **Mọi thao tác git:** checkout, merge, rebase, cherry-pick, revert, reset, tạo hay xoá branch hoặc tag, stash, fetch, pull,
  push, sửa message. Không có menu chuột phải để thao tác.
- **Repo không nằm trên máy Mac này:** terminal đang SSH sang máy khác, cloud VM, workspace remote. Người dùng đã chốt bản đầu chỉ
  hỗ trợ repo local.
- **App iOS và app Windows.** Lựa chọn của người viết spec.
- Blame, lịch sử của riêng một file, so sánh hai commit bất kỳ với nhau.
- Hiển thị submodule như một graph lồng bên trong.

## 4. Điều tuyệt đối tránh

- **Ghi vào repo của người dùng.** Chỉ chạy lệnh git đọc. Không `fetch` (vừa ra mạng vừa ghi ref). Đặt `GIT_OPTIONAL_LOCKS=0` để
  các lệnh như `status` không ghi lại index.
- **Làm app chậm hay đứng.** Git chạy nền, có timeout và giới hạn số byte đọc. Repo lớn không được làm treo sidebar.
- **Màu chói.** Dùng bảng màu dịu của ShellX, không gradient, không quầng sáng (đúng khẩu vị người dùng: màu chủ đạo `#60a5fa`).
- **Webview tải nội dung từ mạng.** Trang chỉ nạp file đóng gói sẵn trong app, giống trang agent session hiện nay.

## 5. Đã chốt với người dùng

| Chủ đề | Quyết định |
|---|---|
| Phạm vi | Chỉ xem: graph, commit, branch, file đổi, diff của file |
| Chỗ đặt | Cả hai (phương án C trong `placement.html`): tab "Git" trong sidebar phải, và nút mở chính view đó thành tab trong workspace |
| Thư viện vẽ graph | `@tomplum/react-git-log` (Apache-2.0), chọn sau khi chạy thử so với `commit-graph` (§6.2) |
| Repo nào | Repo chứa thư mục của terminal đang focus; đổi terminal hoặc `cd` sang repo khác thì graph đổi theo |
| Branch hiển thị | Mặc định mọi branch, kể cả remote; có ô lọc branch |
| Tìm kiếm | Theo message, hash, tác giả, **chỉ trong các commit đã tải**: tô sáng chỗ khớp và nhảy tới kết quả trước/sau, graph giữ nguyên (§6.2) |
| Giới hạn tải | Tải dần khi cuộn, **dừng ở 5.000 commit** gần nhất, không tải tới commit đầu tiên (§6.2) |
| Làm mới | Tự làm mới khi repo đổi (commit mới, checkout, pull) |
| Bấm commit | Hiện message đầy đủ, hash, tác giả, ngày, danh sách file đổi kèm số dòng +/− |
| Bấm file | Mở diff của file đó trong commit |
| Repo SSH/remote | Không làm ở bản đầu |

## 6. Thiết kế

### 6.1 Chỗ đặt và cách mở

- Thêm một mode `git` vào sidebar phải (`RightSidebarMode`, `Sources/RightSidebarMode.swift`), nhãn "Git", nằm sau Files / Find.
  Một mode mới phải được nối vào nhiều chỗ: availability và alias CLI, analytics, switch nội dung trong
  `RightSidebarPanelView`, chính sách đồng bộ root, `RightSidebarToolPanel`, thứ tự và ẩn tab, command palette, persistence.
  Danh sách đầy đủ nằm ở §9.
- Cho mode này vào `paneModes`. Như vậy cơ chế có sẵn "mở tab sidebar thành pane" (`openOrFocusRightSidebarToolSurface`) cung
  cấp tab rộng mà không cần thêm kiểu panel mới. Nút ⤢ trên thanh công cụ của view gọi đúng đường đó.
- Command palette có hai lệnh: hiện Git trong sidebar, và mở Git Graph thành tab. CLI dùng cơ chế có sẵn
  `shellx right-sidebar set git`.
- Không thêm phím tắt mặc định mới. Người dùng tự gán qua cài đặt phím tắt nếu cần. Lựa chọn của người viết spec.
- Bật sẵn cho mọi người, không đặt sau cờ beta. Ai không cần thì ẩn tab bằng cài đặt ẩn tab sidebar đã có. Lựa chọn của người
  viết spec.

### 6.2 Trang web và thư viện

View là một trang mới trong app React `webviews/` (React 19, TanStack Router, build bằng Vite, test bằng `bun test`). App này đã
chạy diff viewer và agent session.

- Thêm route `/git-graph` vào `webviews/src/router.tsx`. `scripts/build-webviews-app.sh` sinh thêm `git-graph.html`, giống cách
  nó đang sinh `agent-session.html`. Phía Swift nạp file này bằng `loadFileURL` từ bundle, giống
  `AgentSessionWebRendererCoordinator.loadShellIfNeeded`.
- Route mới phải qua được `verify:tanstack-router` (`webviews/scripts/verify-tanstack-router-security.mjs`).
- Vẽ graph bằng `@tomplum/react-git-log` 3.5.x: `GitLog` với `GitLog.GraphHTMLGrid` và `GitLog.Table`.

**Bài học từ bản thử** (ảnh ở thư mục design; code thử không giữ lại):

- **Lane:** thư viện xếp lane đúng trên 300 commit thật của ShellX (56 merge, 6 branch), kể cả 16 parent nằm ngoài trang đầu.
- **Màu:** truyền màu dạng `rgb(r, g, b)`. Truyền mã hex thì graph vẽ ra trong suốt, vì ở chế độ tối thư viện tự ghép kênh alpha
  vào chuỗi `rgb(`.
- **Nhãn ref:** thư viện chỉ gắn nhãn cho commit đầu nhánh không có commit con. Vì vậy `main`, `origin/main`, `release/*` và mọi
  tag đều không có nhãn. Phải tự vẽ chip ref trong dòng bảng (prop `row` của `GitLog.Table`), xem §6.4.
- **Dòng WIP:** thư viện tự thêm một dòng "index" phía trên HEAD. Xem §6.6 cho cách dùng.
- **So với `commit-graph`:** thư viện kia ghim React 18 làm dependency cứng, và vỡ bố cục ở bề ngang 390 px. Đó là lý do chọn
  react-git-log.

**Bố cục** (theo mockup):

- **Thanh công cụ:**
  - ô chọn branch, mặc định "Tất cả";
  - công tắc hiện branch remote;
  - ô tìm;
  - nút làm mới;
  - nút ⤢ (chỉ có trong sidebar).
- **Danh sách commit:**
  - Ở bề ngang hẹp (sidebar), mỗi dòng gồm graph, chip ref, message và thời gian tương đối.
  - Ở bề ngang rộng (tab), thêm các cột Date, Author và Commit (hash ngắn).
  - Mốc chuyển giữa hai kiểu do người làm chọn.
- **Khung chi tiết** ở dưới, hiện khi chọn một commit:
  - message đầy đủ, hash, tác giả, ngày;
  - danh sách file đổi: trạng thái, đường dẫn, số dòng +/−.

**Tìm kiếm** (người dùng chọn):

- Chỉ tìm trong các commit đã tải. Phía Swift không có yêu cầu tìm kiếm nào, nên chữ người dùng gõ không bao giờ đi vào lệnh git.
- Khớp theo subject, hash (theo tiền tố) và tên hoặc email tác giả, không phân biệt hoa thường.
- Không ẩn dòng nào. Các dòng khớp được tô sáng, có số "3/17" và nút hoặc phím Enter / Shift+Enter để nhảy tới kết quả
  sau/trước. Lý do: thư viện vẽ graph sai khi bị ẩn bớt dòng.
- Nếu đã tải hết mà không thấy, hiện "Không có kết quả trong N commit đã tải".

**Giới hạn tải** (người dùng chọn):

- Tải từng trang khi cuộn gần cuối danh sách.
- Dừng ở 5.000 commit. Khi đó dòng cuối là "Đã hiện 5.000 commit gần nhất".
- Ô lọc branch cũng tính trong giới hạn này: lọc một branch thì vẫn tối đa 5.000 commit của branch đó.
- Lý do: `GitLog` phải giữ toàn bộ commit đã tải và vẽ lại graph mỗi lần thêm trang. Bản có phân trang `GitLogPaged` chỉ chạy với
  một branch, và thư viện không có cơ chế chỉ vẽ phần đang hiện trên màn hình.

### 6.3 Dữ liệu và cầu nối Swift ↔ trang

Phía Swift chạy git và trả dữ liệu cho trang qua một script message handler có reply. Mẫu có sẵn là `DiffSidecarBridge`
(`Sources/Panels/DiffSidecarBridge.swift`, handler `cmuxDiff`). Trang chỉ gọi được các yêu cầu đọc sau:

| Yêu cầu | Lệnh git (đều chỉ đọc) |
|---|---|
| Một trang commit | `git log --all --date-order` với `--format` có hash, parents, tác giả, email, ngày, subject; phân trang theo số lượng |
| Danh sách ref | `git for-each-ref` cho `refs/heads`, `refs/remotes`, `refs/tags`. Tag annotated lấy commit đã peel |
| File đổi của một commit | `git show --numstat --name-status -M --format= <sha>`. Commit merge so với parent đầu tiên |
| Trạng thái thư mục làm việc | Dùng lại `GitStatusProvider` hoặc `git status --porcelain` |
| Mở diff một file | Không trả dữ liệu, chỉ yêu cầu app mở diff viewer (§6.5) |

- Chạy git ngoài main thread, có timeout, có giới hạn byte đầu ra, và xoá `GIT_DIR`, `GIT_WORK_TREE`, `GIT_CONFIG*` khỏi môi
  trường. `SystemWorkspaceChangesGitRunner` trong `Packages/macOS/CmuxGit` đã làm đúng việc này nhưng đang là internal; người
  làm chọn cách dùng lại (mở ra hoặc bọc lại). `CommandRunning` trong CmuxFoundation là lựa chọn khác.
- Đặt `GIT_OPTIONAL_LOCKS=0` cho mọi lệnh.
- Dữ liệu từ trang (sha, đường dẫn, tên branch dùng để lọc) phải được kiểm tra trước khi đưa vào lệnh git: sha là hex, đường dẫn
  nằm trong danh sách file của commit đó. Không ghép chuỗi thành lệnh shell.
- Commit message và tên ref là dữ liệu không tin cậy. Trang hiển thị chúng dạng text, không bao giờ dạng HTML.

### 6.4 Chip ref

Mỗi dòng tự vẽ chip cho mọi ref trỏ vào commit đó, theo màu mockup:

- branch local: viền xanh `#60a5fa`;
- branch đang checkout: nền xanh đặc, chữ tối;
- remote: viền lilac;
- tag: viền vàng dịu.

Bỏ qua `origin/HEAD`. Sidebar hẹp nên khi có nhiều chip thì hiện chip đầu kèm "+n". Thứ tự ưu tiên: HEAD, local, remote, tag.

### 6.5 Bấm file thì mở diff

Dùng lại diff viewer web có sẵn, không viết bộ hiển thị diff mới. Hiện diff viewer nhận nguồn là working tree, staged, so với
merge-base, hoặc một patch (`DiffSource` trong `CLI/cmux_open.swift`). Cách nối do người làm chọn, ví dụ:

- thêm một nguồn "commit" vào `DiffSource`;
- hoặc đưa patch của `git show <sha> -- <path>` vào đường patch có sẵn.

Diff mở thành split cạnh pane đang focus, giống lệnh "Open Diff Viewer" hiện nay.

### 6.6 Dòng thay đổi chưa commit

Khi thư mục làm việc có thay đổi, hiện dòng "index" của react-git-log kèm số file thêm / sửa / xoá (`indexStatus`). Bấm vào thì
mở diff viewer với nguồn working tree, đúng hành vi của "Open Diff Viewer". Khi sạch thì không hiện dòng này. Lựa chọn của người
viết spec.

### 6.7 Repo nào và khi nào đổi

- **Sidebar:** lấy thư mục của terminal đang focus qua chuỗi có sẵn (`Workspace.panelDirectories`,
  `resolvedWorkingDirectory()`), rồi tìm gốc repo bằng `GitMetadataService.workTreeRoot(forDirectory:)`. Theo dõi thay đổi giống
  cách `RightSidebarToolPanel` đang theo dõi root. Khi gốc repo đổi thì nạp lại; khi chỉ đổi thư mục con trong cùng repo thì giữ
  nguyên.
- **Tab rộng:** giữ repo của lúc mở tab. Tiêu đề tab có tên repo. Lựa chọn của người viết spec: khi focus vào chính tab Git Graph
  thì không còn "terminal đang focus" để bám theo.
  - Mỗi workspace có tối đa một tab Git Graph, đúng như `openOrFocusRightSidebarToolSurface` hiện nay. Bấm ⤢ khi tab đã có thì
    focus tab đó và chuyển nó sang repo mà sidebar đang hiện, không mở thêm tab. Lựa chọn của người viết spec.
  - Vì `RightSidebarToolPanel` đang bám theo thư mục của workspace và lấy tên mode làm tiêu đề, panel cần thêm gốc repo đã ghim
    cho mode `git`, và tiêu đề lấy từ tên repo.
  - `SessionRightSidebarToolPanelSnapshot` lưu thêm gốc repo, dạng trường tuỳ chọn để snapshot cũ vẫn đọc được.
  - Mở lại app thì tab mở đúng repo đã lưu. Nếu thư mục đó không còn là repo thì hiện trạng thái trống (§6.9).
- **Terminal đang SSH hoặc workspace remote:** hiện thông báo "Git Graph hiện chỉ hỗ trợ repo trên máy này". Không chạy git.

### 6.8 Làm mới

- Theo dõi `.git` (HEAD, refs, packed-refs, logs) bằng cơ chế theo dõi file có sẵn của `GitMetadataService` (`watchedPaths`,
  `watchDescriptor`).
- Gom các thay đổi liên tiếp (debounce) rồi mới nạp lại.
- Giữ commit đang chọn và vị trí cuộn nếu commit đó vẫn còn.
- Khi tab không hiện thì không làm mới. Khi tab hiện lại thì làm mới một lần.

### 6.9 Trạng thái trống và lỗi

Mỗi trường hợp có một câu thông báo riêng, không để trang trắng:

- thư mục không phải repo git;
- repo chưa có commit nào;
- không tìm thấy `git`;
- git quá thời gian chờ hoặc báo lỗi (kèm nút thử lại);
- terminal remote (§6.7).

### 6.10 Màu và giao diện

- **Lane:** xoay vòng theo bảng `#60a5fa`, `#c4b5fd`, `#6fd49a`, `#e8c468`, `#7dd3fc`, `#a5b4fc`, `#e88a8a`, `#99f6e4`, truyền
  vào thư viện dạng `rgb()`.
- **Nền và chữ:** lấy theo token của `ShellXPalette`.
- **Sáng/tối:** theo cách app `webviews/` đang xử lý (`appearance.ts`).

### 6.11 Bản địa hoá

- **Phía Swift:** mọi chuỗi (tên tab, lệnh palette, thông báo trạng thái) qua `String(localized:)`, đủ 10 ngôn ngữ trong
  `Resources/Localizable.xcstrings`.
- **Phía trang:** nhận nhãn từ Swift, theo mẫu `createDiffViewerLabelResolver` của diff viewer. Các nhãn đó cũng đủ 10 ngôn ngữ.
- **Ngày giờ** định dạng theo locale.
- Lưu ý: `./scripts/localize-changes` đang lỗi trong fork này vì thiếu `web/i18n/routing.ts`. Dùng
  `python3 scripts/localization_catalog.py check` để kiểm.

### 6.12 Giấy phép

ShellX là GPL-3.0-or-later. Các gói mới đều tương thích:

- `@tomplum/react-git-log` 3.5.x: Apache-2.0;
- `@uidotdev/usehooks`, `classnames`, `dayjs`, `react-tiny-popover`: MIT;
- `fastpriorityqueue`: Apache-2.0.

Thêm các gói này vào `THIRD_PARTY_LICENSES.md`.

## 7. Kiểm chứng

Theo `CLAUDE.md`: test hành vi phải đỏ trước khi sửa, rồi xanh sau khi sửa, ghi lại cả hai.

- **Test Swift:**
  - đọc đầu ra `git log` (gồm merge, commit gốc, message có ký tự lạ);
  - map ref (tag annotated, `origin/HEAD`);
  - kiểm tra sha và đường dẫn từ trang;
  - chọn repo theo thư mục.
- **Test `bun test` trong `webviews/`:**
  - chip ref theo thứ tự ưu tiên;
  - đổi màu hex sang `rgb()`;
  - bố cục hẹp và rộng;
  - lọc và tìm.
- **Repo mẫu dựng bằng script trong test**, có merge lồng nhau và parent nằm ngoài trang đầu, so lane với
  `git log --graph --all`.
- **Đo thời gian** trang đầu trên repo ShellX.
- **Xem bằng mắt:** máy dev không chạy được `reload.sh --launch` có gắn tag (thiếu credential dev). Chụp view bằng một suite test
  tạm (dùng `cacheDisplay` ra PNG) như các lần trước, và nói rõ đó không phải bấm thật trong app.
- **Trước khi xong:** chạy `python3 scripts/verify-local.py`, `scripts/sync-test-wiring` (nếu thêm file trong `cmuxTests/`), và
  build bằng `scripts/test-unit.sh build`.

## 8. Để người làm tự quyết

- Giao thức cụ thể của cầu nối: tên handler, kiểu message, kích thước trang, cách huỷ yêu cầu cũ.
- Mốc bề ngang chuyển giữa bố cục hẹp và rộng, icon SF Symbol của tab, khoảng debounce.
- Dùng hay bỏ `GitLog.Tags` khi đã tự vẽ chip.
- Cách diff viewer nhận nguồn "một file trong một commit" (§6.5).
- Có giữ webview sống khi người dùng chuyển sang tab sidebar khác hay không.

## 9. Chỗ phải sửa khi thêm mode sidebar mới

Do agent khảo sát code tìm ra, để người làm khỏi phải dò lại:

- `Sources/RightSidebarMode.swift`: enum, `paneModes`
- `Sources/RightSidebarMode+Availability.swift`: alias CLI, `isAvailable`
- `Sources/RightSidebarMode+ProductFeature.swift`: analytics
- `Sources/RightSidebarPanelView.swift`: switch nội dung, chính sách đồng bộ root
- `Sources/RightSidebarToolPanel.swift`: bản chạy trong pane
- `Sources/RightSidebarTabPreferences.swift` và
  `Packages/macOS/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/SidebarSection+RightSidebarTabs.swift`: thứ tự và ẩn tab
- `Sources/ContentView+RightSidebarCommandPalette.swift`: command palette
- `Sources/SessionPersistence+Todos.swift`: persistence

## 10. Các quyết định của người viết spec

Người dùng nên xem lại các điểm này:

1. Làm bằng trang web trong `webviews/` thay vì viết native SwiftUI (hệ quả của việc chọn react-git-log).
2. Có dòng "thay đổi chưa commit" khi repo bẩn; bấm vào mở diff working tree.
3. Tab rộng giữ repo của lúc mở; chỉ sidebar bám theo terminal đang focus. Mỗi workspace một tab; bấm ⤢ lần nữa thì tab đó
   chuyển sang repo của sidebar; repo được lưu qua lần mở lại app.
4. Commit merge hiện file đổi so với parent đầu tiên.
5. Không thêm phím tắt mặc định; bật sẵn, không qua cờ beta.
6. Không làm cho app iOS và app Windows.
7. Hiện cả tag dạng chip, dù người dùng chỉ nhắc tới branch.
