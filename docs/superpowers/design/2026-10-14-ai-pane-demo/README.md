# Pane AI — đề xuất và demo

Trang tĩnh trình bày đề xuất pane AI cho ShellX, kèm một demo bấm thử được: cửa sổ ShellX mô phỏng, agent giả nói đúng thông điệp ACP v1, và nhật ký ghi mọi thông điệp.

## Chạy

Không cần cài gì. Mở thẳng tệp:

```sh
open docs/superpowers/design/2026-10-14-ai-pane-demo/index.html
```

Hoặc chạy một server tĩnh rồi vào <http://localhost:8765>:

```sh
python3 -m http.server 8765 --directory docs/superpowers/design/2026-10-14-ai-pane-demo
```

Mở thẳng một kịch bản, chạy nhanh gấp đôi: `index.html?kb=3&tocdo=2` (`kb` từ 1 đến 6).

## Tệp

| Tệp | Nội dung |
|---|---|
| `index.html` | Đề xuất: tổng quan, cách hoạt động, 5 quyết định, giai đoạn 1, plugin, điện thoại, lộ trình, rủi ro, 4 việc cần quyết |
| `demo.js` | Đóng vai ShellX: dựng pane AI từ thông điệp ACP, dự án giả trên “đĩa”, điểm khôi phục, nhật ký |
| `demo-data.js` | Agent giả, dự án mẫu `shop-web`, dữ liệu ACP và 6 kịch bản |
| `page.js` | Giao diện sáng/tối, sơ đồ kiến trúc, form trả lời |
| `styles.css` | Bảng màu desktop của ShellX (`ShellxDesktopColors`) cho cửa sổ; token bảng thiết kế mobile cho trang |

## Độ chính xác

Hình dạng thông điệp theo schema ACP v1 1.25.0 (09/10/2026). Danh sách chế độ, lựa chọn xin quyền, cách đăng nhập và tiêu đề việc agent làm lấy từ mã nguồn `@agentclientprotocol/claude-agent-acp` 0.90.0. Nội dung trả lời của agent, tên model và đường dẫn là minh hoạ.

Trang chỉ tải font từ Google Fonts; không có mạng thì dùng font hệ thống. Lựa chọn ở mục “Cần bạn quyết” và giao diện sáng/tối được nhớ trong `localStorage` của trình duyệt.
