---
layout: ../../layouts/Guide.astro
lang: vi
slug: ssh-from-phone
order: 2
title: "SSH từ điện thoại mà không cần mở port"
metaTitle: "SSH từ điện thoại không cần mở port — Hướng dẫn ShellX"
description: "Các cách SSH từ điện thoại quen thuộc, chúng đòi hỏi gì (mở port, IP tĩnh, VPN), và cách ShellX đưa phiên SSH, tmux của bạn lên điện thoại mà không cần những thứ đó."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["SSH từ điện thoại", "SSH trên iPhone", "SSH trên Android", "SSH không cần mở port", "tmux trên điện thoại", "thay thế SSH client"]
---

Muốn có shell trên điện thoại thường là một trong hai việc: vào một **server** (VPS, máy dev, Raspberry Pi), hoặc vào **chính máy tính của bạn** để xem một việc đang chạy. Bài này nói cả hai, và ShellX nằm ở đâu trong đó.

## Cách quen thuộc: app SSH trên điện thoại

App SSH kết nối thẳng tới SSH server. Muốn vậy, server phải nhận được kết nối từ chỗ điện thoại của bạn:

- **Server công khai** (VPS trên cloud) đã có IP công khai và cổng 22 mở. Ở đây app SSH là lựa chọn đơn giản nhất.
- **Máy ở nhà hay ở công ty** nằm sau router, nhiều khi sau CGNAT, không có IP công khai. Bạn cần mở port trên router, tên miền động (DDNS), hoặc VPN như WireGuard hay Tailscale.
- **Chính máy Mac hoặc PC của bạn** còn phải bật SSH server (Remote Login trên macOS, OpenSSH Server trên Windows), và bạn nhận một shell **mới**, không phải các cửa sổ terminal đang mở, trừ khi mọi thứ chạy trong `tmux`.

Gõ trên điện thoại trong một phiên SSH trần cũng khổ khi mạng chập chờn: rớt mạng là mất phiên, trừ khi dùng `tmux` hoặc `mosh`.

## Cách của ShellX: mở các phiên đang chạy trên máy tính

ShellX bắt đầu từ máy tính của bạn thay vì từ server:

1. **Cài ShellX trên Mac hoặc PC** và đăng ký tài khoản.
2. **Cài app trên điện thoại**, đăng nhập, ghép nối bằng cách quét mã QR từ menu khay trên máy tính.
3. **SSH như bình thường từ app ShellX trên máy tính.** Chạy `ssh my-server` trong tab bất kỳ, hoặc bấm **⌘⇧K** (Windows **Ctrl+Shift+K**) và chọn máy chủ từ `~/.ssh/config`. ShellX mở một workspace SSH cho máy đó.
4. **Mở phiên trên điện thoại.** Điện thoại thấy mọi pane, kể cả pane SSH, và hiện thư mục từ xa dạng `host:/đường/dẫn`.

Vì cả máy tính và điện thoại đều **chủ động gọi ra** máy chủ chuyển tiếp của ShellX, không thiết bị nào trong mạng của bạn phải nhận kết nối vào: không mở port, không IP tĩnh, không VPN.

### Workspace SSH có gì thêm

- **Dùng `ssh` và SSH agent của bạn.** ShellX chạy binary `ssh` của hệ điều hành với khóa và `~/.ssh/config` của bạn. ShellX không bao giờ hỏi, giữ hay lưu mật khẩu; lời nhắc mật khẩu hay host key hiện ngay trong terminal như mọi terminal khác.
- **Tự kết nối lại.** Mất mạng thì pane báo mất kết nối và tự kết nối lại, đúng chỗ cũ trong bố cục.
- **Gắn tmux.** Liệt kê các phiên `tmux` trên máy tính hoặc trên server và gắn một phiên thành tab. Chương trình trong tmux vẫn chạy khi bạn ngắt kết nối.
- **Ngữ cảnh từ xa.** Sidebar hiện thư mục hiện tại, nhánh và các cổng đang nghe trên server; bấm vào cổng là mở trong trình duyệt qua cổng được chuyển tiếp.
- **Không cài gì trên server.** Không có agent hay daemon chạy ở đó; ShellX chỉ đặt một hook shell nhỏ trong thư mục cache của server để hiện thư mục và nhánh.

## Nên dùng cái nào?

| Tình huống | Hợp nhất |
|---|---|
| Vào nhanh một VPS công khai từ điện thoại, không qua máy tính | App SSH trên điện thoại |
| Máy tính ở nhà hoặc công ty, sau NAT, không có VPN | ShellX |
| Theo dõi việc chạy lâu hay AI agent đang chạy trong terminal | ShellX |
| Thông báo đẩy khi lệnh chạy xong | ShellX |
| Nhiều server, đã vào được qua VPN | Cái nào cũng được; ShellX thêm phiên trên điện thoại và thông báo |

## Bảo mật

Điện thoại và máy tính thống nhất khóa khi ghép nối bằng QR, và mọi nội dung terminal được mã hóa đầu cuối bằng giao thức Noise. Máy chủ chuyển tiếp chỉ chuyển gói đã mã hóa. Khóa SSH của bạn nằm trong SSH agent trên máy tính; chúng không bao giờ đi tới điện thoại hay máy chủ chuyển tiếp.

## Câu hỏi thường gặp

**ShellX có thay được app SSH của tôi không?** Với việc vào chính máy tính của bạn và các server bạn vẫn làm việc từ máy đó thì có. Nếu bạn muốn kết nối từ điện thoại thẳng tới server mà không qua máy tính nào, app SSH vẫn là đường trực tiếp.

**Có chạy trên Linux không?** App ShellX cho máy tính chạy trên macOS và Windows. Từ đó bạn SSH vào server Linux như thường.

**Có mất phí không?** ShellX hiện miễn phí.
