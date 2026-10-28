# Ledger: ShellX mobile workspaces

Spec: `docs/superpowers/specs/2026-10-28-shellx-mobile-workspaces-design.md`. Kế hoạch đợt 1:
`docs/superpowers/plans/2026-10-28-shellx-mobile-workspaces-wave1.md`. Nhánh: `feat/shellx-mobile-workspaces`
(chưa push, chưa gộp vào develop).

## Đợt 1 — trạng thái 29/10/2026

- Code xong ở `899e6aec51`: 6 task, mỗi task qua review riêng; review toàn nhánh (opus) → 11 điểm sửa trong một
  đợt (19 commit), soát lại sạch.
- Test ở `899e6aec51` (lần chạy của đợt sửa cuối):
  - shellx-link `swift test`: 198 test, 0 lỗi, 9 bỏ qua (relay integration, `CMUX_RELAY_BIN` không đặt) — chạy ở
    `810c96798c`; sau đó shellx-link chỉ đổi PROTOCOL.md.
  - Mac `scripts/shellx/test-app.sh ShellXLinkWorkspaceSourceTests ShellXLinkSessionSourceTests`: 20/20.
  - iOS `dev.sh test all`: core 402/0, app 145/0, Release chưa ký build được; `check-ios-license.sh` ok,
    `check-strings.py` ok (225 khoá).
  - `AttachmentPreparerTests.testCancellingAHungFileReadStopsIt` từng đỏ ở nhánh task 5/6 rồi xanh ở bản gộp:
    chập chờn, không phải hồi quy.
- Chưa chạy: `python3 scripts/verify-local.py`; đo các tiêu chí 2.2 trên máy thật.
- Bản dogfood:
  - Mac: Release arm64 ở `build-shellx-wave1/` (thư mục riêng, loại khỏi git qua `.git/info/exclude`), ký Developer
    ID tại máy, **không notarize**, phiên bản vẫn ghi 1.5.1 (117). App ShellX người dùng đang chạy (từ `build-shellx/`)
    không bị đụng tới.
  - iPhone: `ShellX Dev` (com.shellx.dev) đã cài lên iPhone 11 Pro ngày 29/10 02:01; lần mở tự động bị từ chối vì máy
    khoá.
- Lúc build, task 3 đã dời một `ShellXLinkCore.swiftmodule`/`.o` cũ (26/10) ra khỏi DerivedData mặc định
  `Build/Products/Debug` (chúng che bản framework và làm mọi build app hỏng).

## Quyết định của người điều phối (đợt 1)

Mỗi dòng: quyết định — lý do — giá của nó nếu sai.

1. Nhãn "xong" lấy từ `SessionFinishDetector` trong bộ nhớ của `MachineHub`, không lưu — chỗ lưu cũ nằm trong kho
   chat gộp đã bỏ — mở lại app thì nhãn "xong" mất.
2. Task 3 và 4 chạy song song, mỗi task một worktree — hai cây file tách nhau — rủi ro xung đột khi gộp (không xảy ra).
3. Tên rỗng sau khi làm sạch → `failed`, nút Lưu tắt; không có "về tên tự động" — đường mobile của cmux không cho
   `clear_name` — chưa đặt lại được tên tự động từ điện thoại.
4. Danh sách workspace quá lớn theo luật của `agent.sessions` (cắt dần, không gửi thiếu; `too_large` / bỏ push) —
   một luật cho cả hai danh sách — Mac có danh sách khổng lồ sẽ không hiện gì.
5. Host không chống lặp theo `call_id` cho lệnh điều khiển — điện thoại không bao giờ gửi lại — một client lỗi gửi
   lại có thể tạo hai workspace.
6. Task 3 (Mac) chạy ở bản checkout chính, Task 4 trong worktree, khi Task 2 còn đang review — build Mac cần
   GhosttyKit và submodule của checkout chính — sửa API ở Task 2 sẽ phải làm lại một ít.
7. Lỗi `.remote` (`unsupported`/`too_large`) khi đọc danh sách = "không có danh sách", không phải hỏng kết nối — danh
   sách quá lớn không được làm điện thoại mất kết nối — Mac đó hiện như Mac cũ thay vì báo lỗi.
8. Lệnh điều khiển tới Mac không có `workspace_control` → `.failed`, không gửi — giao diện đã ẩn các nút đó — câu
   báo "không làm được" ở một đường giao diện không mở ra.
