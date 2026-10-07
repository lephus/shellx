---
layout: ../layouts/Legal.astro
lang: vi
page: privacy
title: Chính sách quyền riêng tư
description: "ShellX thu thập dữ liệu gì, dùng để làm gì, lưu bao lâu, mã hóa đầu cuối bảo vệ nội dung terminal ra sao, và cách xóa tài khoản của bạn."
updated: "2026-10-07"
---

ShellX ("chúng tôi") cung cấp agent cho máy tính (macOS, Windows), ứng dụng di động (iOS, Android), máy chủ chuyển tiếp (relay) tại `relay.shellx.pro` và trang web `shellx.pro` (gọi chung là "Dịch vụ"). Chính sách này mô tả dữ liệu nào được thu thập, dùng để làm gì, lưu bao lâu và bạn có những quyền gì.

## Tóm tắt

- Nội dung terminal (lệnh bạn gõ và kết quả hiển thị) được **mã hóa đầu cuối** giữa điện thoại và máy tính của bạn. Máy chủ chuyển tiếp chỉ chuyển dữ liệu đã mã hóa và **không thể đọc** nội dung đó, ngoại trừ nội dung thông báo đẩy (mục 3).
- Chúng tôi chỉ lưu những gì cần để vận hành tài khoản: email, mật khẩu ở dạng băm, thông tin thiết bị và bản ghi ghép nối.
- Thông báo đẩy (push notification): trong lúc cài đặt "Thông báo khi lệnh chạy lâu xong" trên máy tính đang bật (mặc định) hoặc khi một chương trình gửi thông báo, agent gửi nội dung thông báo qua máy chủ của chúng tôi, Google Firebase Cloud Messaging và Apple Push Notification service, ở dạng không mã hóa đầu cuối, tới điện thoại đã ghép nối và cho phép thông báo (mục 3).
- Nhập lệnh bằng giọng nói: khi bạn chạm nút mic, lời nói được chuyển thành chữ bằng nhận dạng giọng nói của Apple (iPhone) hoặc Google (Android, khi điện thoại không tự nhận dạng được), có thể xử lý âm thanh trên máy chủ của họ. ShellX không lưu và không nhận âm thanh (mục 2).
- Không quảng cáo, không công cụ phân tích hay theo dõi, không bán dữ liệu.

## 1. Dữ liệu lưu trên máy chủ của chúng tôi

**Tài khoản**

- **Email** — dùng làm tên đăng nhập, lưu ở dạng chữ thường. Chúng tôi không gửi email xác thực hay email quảng cáo.
- **Mật khẩu** — không bao giờ được lưu ở dạng gốc. Máy chủ chỉ lưu kết quả băm bằng thuật toán **argon2id**; từ kết quả băm không thể khôi phục mật khẩu.
- Thời điểm tạo tài khoản và thời điểm đổi mật khẩu gần nhất.

**Thiết bị** — mỗi khi bạn đăng ký hoặc đăng nhập trên một thiết bị, chúng tôi lưu:

- **tên thiết bị**: tên máy (hostname) với máy tính, tên model với điện thoại;
- **loại thiết bị** (agent trên máy tính hoặc ứng dụng di động) và **nền tảng** (macOS, Windows, iOS hoặc Android);
- **khóa công khai** của thiết bị (X25519). Khóa bí mật tương ứng không bao giờ rời khỏi thiết bị;
- thời điểm thêm thiết bị và **thời điểm online gần nhất**, dùng để hiển thị "Lần cuối online" trong ứng dụng.

**Mã truy cập (token)** — mỗi thiết bị đăng nhập nhận một mã truy cập ngẫu nhiên. Máy chủ chỉ lưu giá trị băm SHA-256 của mã, thời điểm tạo và thời điểm dùng gần nhất.

**Mã thông báo đẩy** — nếu bạn cho phép thông báo trên ứng dụng di động, máy chủ lưu mã thông báo đẩy (FCM token) của điện thoại đó, nền tảng (iOS hoặc Android) và thời điểm cập nhật (mục 3).

**Bản ghi ghép nối** — khi bạn ghép nối một điện thoại với một máy tính bằng mã QR, máy chủ lưu cặp (máy tính, điện thoại) và thời điểm ghép nối, chỉ để hiển thị trong ứng dụng. Việc tin cậy một điện thoại được quyết định và lưu trên chính máy tính của bạn, không phải trên máy chủ.

