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
| 2 | streak_2 → streak_5_plus | bình luận viên bóng đá hài, nói nhanh, cười khoái chí | Song sát! · Tam sát! · Tứ sát! · Ngũ sát! · Thắng đời một không! |
| 3 | streak_high | rapper thong thả, chill, cà khịa nhẹ | Bá khí quá vậy! · Mãnh hổ hạ sơn! · Một mình một sân! · Ai cản nổi! · Ngồi xem đi! |
| 4 | shutdown | thì thầm bí ẩn rồi bật cười khúc khích | Nín! · Chấm dứt! · Hết phim! · Thân chưa mà giỡn! · Tắt điện! |
| 5 | comeback | hát ngân kiểu cải lương/vọng cổ hài, luyến láy | Lật kèo! · Quay xe! · Hồi sinh! · Chưa xong đâu! · Bay phấp phới! |
| 6 | crucial_moment | cô giáo mầm non dỗ dành, ngọt ngào mà hồi hộp | Deuce! · Bình tĩnh nha! · Tim đập chân run! · Một điểm thôi! |
| 7 | random_meme | nữ nhí nhảnh, cười khúc khích, lém lỉnh | Khét lẹt! · Hên lắm mới xui vậy! · Lưới ăn cầu! · Cầu này ai đỡ! · Khó chệu ghê! |
| 8 | streak_low (cú đẹp) | song ca nam nữ hát đối đáp vui, người hỏi người đáp | Đỉnh nóc kịch trần! · Khen đi, đọc stk! · Cầu biết bay! · Xỉu ngang! · Đẹp ghê chưa! |
| 9 | match_end | ông cụ kể chuyện chậm rãi, hóm hỉnh, cuối câu cười khà khà | Vô địch! · Thua thì trả tiền cầu! · Tám ba tám sáu! · Hẹn tái đấu! |
