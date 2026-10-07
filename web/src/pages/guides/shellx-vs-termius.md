---
layout: ../../layouts/Guide.astro
lang: vi
slug: shellx-vs-termius
order: 4
title: "ShellX và Termius: chọn cái nào để có terminal trên điện thoại?"
metaTitle: "ShellX so với Termius — so sánh terminal trên điện thoại"
description: "Termius là SSH client đa nền tảng; ShellX đưa phiên terminal trên máy tính của bạn lên điện thoại. Khác nhau thế nào, khi nào chọn cái nào, dùng cả hai ra sao."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["ShellX vs Termius", "thay thế Termius", "SSH client hay remote terminal", "so sánh app terminal điện thoại", "Termius không cần mở port"]
---

Cả hai đều đưa terminal lên điện thoại, nhưng xuất phát từ hai đầu ngược nhau. **Termius** là SSH client: điện thoại của bạn kết nối tới server. **ShellX** là app terminal cho máy tính mà bạn mở được từ điện thoại: bạn thấy các phiên đang chạy trên máy Mac hoặc PC. Chọn cái nào tùy công việc của bạn thực sự chạy ở đâu.

## Trả lời ngắn

- Chọn **Termius** nếu bạn chủ yếu kết nối từ điện thoại **thẳng tới server** truy cập được qua SSH (VPS công khai, máy trong VPN), và muốn một SSH client hoàn chỉnh với danh sách máy, khóa và SFTP trên mọi thiết bị.
- Chọn **ShellX** nếu công việc chạy **trên chính máy tính của bạn** (build, script, AI coding agent, các phiên SSH và tmux bạn mở từ máy đó) và bạn muốn theo dõi, điều khiển từ điện thoại **mà không mở port hay cài VPN**, kèm thông báo đẩy.
- Nhiều người dùng **cả hai**: SSH client để vào server nhanh, ShellX cho các phiên trên máy tính.

## Mỗi công cụ hoạt động thế nào

**Termius** là SSH client có trên điện thoại và máy tính. Nó kết nối từ thiết bị bạn đang cầm tới một SSH server, hỗ trợ các giao thức như SSH, Mosh và Telnet, truyền file qua SFTP, chuyển tiếp cổng, snippet, và đồng bộ danh sách máy, khóa giữa các thiết bị qua tài khoản. Termius có gói miễn phí và trả phí; xem trang của họ để biết mỗi gói gồm gì.

Vì là client, server phải **truy cập được** từ điện thoại: IP công khai với cổng 22 mở, mở port trên router, hoặc VPN.

**ShellX** gồm hai phần: app terminal trên Mac hoặc PC, và app trên điện thoại. Cả hai cùng gọi ra máy chủ chuyển tiếp của ShellX, và điện thoại mở **đúng các phiên** đang có trên máy tính: mọi tab và pane, kể cả workspace SSH và phiên `tmux` bạn mở từ máy tính. Nội dung được mã hóa đầu cuối bằng giao thức Noise, nên máy chủ chuyển tiếp không đọc được.

## So sánh từng mục

| | ShellX | Termius |
|---|---|---|
| Mở gì trên điện thoại | Các phiên đang chạy trên Mac hoặc PC | Một phiên SSH mới tới server |
| Máy đích phải truy cập được từ ngoài | Không: cả hai thiết bị gọi ra | Có: IP công khai, mở port hoặc VPN |
| Chạy sau NAT / CGNAT không cần cấu hình | Có | Chỉ khi có VPN hoặc jump host truy cập được |
| SSH server trên chính máy tính | Không cần | Cần, nếu muốn vào máy tính |
| Tiếp tục đúng cửa sổ agent đang chạy | Có | Chỉ khi nó chạy trong tmux/screen để gắn vào |
| Thông báo đẩy khi lệnh xong hay chương trình cần bạn | Có (hook shell, OSC 9 / 777 / 99, `shellx notify`) | Không phải trọng tâm |
| Nền tảng máy tính | macOS, Windows | Điện thoại và máy tính |
| SFTP / truyền file | Không | Có |
| Giá | Hiện miễn phí | Có gói miễn phí và trả phí |

## Khi nào ShellX hợp hơn

- **AI coding agent.** Claude Code hay Codex chạy trong terminal vài phút rồi dừng để hỏi. ShellX cho bạn thấy đúng phiên đó trên điện thoại và đẩy thông báo khi nó cần bạn. Xem [Claude Code trên điện thoại](/guides/claude-code-on-phone/).
- **Máy tính ở nhà hay ở công ty**, không có IP công khai và bạn không muốn mở port. Xem [terminal từ xa không cần VPN](/guides/remote-terminal-without-vpn/).
- **Việc chạy lâu.** Build, migration, import dữ liệu: chạy ở bàn làm việc, xem trên điện thoại, được báo khi xong.

## Khi nào Termius hợp hơn

- Bạn quản lý nhiều server và muốn vào **thẳng từ điện thoại**, không qua máy tính nào.
- Bạn cần **SFTP** hay truyền file trên điện thoại.
- Bạn muốn có cả client cho Linux desktop.

## Dùng cả hai

Hai công cụ không xung đột. Giữ SSH client để vào server trực tiếp, và chạy ShellX trên máy tính để công việc ở đó, kể cả các phiên SSH bạn mở từ máy tính, luôn sẵn trên điện thoại.

*Termius là nhãn hiệu của chủ sở hữu. So sánh dựa trên thông tin công khai tại ngày ở trên; xem trang web của từng sản phẩm để biết tính năng hiện tại.*