**Địa chỉ IP** — địa chỉ IP của bạn được dùng tạm thời để giới hạn số lần đăng nhập và đăng ký trong mỗi khoảng 60 giây (chống dò mật khẩu và lạm dụng). Chúng tôi không lưu địa chỉ IP vào cơ sở dữ liệu tài khoản. Các yêu cầu `https://` tới Dịch vụ không bị ghi nhật ký truy cập; riêng nếu bạn truy cập bằng liên kết `http://` không bảo mật, máy chủ web dùng chung có thể ghi yêu cầu đó (kèm địa chỉ IP) vào nhật ký kỹ thuật trước khi chuyển hướng bạn sang `https://`.

**Nhật ký vận hành** — máy chủ ghi nhật ký kỹ thuật tối thiểu để vận hành và xử lý sự cố: thời điểm, mã thiết bị, mã lỗi và kích thước gói dữ liệu. Nhật ký **không bao giờ** chứa nội dung terminal, mật khẩu hay mã truy cập.

## 2. Nội dung terminal được mã hóa đầu cuối

Điện thoại và máy tính thiết lập một kênh mã hóa bằng giao thức Noise, với khóa mà chỉ hai thiết bị đó nắm giữ. Máy chủ chuyển tiếp chỉ thấy các gói dữ liệu đã mã hóa, mã thiết bị gửi và nhận, kích thước và thời điểm của gói; nó không đọc được lệnh bạn gõ, kết quả hiển thị, và cũng không biết bạn đang mở bao nhiêu phiên terminal — ngoại trừ nội dung thông báo đẩy (mục 3). Chúng tôi không lưu nội dung terminal.

Để bù phần output phát sinh khi điện thoại tạm mất kết nối, agent giữ tối đa 256 KiB output gần nhất của mỗi phiên **trong bộ nhớ của máy tính của bạn**. Dữ liệu này không được gửi cho chúng tôi và mất đi khi phiên kết thúc hoặc agent thoát. Riêng việc ứng dụng máy tính lưu nội dung terminal gần nhất trên máy để khôi phục sau khi mở lại được mô tả ở mục 4.

### Nhập lệnh bằng giọng nói

- Ứng dụng di động chỉ dùng micro khi bạn chạm nút mic trên màn terminal; không ghi âm nền.
- Lời nói được chuyển thành chữ bằng tính năng nhận dạng giọng nói của điện thoại, **trước khi** mã hóa đầu cuối. Trên iPhone, ứng dụng dùng nhận dạng giọng nói của Apple: Apple có thể xử lý âm thanh ngay trên điện thoại hoặc trên máy chủ của Apple. Trên Android, lời nói được nhận dạng ngay trên điện thoại khi máy làm được; nếu không, âm thanh được gửi tới dịch vụ nhận dạng giọng nói của Google. Apple và Google xử lý theo chính sách riêng của họ.
- ShellX không lưu âm thanh và không gửi âm thanh tới máy chủ của ShellX. Chữ bạn gửi đi vào terminal như phím gõ, được mã hóa đầu cuối như trên; máy chủ chuyển tiếp không đọc được.
- Lựa chọn ngôn ngữ nhận dạng (tiếng Việt/tiếng Anh) được lưu trên điện thoại.

## 3. Thông báo đẩy

Agent trên máy tính có thể báo cho điện thoại đã ghép nối khi một lệnh chạy lâu kết thúc, hoặc khi một chương trình gửi thông báo — kể cả khi ứng dụng di động đã đóng.

