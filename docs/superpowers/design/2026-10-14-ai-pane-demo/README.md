# Giao diện AI cho ShellX — đề xuất và demo

Trang tĩnh trình bày đề xuất V2: giao diện AI cho người không muốn dùng terminal, tool riêng nhúng bằng một URL, và điện thoại xem, điều khiển được cả hai. Kèm một demo bấm thử được:
- cửa sổ ShellX mô phỏng;
- agent giả nói đúng thông điệp ACP v1;
- app điện thoại mô phỏng;
- nhật ký ghi mọi thông điệp.

## Chạy

Không cần cài gì. Mở thẳng tệp:

```sh
open docs/superpowers/design/2026-10-14-ai-pane-demo/index.html
```

Hoặc chạy một server tĩnh rồi vào <http://localhost:8765>:

```sh
python3 -m http.server 8765 --directory docs/superpowers/design/2026-10-14-ai-pane-demo
```

Muốn mở thẳng một kịch bản và chạy nhanh gấp đôi, dùng `index.html?kb=7&tocdo=2` (`kb` nhận giá trị từ 1 đến 7).

## Bảy kịch bản

1. **Một lượt sửa lỗi:** thẻ, xin quyền, diff, hoàn tác.
2. **Hoàn tác lệnh shell:** agent sửa bằng `sed`, không gửi diff nào, nhưng panel Thay đổi vẫn bắt được.
3. **Lần đầu dùng:** màn chào "Giao diện AI | Terminal"; đăng nhập chạy trong một khung nhỏ.
4. **Thoát rồi mở lại:** phiên được khôi phục bằng `session/load`.
5. **Agent gặp sự cố:** agent chết giữa lượt, rồi khởi động lại.
6. **Tool qua URL (GĐ2):** thêm tool bằng tên và URL; tool mở cạnh pane AI.
7. **Điện thoại (GĐ2):** gửi yêu cầu, trả lời xin quyền và mở tool, tất cả từ điện thoại.

## Tệp

| Tệp | Nội dung |
|---|---|
| `index.html` | Đề xuất: tổng quan, cách hoạt động, 7 quyết định, giai đoạn 1, tool qua URL, điện thoại, lộ trình, rủi ro, những gì đã chốt |
| `demo.js` | Đóng vai ShellX: dựng tab AI từ thông điệp ACP, quản lý dự án giả trên "đĩa", điểm khôi phục, pane tool, app điện thoại và nhật ký |
| `demo-data.js` | Agent giả, dự án mẫu `shop-web`, dữ liệu ACP và 7 kịch bản |
| `page.js` | Chế độ sáng/tối, sơ đồ kiến trúc |
| `styles.css` | Cửa sổ dùng bảng màu desktop của ShellX (`ShellxDesktopColors`); điện thoại dùng token tối của bảng thiết kế mobile; phần trang dùng token của bảng thiết kế |

## Độ chính xác

- **Theo nguồn thật:**
  - Hình dạng thông điệp theo schema ACP v1 bản 1.25.0 (09/10/2026).
  - Danh sách chế độ, lựa chọn xin quyền, cách đăng nhập và tiêu đề việc agent làm lấy từ mã nguồn `@agentclientprotocol/claude-agent-acp` 0.90.0.
- **Đề xuất, chưa có trong giao thức:** các loại tin `ai.*` và `tool.*` giữa desktop và điện thoại.
- **Minh hoạ:** nội dung agent trả lời, tên model và đường dẫn.

Trang chỉ tải font từ Google Fonts; không có mạng thì dùng font hệ thống. Chế độ sáng/tối được nhớ trong `localStorage` của trình duyệt.
