# Giọng hype đã tạo bằng Gemini (Tạo nhạc / Lyria) — để tạo lại đúng giọng

Cách tạo: gemini.google.com → + → Tạo nhạc (có khi nằm trong "Các công cụ khác") → Thời lượng **Ngắn** →
dán prompt → gửi. **Mỗi gói một cuộc trò chuyện mới** (cùng chat lần 2 hay lỗi). Hết lượt thì Gemini trả lời bằng chữ.
Chế độ phải là "Tự động" (chế độ "Phân tích sâu hơn" không tạo nhạc).

Bản gốc từng gói: `goiN.mp3` (128 kbps). `segs.json` = mốc gợi ý cắt (giây).
Cắt clip: tool "Cắt clip hype" (artifact) -> Copy danh sách -> Claude cắt từ bản gốc, không tách giọng
(tách giọng bằng UVR làm giọng bị "bẻ").

Đuôi chung của mọi prompt (giữ nguyên — đây là thứ làm nhạc nền nhỏ, giọng rõ):
> Giọng là chính, rõ chữ, gần như a cappella. Nhạc nền tối giản: chỉ một tiếng trống hoặc vỗ tay ngay sau mỗi câu,
> không giai điệu, không synth, không bass liên tục. Giữa các câu im lặng một nhịp.
Từ gói 14: thêm "Nói đúng từng câu sau, không thêm bớt chữ:" trước danh sách câu.

| Gói | Đánh giá của Hùng | Mô tả giọng (dán y nguyên đầu prompt) |
|---|---|---|
| 1 | clip 3,4,5 dùng được; nhạc lấn giọng | (prompt cũ EDM 140 BPM — KHÔNG dùng lại) |
| 2 | ok, bỏ "Ngũ sát" (khó hiểu) | Bản hype cầu lông vui nhộn: giọng bình luận viên bóng đá hài hước, nói nhanh, cười khoái chí, dí dỏm, mỗi câu lên giọng cao hơn câu trước. |
| 10 | chất âm tốt nhưng lời "chợ búa" | Bản hype cầu lông vui: giọng anh bán hàng chợ vui tính đang rao hàng, nói tự nhiên như người thật, dí dỏm, không chỉnh giọng, không autotune. |
| **11** | **HAY** | Bản hype cầu lông vui vẻ trẻ trung: giọng MC trẻ Gen Z, năng lượng, cười tươi, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |
| **12** | **HAY NHẤT** | Bản hype cầu lông vui nhộn: giọng nữ trẻ lém lỉnh, trêu đùa dễ thương, cười khúc khích, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |
| **13** | **HAY NHẤT** | Bản hype cầu lông khí thế: giọng nam trẻ phấn khích, sung sức, vui vẻ, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |

| 14 | (chờ nghe) Mở màn | Bản hype mở màn trận cầu lông: giọng MC sự kiện trẻ, vui vẻ, hào hứng, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |
| 15 | (chờ nghe) Kết trận | Bản kết trận cầu lông vui: giọng MC trẻ vui tính, hào hứng, cuối câu cười nhẹ, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |
| 16 | (chờ nghe) Khen — dùng lại giọng gói 11 | (y như gói 11) |
| 17 | (chờ nghe) Cà khịa — dùng lại giọng gói 12 | (y như gói 12) |
| 18 | (chờ nghe) Deuce — giọng gói 13 + "hồi hộp kịch tính nhưng vui" | Bản hype cầu lông khí thế: giọng nam trẻ phấn khích, sung sức, hồi hộp kịch tính nhưng vui, nói tự nhiên như người thật, không chỉnh giọng, không autotune. |

Lời từng gói: xem `../lyria_packs.md`. Quy tắc lời: chỉ dựa vào thứ app biết từ điểm số
(đầu trận, điểm đầu, chuỗi, cắt chuỗi, lội ngược dòng, deuce, hết trận) — không tả loại cú đánh.

## Clip đã đưa vào app (26/11/2026)

72 clip cắt từ bản gốc (không tách giọng), tên `g<gói>_<slug>` trong `audio_src/hype/`, nhóm phát nằm ở
`assets/config/sound_library.json`. Hùng chấm gói **12, 13 hay nhất** — cần thêm câu thì gen lại đúng prompt giọng của hai gói này.
Hai câu tả cú đánh (`g12_cau_ra_ngoai_san…`, `g12_dap_hut…`) chỉ nằm trong `manual_trigger`: trọng tài bấm giữ trên band khi gặp pha đó.