- **Agent gửi gì, khi nào.** Trong lúc cài đặt "Thông báo khi lệnh chạy lâu xong" trên máy tính đang bật (mặc định: 30 giây) — và bất cứ khi nào một chương trình trong terminal phát chuỗi thông báo (ví dụ `shellx notify`, OSC 9, OSC 777) — agent gửi **nội dung thông báo** tới máy chủ chuyển tiếp ShellX: tên máy tính, tên phiên hoặc cửa sổ terminal, dòng lệnh, mã thoát và thời gian chạy, hoặc chữ do chương trình gửi. Nội dung này **không được mã hóa đầu cuối**.
- **Máy chủ làm gì với nó.** Máy chủ chỉ chuyển tiếp nội dung đó qua **Google Firebase Cloud Messaging** và, với iPhone, **Apple Push Notification service**, và chỉ tới những điện thoại đã ghép nối với chính máy tính đó và đã cho phép thông báo. Máy chủ không lưu nội dung này và không ghi nó vào nhật ký; Google và Apple xử lý nó theo chính sách riêng của họ.
- **Khi không điện thoại nào nhận được** (chưa điện thoại nào cho phép thông báo, hoặc đều đã đăng xuất), agent ngừng gửi tối đa 15 phút — sớm hơn nếu trong lúc đó có điện thoại kết nối tới máy tính.
- **Mã thông báo đẩy.** Ứng dụng di động nhận một mã thông báo đẩy (FCM token) từ Google Firebase Cloud Messaging và gửi lên máy chủ khi bạn cho phép thông báo. Máy chủ lưu mã này tới khi bạn đăng xuất trên điện thoại đó, xóa tài khoản, tắt thông báo của ShellX trong cài đặt điện thoại (ở lần mở ứng dụng tiếp theo), hoặc Firebase báo mã không còn hiệu lực.
- Đây là ngoại lệ duy nhất đối với mục 2: chỉ nội dung thông báo, không phải phần còn lại của terminal.
- **Cách tắt:** chọn "Tắt" ở "Thông báo khi lệnh chạy lâu xong" trong menu ShellX trên máy tính (thông báo khi lệnh kết thúc), hoặc tắt thông báo của ShellX trong cài đặt điện thoại, hoặc đăng xuất trên điện thoại.

## 4. Dữ liệu chỉ nằm trên thiết bị của bạn

Khóa bí mật của thiết bị, mã truy cập, danh sách điện thoại được tin cậy (trên máy tính), danh sách máy đã ghép nối (trên điện thoại) và các cài đặt được lưu trong kho bảo mật của hệ điều hành (Keychain trên macOS/iOS, Windows Credential Manager cùng tệp mã hóa AES trên Windows, Android Keystore) hoặc vùng cài đặt của ứng dụng. Những dữ liệu này không được gửi lên máy chủ, trừ mã truy cập được gửi kèm mỗi yêu cầu để xác thực.

- **Camera:** ứng dụng di động chỉ dùng camera để quét mã QR ghép nối. Hình ảnh không được lưu hay gửi đi.
- **Sinh trắc học:** khóa ứng dụng bằng Face ID, vân tay hoặc mã máy do hệ điều hành xử lý. Ứng dụng chỉ nhận kết quả thành công hoặc thất bại, không bao giờ nhận dữ liệu sinh trắc học.
- **Full Disk Access (macOS):** quyền này không bắt buộc và chỉ để các lệnh bạn chạy trong terminal truy cập được thư mục của bạn. Agent không tự đọc hay tải lên tệp nào của bạn.
- **Khôi phục phiên (máy tính):** để mở lại đúng chỗ làm việc sau khi bạn thoát ứng dụng hoặc khởi động lại máy, ShellX lưu bố cục tab/pane, thư mục làm việc của từng terminal và — nếu "Lưu nội dung terminal khi thoát" đang bật (mặc định bật) — tối đa 2.000 dòng nội dung cuối của mỗi terminal (không quá 256 KiB mỗi terminal). Các tệp này chỉ nằm trên máy tính của bạn, trong thư mục dữ liệu của ứng dụng thuộc tài khoản của bạn: trên macOS là `~/Library/Application Support/pro.shellx.desktop/restore`, chỉ tài khoản của bạn đọc được và không đưa vào bản sao lưu Time Machine; trên Windows là `%LOCALAPPDATA%\ShellX\restore`, được xóa khi gỡ cài đặt. Nội dung này có thể chứa bất cứ thứ gì đã hiện trên terminal; nó không bao giờ được gửi lên máy chủ, tới điện thoại hay đồng bộ đi đâu. Bạn có thể tắt việc lưu nội dung hoặc xóa nội dung đã lưu bất cứ lúc nào trong menu ShellX trên máy tính → Terminal.
- **SSH (máy tính):** khi bạn kết nối tới máy chủ, ShellX chạy lệnh `ssh` của máy bạn với khoá và cấu hình của bạn; ShellX không hỏi, không lưu mật khẩu. Nếu bật hook, ShellX ghi vài tệp script nhỏ vào `~/.cache/shellx/` trên máy chủ để biết thư mục, nhánh git và cổng đang mở — không gửi gì khác đi đâu. Danh sách máy gần đây chỉ lưu trên máy tính này. Tên máy chủ và thư mục bạn đang ở trên đó có thể hiện trong danh sách phiên trên điện thoại đã ghép nối của bạn, như một thư mục cục bộ.

