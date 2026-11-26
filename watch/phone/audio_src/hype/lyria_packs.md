# Gói hype tạo bằng Gemini (Tạo nhạc · Lyria · độ dài "Ngắn")

Mỗi gói = 1 bài ~30s chỉ gồm câu hô ngắn, nghỉ 1 nhịp giữa các câu -> cắt ra từng clip 1–3s,
chuẩn hoá bằng tools/normalize_voice.py, rồi thêm vào assets/config/sound_library.json.
Quy tắc câu: ≤ 6 chữ, nghe 1 lần là hiểu, hô được giữa trận. Không nêu tên người thật trong prompt.

Phần chung cuối mỗi prompt (bản 2 — bản 1 bị nhạc lấn giọng, nghe như tạp âm ở sân):
> Giọng là chính, rõ chữ, gần như a cappella (nói/hát theo kiểu giọng của gói, không cần hét). Nhạc nền tối giản: chỉ một tiếng trống kick hoặc tiếng vỗ tay ngay sau mỗi câu hô, không giai điệu, không synth, không bass liên tục. Giữa các câu im lặng một nhịp. Lặp lại 2 lần.
(Ở phần "nhạc" của từng gói bên dưới chỉ giữ không khí — vd. "kiểu trailer", "kiểu phonk" — không thêm nhạc cụ.)

Đã dùng: gói 1 bản đầu -> mo_man_lyria_1..3 (tách giọng bằng UVR-MDX-NET-Voc_FT, nhạc nền 15%).

Giọng: KHÔNG chỉ hô quát — mỗi gói một kiểu giọng vui/dí dỏm khác nhau để nghe không nhàm.

| # | Dịp (trigger) | Kiểu giọng | Câu |
|---|---|---|---|
| 1 | first_point_of_match | MC đám cưới miền Tây, vui vẻ, kéo dài chữ cuối | Vào sân! · Ai sợ thì đi về! · Mở hàng! · Cầu bay, lưới rung! |
| 2 | streak_2 → streak_5_plus | bình luận viên bóng đá hài, nói nhanh, cười khoái chí | (đã tạo, bỏ clip "Ngũ sát" — khó hiểu) Song sát! · Tam sát! · Tứ sát! · Thắng đời một không! |
| 3 | streak_high | rapper thong thả, chill, cà khịa nhẹ | Bá khí quá vậy! · Mãnh hổ hạ sơn! · Một mình một sân! · Ai cản nổi! · Ngồi xem đi! |
| 4 | shutdown | thì thầm bí ẩn rồi bật cười khúc khích | Nín! · Chấm dứt! · Hết phim! · Thân chưa mà giỡn! · Tắt điện! |
| 5 | comeback | hát ngân kiểu cải lương/vọng cổ hài, luyến láy | Lật kèo! · Quay xe! · Hồi sinh! · Chưa xong đâu! · Bay phấp phới! |
| 6 | crucial_moment | cô giáo mầm non dỗ dành, ngọt ngào mà hồi hộp | Deuce! · Bình tĩnh nha! · Tim đập chân run! · Một điểm thôi! |
| 7 | random_meme | nữ nhí nhảnh, cười khúc khích, lém lỉnh | Khét lẹt! · Hên lắm mới xui vậy! · Lưới ăn cầu! · Cầu này ai đỡ! · Khó chệu ghê! |
| 8 | streak_low (cú đẹp) | song ca nam nữ hát đối đáp vui, người hỏi người đáp | Đỉnh nóc kịch trần! · Khen đi, đọc stk! · Cầu biết bay! · Xỉu ngang! · Đẹp ghê chưa! |
| 9 | match_end | ông cụ kể chuyện chậm rãi, hóm hỉnh, cuối câu cười khà khà | Vô địch! · Thua thì trả tiền cầu! · Tám ba tám sáu! · Hẹn tái đấu! |

## Gói 10 — Khen nịnh tai (câu vần, dân dã, dễ nhớ) — thêm 24/11
Hùng thích kiểu "Hết sảy con bà bảy": câu có vần, khẩu ngữ, nghe là cười. Tránh từ Hán Việt khó hiểu (vd "Ngũ sát").

| Dịp | Kiểu giọng | Câu |
|---|---|---|
| streak_low / random_meme | anh bán hàng chợ vui tính, rao hàng, nói tự nhiên | Hết sảy con bà bảy! · Ngon lành cành đào! · Chất như nước cất! · Xịn xò con bò! · Tuyệt cú mèo! |
| streak_mid / streak_high | MC hội chợ vui vẻ, tự nhiên | Đỉnh của đỉnh! · Khỏi chê luôn! · Bén ngót! · Quá dữ quá dữ! · Số dzách! |

## Đợt 24/11 (chiều) — vui vẻ trẻ trung, KHÔNG chợ búa
Hùng: gói 10 nghe "chợ búa" quá (rổ giá cả rổ). Muốn kiểu Gen Z vui: đỉnh của nóc, nín, siêu phẩm… và nhiều câu hơn mỗi gói.

