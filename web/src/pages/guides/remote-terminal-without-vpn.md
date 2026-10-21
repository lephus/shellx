---
layout: ../../layouts/Guide.astro
lang: vi
slug: remote-terminal-without-vpn
order: 3
title: "Điều khiển terminal Mac hoặc PC từ xa không cần VPN"
metaTitle: "Terminal Mac, PC từ xa không cần VPN — Hướng dẫn ShellX"
description: "Vào terminal của máy tính ở nhà hoặc công ty từ điện thoại khi máy nằm sau NAT hay CGNAT: không VPN, không mở port, không IP tĩnh, mã hóa đầu cuối."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["terminal từ xa không cần VPN", "truy cập terminal Mac từ xa", "remote terminal sau NAT", "không cần mở port", "truy cập từ xa CGNAT", "điều khiển terminal PC từ điện thoại"]
---

Bạn vừa chạy một bản build, một đợt import dữ liệu hay một AI agent trên máy tính, rồi phải ra ngoài. Bạn muốn xem terminal đó từ điện thoại. Câu trả lời thường gặp là VPN hoặc mở port. Cả hai đều chạy được, nhưng tốn công cài đặt hơn mức cần thiết, và có mạng làm không được.

## Vì sao truy cập từ xa thường khó

Máy tính ở nhà và ở công ty gần như không bao giờ có địa chỉ công khai:

- **Router che máy đi (NAT).** Muốn vào máy từ bên ngoài, bạn phải mở port trên router trỏ tới máy đó. Việc này cần quyền vào router, và phơi một dịch vụ ra cả Internet.
- **Nhiều nhà mạng và mạng di động dùng CGNAT.** Chính router của bạn cũng không có IP công khai, nên mở port là không thể.
- **Mạng công ty** hiếm khi cho bạn mở port.
- **VPN** (WireGuard, OpenVPN hay VPN dạng mesh như Tailscale) giải quyết việc kết nối tới máy, nhưng bạn vẫn cần SSH server trên máy tính và cách quay lại đúng các cửa sổ terminal đang mở.

## ShellX tránh được tất cả thế nào

ShellX đảo chiều kết nối. App ShellX trên máy tính và app trên điện thoại đều **chủ động gọi ra** máy chủ chuyển tiếp của ShellX qua Internet, giống như trình duyệt mở một trang web. Kết nối đi ra chạy được sau NAT, CGNAT và hầu hết mạng công ty, nên:

- **Không mở port**, và không có gì trên máy tính lắng nghe kết nối từ ngoài vào.
- **Không cần IP tĩnh** hay tên miền động.
- **Không cần app VPN** trên điện thoại hay máy tính.

Máy chủ chuyển tiếp chỉ ghép hai thiết bị của bạn và chuyển dữ liệu giữa chúng. Nó không đọc được dữ liệu đó: nội dung terminal được **mã hóa đầu cuối** bằng giao thức Noise, với khóa được thống nhất khi bạn ghép nối điện thoại bằng mã QR.

## Cài đặt trong ba bước

1. **Cài ShellX trên máy tính** (macOS 14+ hoặc Windows 10 bản 1809+) và đăng ký tài khoản.
2. **Cài app trên điện thoại** (iOS 15+ hoặc Android 8.0+) và đăng nhập cùng tài khoản.
3. **Ghép nối.** Mở menu khay trên máy tính, chọn ghép nối điện thoại, và quét mã QR.

Từ đó, mọi phiên terminal trong ShellX trên máy tính đều mở được từ điện thoại, ở bất kỳ đâu có Internet.

## Dùng hằng ngày

- **Nhiều phiên cùng lúc.** Chuyển qua lại giữa các tab và pane trên điện thoại như đang ngồi trước máy.
- **Mạng di động chập chờn cũng không sao.** Máy tính giữ 256 KiB output gần nhất của mỗi phiên; khi điện thoại kết nối lại, phần đã diễn ra được phát lại.
- **Thông báo.** Nhận thông báo đẩy khi lệnh dài chạy xong, hoặc khi chương trình hay script cần bạn (`shellx notify "xong"`, hoặc chuỗi OSC 9 / 777 / 99).
- **Cả server nữa.** Workspace SSH và phiên `tmux` bạn mở trong app ShellX trên máy tính hiện trên điện thoại như mọi phiên khác.

## Khi nào VPN vẫn là công cụ đúng

ShellX dành cho **terminal**. Nếu bạn cần thư mục chia sẻ, remote desktop, cơ sở dữ liệu hay mọi cổng của một máy, VPN cho bạn cả mạng. Hai thứ dùng chung rất hợp: giữ VPN để vào mạng, dùng ShellX để theo dõi phiên terminal từ điện thoại kèm thông báo. Xem [ShellX so với Tailscale](/guides/shellx-vs-tailscale/).

## Câu hỏi thường gặp

**Máy tính có phải luôn bật không?** Có. Các phiên chạy trên máy tính, nên máy phải bật và có mạng. Máy ngủ thì điện thoại kết nối lại khi máy thức dậy.

**ShellX có lưu gì trên máy chủ không?** Chỉ tài khoản, thông tin thiết bị và ghép nối, và mã thông báo đẩy của điện thoại đã cho phép thông báo. Nội dung terminal được mã hóa đầu cuối nên không đọc hay lưu được. Chi tiết trong [Chính sách quyền riêng tư](/privacy/).

**Có mất phí không?** ShellX hiện miễn phí.