## 5. Những gì chúng tôi không làm

- Không dùng công cụ phân tích, quảng cáo, pixel theo dõi hay SDK bên thứ ba để theo dõi hành vi. Ứng dụng di động chỉ dùng Firebase Cloud Messaging để nhận thông báo đẩy, không dùng các dịch vụ phân tích của Firebase.
- Không gửi thông báo quảng cáo: thông báo đẩy chỉ đến từ máy tính của chính bạn.
- Không bán, cho thuê hay chia sẻ dữ liệu cá nhân cho mục đích quảng cáo.
- Trang web `shellx.pro` không dùng cookie và không nhúng script của bên thứ ba.

## 6. Mục đích sử dụng dữ liệu

Chúng tôi chỉ dùng dữ liệu nêu ở mục 1 để: tạo và xác thực tài khoản; hiển thị danh sách thiết bị, trạng thái online và ghép nối; chuyển tiếp dữ liệu đã mã hóa giữa các thiết bị trong cùng một tài khoản; gửi thông báo đẩy bạn đã bật tới điện thoại của bạn; và bảo vệ Dịch vụ khỏi lạm dụng.

## 7. Bên cung cấp hạ tầng và nơi xử lý dữ liệu

Dịch vụ chạy trên máy chủ riêng do ShellX thuê tại **Việt Nam**: máy chủ chuyển tiếp, cơ sở dữ liệu tài khoản cùng các bản sao lưu, trang web và bản cài đặt. Dữ liệu được lưu và xử lý tại **Việt Nam**. Chúng tôi không dùng mạng phân phối nội dung (CDN) hay dịch vụ phân tích của bên thứ ba.

Khi bạn tải ứng dụng từ App Store hoặc Google Play, Apple và Google xử lý dữ liệu theo chính sách riêng của họ. Khi bạn bật thông báo đẩy, nội dung thông báo và mã thông báo đẩy được chuyển cho Google (Firebase Cloud Messaging) và, với iPhone, Apple (Apple Push Notification service) để gửi tới điện thoại (mục 3); các dịch vụ này có thể xử lý dữ liệu ngoài Việt Nam. Khi bạn nhập lệnh bằng giọng nói, âm thanh được xử lý bởi nhận dạng giọng nói của Apple (iPhone) hoặc, khi điện thoại không tự nhận dạng được, của Google (Android); các dịch vụ này cũng có thể xử lý dữ liệu ngoài Việt Nam (mục 2).

Chúng tôi chỉ cung cấp dữ liệu cho cơ quan nhà nước khi pháp luật bắt buộc. Vì nội dung terminal được mã hóa đầu cuối, chúng tôi không có nội dung đó để cung cấp.

## 8. Thời gian lưu trữ

- **Tài khoản và thiết bị:** cho tới khi tài khoản bị xóa.
- **Mã truy cập:** bị xóa khi bạn đăng xuất trên thiết bị đó hoặc khi bị thu hồi (đổi mật khẩu thu hồi mã của mọi thiết bị khác); mã hết hiệu lực sau 90 ngày không dùng.
- **Mã thông báo đẩy:** bị xóa khi bạn đăng xuất trên điện thoại đó, khi xóa tài khoản, khi bạn tắt thông báo của ShellX trong cài đặt điện thoại (ở lần mở ứng dụng tiếp theo), hoặc khi Firebase báo mã không còn hiệu lực.
- **Bản ghi ghép nối:** bị xóa khi bạn thu hồi hoặc bỏ ghép nối, hoặc khi bạn đăng xuất khỏi agent trên máy tính đó.
- **Nhật ký vận hành:** không quá 30 ngày.
- **Bản sao lưu cơ sở dữ liệu:** mỗi ngày một bản, giữ 14 bản gần nhất.

<h2 id="delete-account">9. Xóa tài khoản</h2>

