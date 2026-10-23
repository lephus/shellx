# Sổ quyết định: tab đang chọn và hiệu ứng agent (desktop Mac)

Spec: `docs/superpowers/specs/2026-10-23-shellx-tab-selection-agent-effects-design.md`.

## Chỉ thị của người dùng

- 23/10/2026: chọn B (nền xanh dịu) cho tab đang chọn, C (tên phiên đổi màu) cho hiệu ứng, làm desktop Mac trước. Đồng ý các lựa chọn của người viết spec khi nghe tóm tắt.
- 23/10/2026, chế độ vắng mặt: "bạn tự xử lý xong thì code luôn nhé, Làm xong push lên develop rồi merge vào main, Sau đó build release version mới luôn". Từ đây người viết tự ra quyết định và ghi lại ở mục dưới.

## Quyết định khi người dùng vắng mặt

- **R1. Fork Bonsplit.** `vendor/bonsplit` là submodule trỏ tới `manaflow-ai/bonsplit` (MIT, công khai), nên repo này không push lên đó được. Phần tô tab và chữ tab nằm trong Bonsplit, và skill `cmux-ghostty` yêu cầu push commit của submodule lên một fork trước khi đổi con trỏ. Quyết định: tạo fork công khai `lephus/bonsplit`, đổi URL submodule trong `.gitmodules` sang fork. Mọi thay đổi trong Bonsplit chỉ bật khi app chọn qua `Appearance`; mặc định giữ nguyên hành vi upstream.
- **R2. Số phiên bản 1.3.0, build 113.** Đây là bản thêm tính năng giao diện, nên tăng số phụ. Windows tăng cùng số để hai app giữ một số phiên bản; nội dung app Windows không đổi.
- **R3. "Build release" nghĩa là dựng bản phát hành, chưa phát hành.** Dựng, ký, notarize DMG; build bản Windows trên CI; tạo GitHub release ở dạng nháp với đủ file. Chưa bấm publish, vì publish sẽ đẩy file lên VPS production và đẩy bản cập nhật tự động tới mọi người dùng. Người dùng đã dặn hỏi trước mỗi lần deploy. Lệnh publish để sẵn trong báo cáo cuối.
- **R4. Tên dòng phiên không đổi độ đậm.** Hiện tên mọi dòng đều đậm (semibold). Dòng đang chọn khác các dòng khác ở nền xanh và màu chữ `#f1f5ff`; các dòng khác giữ nguyên.
