---
layout: ../../layouts/Guide.astro
lang: vi
slug: claude-code-on-phone
order: 1
title: "Cách dùng Claude Code và Codex từ điện thoại"
metaTitle: "Claude Code và Codex trên điện thoại — Hướng dẫn ShellX"
description: "Chạy Claude Code, Codex hay AI coding agent dạng CLI trên máy tính và theo dõi từ điện thoại: trả lời câu hỏi, duyệt thay đổi, nhận thông báo khi agent cần bạn."
published: "2026-10-07"
updated: "2026-10-07"
keywords: ["Claude Code trên điện thoại", "Claude Code mobile", "Codex CLI từ điện thoại", "điều khiển AI agent từ xa", "Claude Code iPhone", "Claude Code Android"]
---

Các AI coding agent như **Claude Code** và **Codex** làm việc tốt nhất trong terminal trên chính máy tính của bạn: chúng thấy repo, chạy test và dùng công cụ của bạn. Vấn đề là chúng thường chạy vài phút rồi dừng lại để hỏi hoặc chờ bạn duyệt. Nếu bạn đã rời bàn làm việc, agent nằm chờ tới khi bạn quay lại.

ShellX giải quyết đúng chỗ đó. Agent vẫn chạy trên máy Mac hoặc PC, còn bạn mở **đúng phiên terminal đó** trên điện thoại để xem nó đang làm gì, trả lời, và cho nó chạy tiếp.

## Cần chuẩn bị

- ShellX trên máy tính (macOS 12 trở lên, Windows 10 bản 1809 trở lên).
- App ShellX trên điện thoại (iOS 15 trở lên, Android 8.0 trở lên), đăng nhập cùng tài khoản và đã ghép nối bằng mã QR.
- Claude Code, Codex hoặc agent dòng lệnh khác đã cài trên máy tính như bình thường.

Cách cài và đăng nhập agent không thay đổi gì. ShellX không đi qua lưu lượng API của agent; nó chỉ truyền terminal, được mã hóa đầu cuối giữa hai thiết bị của bạn.

## Từng bước

1. **Chạy agent trong terminal ShellX.** Mở một tab trong app ShellX trên máy tính, `cd` vào dự án và chạy `claude` (hoặc `codex`). Giao việc cho nó như mọi khi.
2. **Mở phiên trên điện thoại.** Trong app ShellX trên điện thoại, chọn máy tính rồi chọn phiên. Bạn thấy đúng màn hình đó, cập nhật trực tiếp, và gõ được vào. Cuộn lên được, nên bạn đọc lại được những gì đã diễn ra lúc vắng mặt.
3. **Trả lời và duyệt ở bất kỳ đâu.** Khi agent hỏi "Do you want to make this edit?" hay cần làm rõ yêu cầu, gõ câu trả lời trên điện thoại. Agent chạy tiếp ngay trên máy tính.
4. **Nhận thông báo thay vì phải canh.** ShellX biến thông báo terminal thành thông báo đẩy trên điện thoại. Mọi chương trình gửi thông báo dạng **OSC 9**, **OSC 777** hoặc **OSC 99** đều được hỗ trợ. Claude Code cho chọn kênh thông báo terminal trong phần cài đặt (`/config`); hãy chọn kênh dùng các chuỗi này. Từ bất kỳ script hay hook nào bạn cũng gửi được:

```sh
shellx notify "Claude Code đang chờ bạn"
```

Trong một pane ShellX, thông báo hiện trên tab và được đẩy về điện thoại đã ghép nối.

## Cho agent dùng ShellX luôn

ShellX có sẵn công cụ dòng lệnh `shellx` để agent gọi: mở pane bên cạnh chạy dev server, chờ một dòng trong log, đọc output của pane, gửi thông báo. Cài skill có sẵn để Claude Code biết cách dùng:

```sh
shellx skills install --claude   # hoặc --codex
```

Sau đó agent có thể, chẳng hạn, chạy `npm run dev` ở pane bên cạnh bằng `shellx split --right --cmd "npm run dev"` rồi chờ bằng `shellx wait`, mà không cướp focus của bạn.

## Sao không SSH thẳng vào máy tính?

Bạn có thể bật SSH trên Mac, mở cổng hoặc cài VPN, rồi gắn vào phiên `tmux` từ một app SSH trên điện thoại. Cách đó chạy được, nhưng nhiều khâu, và bạn nhận một shell **mới**, không phải cửa sổ agent đang chạy, trừ khi đã chuẩn bị tmux từ trước. ShellX không cần mở cổng hay VPN, hiện đúng phiên đang chạy, và có thêm thông báo đẩy. Xem [ShellX so với Termius](/guides/shellx-vs-termius/) và [ShellX so với Tailscale](/guides/shellx-vs-tailscale/) để so sánh.

## Về bảo mật

- Nội dung terminal được mã hóa đầu cuối bằng giao thức Noise. Máy chủ chuyển tiếp ở giữa chỉ chuyển gói đã mã hóa, không đọc được code, câu lệnh hay output.
- Ghép nối bằng mã QR hiện trên máy tính; khóa bí mật không bao giờ rời thiết bị.
- Nếu điện thoại mất mạng, máy tính giữ 256 KiB output gần nhất của mỗi phiên và phát lại khi điện thoại kết nối lại.

## Câu hỏi thường gặp

**Agent có chạy trên điện thoại không?** Không. Nó chạy trên máy tính, với file, thông tin đăng nhập và công cụ của bạn. Điện thoại chỉ là màn hình và bàn phím.

**Có dùng được với agent khác không?** Được. Mọi thứ chạy trong terminal đều dùng như nhau: Codex, Aider, Gemini CLI, hay một lệnh `npm test` dài.

**Có mất phí không?** ShellX hiện miễn phí.