| Gói | Giọng | Câu |
|---|---|---|
| 11 Khen cú đẹp | MC trẻ Gen Z, năng lượng, cười tươi, tự nhiên | Siêu phẩm! · Đỉnh của nóc! · Đỉnh nóc kịch trần! · Khét lẹt! · Quá cháy! · Ảo thật đấy! · Cú này để đời! · Mãi đỉnh! · Không thể tin nổi! · Xuất sắc! |
| 12 Cà khịa / cắt chuỗi | nữ trẻ lém lỉnh, trêu đùa, cười khúc khích | Nín! · Nín luôn! · Toang rồi! · Ối dồi ôi! · Còn đúng cái nịt! · Gì căng vậy! · Tạch rồi! · Thôi xong! · Hết cứu! · Đi về đi! |
| 13 Khí thế / chuỗi thắng | nam trẻ phấn khích, sung sức, tự nhiên | Bá khí quá vậy! · Không ai cản nổi! · Một mình cân hết! · Quá dữ! · Chơi lớn! · Lên luôn! · Đỉnh cao phong độ! · Ai sợ thì đi về! · Thắng đời một không! |

## Đợt 25/11 — Claude tự viết lời, CHỈ dựa vào thứ app biết
App chỉ biết: ai ghi điểm, chuỗi điểm, cắt chuỗi, lội ngược dòng, deuce/điểm quyết định, đầu trận, hết trận.
KHÔNG biết loại cú đánh (bỏ nhỏ, đánh hụt, vào lưới, out) -> không viết câu mô tả cú đánh cụ thể.
Ngoại lệ Hùng duyệt: "Đập cầu như đập muỗi" (khen chung chung).

| Gói | Dịp | Giọng | Câu |
|---|---|---|---|
| 14 Mở màn | first_point_of_match | MC sự kiện vui, hào hứng | Khai trương hồng phát! · Mở hàng may mắn, cả trận phát tài! · Điểm đầu tiên, hên rồi đó nha! · Vào sân là phải có lửa! · Ai sợ thì đi về! · Trận này căng à nha! |
| 15 Kết trận | match_end | MC vui, cuối câu cười | Hết phim! Bên thắng cười, bên thua mời nước! · Vô địch thiên hạ… trong sân này thôi! · Thắng không kiêu, thua nhớ trả tiền cầu! · GG! Bắt tay rồi tái đấu! · Trận này lên báo được rồi! · Thắng rồi, tối nay ngủ ngon! |
| 16 Khen ghi điểm / chuỗi | streak_low..high | MC trẻ hào hứng | Siêu phẩm, đóng khung treo tường! · Đập cầu như đập muỗi! · Cú này phải tua chậm! · Ăn điểm như ăn kẹo! · Ghi điểm đều như vắt chanh! · Đỉnh nóc, kịch trần, bay phấp phới! |
| 17 Cà khịa / cắt chuỗi | shutdown, random_meme | nữ trẻ lém lỉnh | Toang rồi ông giáo ạ! · Còn đúng cái nịt! · Cay chưa? Cay thì uống nước! · Tạch như chưa từng được tạch! · Mất chuỗi rồi, buồn ghê! · Nín! Để người ta đánh! |
| 18 Deuce / điểm quyết định | crucial_moment | nam trầm kịch tính | Deuce! Tim ai đập nhanh hơn? · Một điểm bằng cả buổi tập! · Ai cay người đó thua! · Hồi hộp như chờ người yêu rep tin! |

## Gói cho bảng chọn tay trên band (viết 26/11/2026, CHƯA gen — chờ "approve")

| Gói | Nhóm | Giọng (prompt đầu) | Câu |
|---|---|---|---|
| 19 Ra ngoài | manual_ra_ngoai | như gói 12 (nữ trẻ lém lỉnh) | Cầu xin… ra ngoài! · Out như tình cũ! · Tưởng in, ai dè out! · Vạch kẻ cho vui hả? · Cầu đi du lịch rồi! · Mạnh quá, cầu bay qua tỉnh bên! · Ra ngoài hít thở không khí hả? · Out rồi, khỏi cãi nha! |
| 20 Hụt / lưới | manual_hut_luoi | như gói 12 | Quạt mát ghê! · Vụt cái vèo, cầu vẫn nằm đó! · Trúng lưới như trúng số! · Lưới ăn hết rồi! · Cầu mắc cạn rồi! · Vợt đẹp mà cầu không thương! · Đập vô lưới, lưới cũng tức! · Hụt rồi, về múa quạt đi! |
| 21 Đập cầu | manual_dap_cau | như gói 13 (nam trẻ phấn khích) | Đập như đập hộp! · Cú đập đi vào lòng đất! · Bùm! Sân rung luôn! · Đập xuyên sàn! · Smash như sấm! · Đập tơi bời khói lửa! · Đỡ bằng niềm tin à? · Một phát ăn ngay! |
| 22 Siêu phẩm + cà khịa | manual_sieu_pham, manual_ca_khia | 4 câu đầu giọng 13, 4 câu sau giọng 12 (gen 2 lần) | Đẳng cấp là mãi mãi! · Pha này lên sóng giờ vàng! · Ét o ét, đẹp quá trời! · Đóng khung treo phòng khách! — Ủa alo? Ai đánh đó? · Ơ kìa bạn ơi! · Về luyện thêm mười năm nha! · Bình tĩnh, tay đừng run! |

Prompt = đầu của gói 12 hoặc 13 (VOICES.md) + `Các câu: "…" "…"` + đuôi chung. Giữ kiểu gói 12: KHÔNG thêm
"Nói đúng từng câu" — để Gemini tự chế thêm câu vần cùng chủ đề (nhóm bấm tay nên câu tả cú đánh là đúng chỗ).
