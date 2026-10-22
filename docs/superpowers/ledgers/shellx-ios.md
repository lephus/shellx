# Sổ quyết định ShellX iOS

Sổ ghi quyết định cho dự án app iOS và ShellX Link. Các task sau ghi tiếp vào đây.

## Giấy phép (2026-10-22)

- `cmux-tui/Cargo.toml:60` ghi `license = "MIT"`, nhưng không có file LICENSE nào trong thư mục đó. `LICENSE` ở gốc repo (Manaflow GPL) nói cmux-tui theo "license that this file or their own notices state", tức là đang **mơ hồ**, phải hỏi Manaflow trước khi dựa vào nó.
- `ghostty/LICENSE` là MIT.
- `shellx-core` là GPL-3.0-or-later. Tác giả: Phu.le và "Richard". Không thấy code chép từ Manaflow. Người dùng phải xác nhận "Richard" là ai trước khi nhúng `shellx-core` vào app App Store.
- `shellx-link/` là gói MIT riêng, không phụ thuộc và không chép code từ `ios/`, `Packages/iOS/`, `Packages/Shared/`, `cmux-tui/`. Ranh giới được kiểm bằng `scripts/shellx/check-link-license.sh` (chạy trong `PackageBoundaryTests`).

## D-iOS-0 (2026-10-22): phiên riêng cho ShellX Link

ShellX Link dùng phiên Noise riêng trên `link_slot`. Lý do:

- `Service` là enum đóng (`cmux-remote-protocol/src/rpc.rs:120`), không thêm dịch vụ mới được mà không đổi giao thức cmux.
- Đăng ký lần hai trên cùng slot sẽ thay daemon đang chạy (`cmux-relay/src/relay.rs:684-730`).
