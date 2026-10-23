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
- **R5. Spinner và nhãn "chạy" khi có hiệu ứng** (builder check, câu 1). Trong lúc tên phiên chạy hiệu ứng, dòng sidebar ẩn spinner và ẩn nhãn "chạy". Hiệu ứng thay cho hai dấu hiệu đó, đúng như bản phác C người dùng đã chọn. Các nhãn khác giữ nguyên. Hiệu ứng tên, ở sidebar lẫn thanh tab, đi theo cài đặt sẵn có "Show Loading Spinner" (`sidebar.showAgentActivity`). Nếu sai: người dùng muốn thấy cả nhãn "chạy" thì bật lại nhãn, sửa nhỏ.
- **R6. Bề mặt sáng** (builder check, câu 2). Thanh tab sáng (theme terminal sáng) và sidebar sáng giữ cách tô hiện nay, không có hiệu ứng tên. Nếu sai: người dùng theme sáng không có hiệu ứng; muốn có thì phải làm thêm một bảng màu cho nền sáng.
- **R7. Độ chính xác của dấu workflow** (builder check, câu 3). `prompt-submit` giữ dấu workflow. `stop` chỉ giữ dấu khi còn một `background_tasks` đang `running`; không tính `session_crons`. Không bám theo id của từng tác vụ nền. Nếu sai: cầu vồng có thể còn sáng khi workflow đã xong nhưng còn một tác vụ nền khác.
- **R8. Ngoài Bonsplit** (builder check, câu 4). Canvas nằm ngoài phạm vi bản này. Đầu nhóm workspace đại diện cho workspace neo đang chọn thì được tô nền chọn, nhưng không có hiệu ứng tên. Nếu sai: ở chế độ Canvas vẫn chưa có tab xanh; đó là một việc riêng.
- **R9. Màu nhấn tự chọn** (builder check, câu 5). Mức tương phản 4.5:1 chỉ bảo đảm và chỉ test với màu nhấn mặc định. Màu nhấn khác thì không chỉnh riêng. Nếu sai: với màu nhấn vàng hoặc trắng, vệt vàng trên dòng đang chọn đạt khoảng 3.5-3.9:1.
