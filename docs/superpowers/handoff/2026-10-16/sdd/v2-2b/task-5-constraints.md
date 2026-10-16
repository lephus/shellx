# Task 5 constraints (verbatim spec excerpts)

Spec header (line 10):
- **V2-2b được phép sửa:** như V2-2 (giao thức chỉ thêm, `shellx_ai` remote, `shellx_agent`, `shellx_client`, daemon, app mobile, phần nối desktop), **thêm:** mô hình V2-1a ở đúng hai chỗ (B3 id duy nhất, B24 nguồn của tin), lớp hoàn tác của desktop (B19, tách khỏi widget), relay (B6, nhánh riêng).

Success criterion 12 (line 42):
12. **Nguồn tin.** Tin gửi từ điện thoại hiện "Bạn · từ điện thoại" trên máy tính (cả khi đang xếp hàng).

Decision B24 (line 98):
| # | Chủ đề | Quyết định | Giá nếu sai |
|---|---|---|---|
| B24 | "Bạn · từ điện thoại" | `enum PromptSource { computer, phone }` trên `UserItem` và `QueuedPrompt`, truyền qua `send(…, source)`, `enqueue`, `beginTurn`. Hub gửi `phone`. Desktop ghi **"Bạn · từ điện thoại"** / "You · from your phone" trên tin và trên hàng đang xếp hàng. Mục gương có `src: "phone"`; điện thoại ghi "từ điện thoại" dưới tin của chính nó. Phát lại bằng `session/load` không giữ được nguồn (agent không lưu): tin cũ ghi "Bạn". | — |

§4.2 mirror line (line 130) and §5 strings (lines 149-150, 173-174):
- Mục gương tin người dùng: thêm `img` (số ảnh), `src` (`phone`).

| Khoá | EN | VI |
|---|---|---|
| `aiYouFromPhone` (desktop) | You · from your phone | Bạn · từ điện thoại |
| `aiFromPhone` | from phone | từ điện thoại |

§8 test line for B24 (line 219):
- **B24:** nguồn đi suốt từ hub tới widget desktop; phát lại thì "Bạn".