9. Task 5 bắt đầu khi Task 4 còn review — tiết kiệm thời gian — đổi tên API ở Task 4 thì Task 5 phải sửa theo.
10. Task 6 bắt đầu khi Task 5 còn review, tự gộp bản sửa của Task 4 — giữ chuỗi iOS chạy — sửa ở Task 5 phải gộp lại.
11. Workspace "máy ở xa" của ShellX (`ShellXTabWorkspaceOpener`) vẫn được liệt kê và điều khiển — cờ
    `ShellXFeatures.remoteMachines` đang tắt nên không có workspace nào như vậy — phải loại chúng ra trước khi bật cờ.
12. Đóng workspace đang chọn trên Mac từ điện thoại thì Mac chọn workspace bên cạnh — không tránh được, giống đóng
    trên Mac — người ở Mac thấy màn hình chuyển.
13. Nguồn Mac tự dựng hàng có kiểu riêng thay vì dùng `v2MobileWorkspaceList`/`MobileWorkspaceListObserver` — dùng lại
    các hàm cấp thấp; bản cmux là `[String: Any]` gắn với host iroh — hai bộ dựng hàng có thể lệch nhau.
14. `AttachmentPreparerTests` đỏ là chập chờn — đã xanh ở bản gộp — nếu sai thì một hồi quy thật bị che.

## Điểm nhỏ để lại (không chặn dogfood)

- Giao thức / link: thiếu vài test âm cho codec; lệnh điều khiển không giới hạn mỗi phiên; doc
  `WorkspaceSource.workspaces()` nên ghi "trả nhanh"; init `LinkHost` không đồng nhất tham số mặc định; dòng doc
  dài ở PROTOCOL.md (~763); vài comment ví dụ chỉ nói "workspace cuối cùng".
- Mac: hai watch thừa (panels, paneLayoutVersion) và comment sai; theo dõi cả workspace SSH/cloud không bao giờ liệt
  kê; thứ tự cửa sổ theo thứ tự băm (có thể đổi khi mở/đóng cửa sổ); `selected` không được đẩy khi chỉ đổi focus;
  chưa có test cho `stop()` của observer sống; `waitUntilQuiet` im lặng sau 6 s.
- iOS: `MachineHub.swift` ~750+ dòng; lấy lại danh sách thất bại giữa phiên vì `too_large` đóng client một lần; ＋ bị
  tắt thay vì ẩn khi không Mac nào hỗ trợ; tạo xong vẫn đẩy màn workspace dù người dùng đã đi chỗ khác; khối gửi
  lệnh lặp ở `WorkspaceView`/`WorkspaceListView`; `NoticeCapsule` lặp modifier của `AgentScreen`; vài test render
  yếu; `WorkspaceView.body` phụ thuộc pha mic (vẽ lại mỗi từ nhận dạng); chọn lại chip mặc định bị bỏ qua khi đang
  hiện chat agent; `AppGraph.swift:13` còn ghi "Measures launchToHome"; Mac có danh sách quá lớn hiện như Mac cũ.
- Tiêu chí 2.2 số 2 (Mac đổi → điện thoại thấy) chưa có số đo: `workspace.changed` không mang mốc giờ của Mac.

## Cần kiểm trên iPhone (dogfood)

1. Giữ mic rồi thả: gửi. Giữ mic rồi kéo trái: huỷ, không chuyển chip. Đang giữ mic thì vuốt không đổi pane.
2. Bàn phím và ô nhắn trong màn vuốt pane: ô nhắn nằm sát bàn phím, trang không nhảy chip khi bàn phím lên/xuống.
3. Vuốt mép trái để quay lại khi đang ở chip đầu.
4. Chữ đang soạn và vị trí cuộn còn nguyên khi vuốt sang chip khác rồi quay lại.
5. Vuốt trái dòng workspace → Đóng: dòng không biến mất trước khi xác nhận.
6. Tạo workspace từ điện thoại: Mac không chuyển workspace; điện thoại mở workspace mới.
7. Đổi tên, đóng (kể cả workspace cuối cùng → báo Mac không cho).
8. `git checkout` nhánh khác trên Mac → dòng workspace trên điện thoại đổi nhánh trong vòng ~1 s.
9. Đo tiêu chí 1 (mở app → thấy danh sách) qua `LatencyLog` (`launchToWorkspaceList`).