Bạn có thể tự xóa tài khoản ngay trong ứng dụng di động: mở **Cài đặt → Xóa tài khoản** và nhập lại mật khẩu để xác nhận. Việc xóa có hiệu lực ngay và không thể hoàn tác: máy chủ xóa vĩnh viễn tài khoản cùng toàn bộ thiết bị, mã truy cập, mã thông báo đẩy và bản ghi ghép nối; mọi thiết bị đang kết nối bị đăng xuất. Agent trên máy tính không phân biệt được việc này với đổi mật khẩu, nên luôn xóa mã truy cập của nó, đóng mọi phiên terminal rồi hiện lại màn hình đăng nhập — nó **giữ nguyên** khóa thiết bị và danh sách điện thoại được tin cậy. Danh sách đó chỉ bị xóa khi bạn đăng nhập lại bằng một tài khoản khác, khi bạn đăng xuất khỏi agent từ tray, hoặc khi bạn gỡ cài đặt agent.

Nếu bạn không còn dùng được ứng dụng di động, hãy gửi email tới [phule9225@gmail.com](mailto:phule9225@gmail.com) **từ chính địa chỉ email của tài khoản**, tiêu đề "Xóa tài khoản ShellX". Chúng tôi có thể hỏi thêm thông tin để xác minh bạn là chủ tài khoản, xóa tài khoản trong vòng 30 ngày kể từ khi xác minh, rồi gửi email xác nhận.

Nhật ký vận hành (không chứa nội dung terminal, mật khẩu hay mã truy cập) tự hết hạn trong vòng 30 ngày. Dữ liệu đã xóa cũng có thể còn trong các bản sao lưu hằng ngày của cơ sở dữ liệu tối đa 14 ngày, rồi bị xóa cùng bản sao lưu đó.

Dữ liệu nằm trên thiết bị của bạn (mục 4): trên Windows, gỡ cài đặt agent sẽ xóa dữ liệu này; trên Android, gỡ cài đặt ứng dụng cũng xóa dữ liệu. Trên macOS và iOS, các mục trong Keychain có thể vẫn còn sau khi bạn gỡ ứng dụng — trên iOS, ShellX tự xóa các mục đó ở lần cài đặt tiếp theo; trên macOS, chúng có thể được dùng lại nếu bạn cài lại ShellX — và bạn có thể xóa sớm hơn bằng công cụ quản lý Keychain của hệ điều hành.

## 10. Quyền của bạn

Bạn có quyền yêu cầu truy cập, chỉnh sửa hoặc xóa dữ liệu cá nhân của mình, rút lại sự đồng ý và phản đối việc xử lý dữ liệu, theo pháp luật về bảo vệ dữ liệu cá nhân nơi bạn sinh sống. Gửi yêu cầu tới [phule9225@gmail.com](mailto:phule9225@gmail.com); chúng tôi phản hồi trong vòng 30 ngày.

Ngay trong ứng dụng, bạn có thể xem danh sách thiết bị, thu hồi hoặc bỏ ghép nối, đăng xuất, đổi mật khẩu (từ máy tính đang đăng nhập) và xóa tài khoản (từ ứng dụng di động).

## 11. Bảo mật

Mọi kết nối tới máy chủ dùng TLS; nội dung terminal được mã hóa đầu cuối (trừ nội dung thông báo đẩy, mục 3); mật khẩu được băm bằng argon2id; mã truy cập chỉ được lưu ở dạng băm SHA-256; khóa bí mật nằm trong kho bảo mật của hệ điều hành; ứng dụng di động mặc định khóa bằng sinh trắc học. Không hệ thống nào an toàn tuyệt đối; nếu xảy ra sự cố ảnh hưởng tới dữ liệu của bạn, chúng tôi sẽ thông báo theo quy định của pháp luật.

## 12. Trẻ em

Dịch vụ không dành cho người dưới 16 tuổi và chúng tôi không cố ý thu thập dữ liệu của họ. Nếu bạn biết một người dưới 16 tuổi đã tạo tài khoản, hãy liên hệ để chúng tôi xóa tài khoản đó.

## 13. Thay đổi chính sách

Khi chính sách thay đổi, chúng tôi cập nhật trang này và ngày "Cập nhật lần cuối" ở đầu trang. Với thay đổi quan trọng, chúng tôi đăng thông báo trên `shellx.pro` trước khi thay đổi có hiệu lực.

## 14. Liên hệ

Mọi câu hỏi về quyền riêng tư: [phule9225@gmail.com](mailto:phule9225@gmail.com).
