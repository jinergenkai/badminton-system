Plan: Hype Voice Feature
Context
Add-on feature cho badminton scoring app. Sau khi đọc điểm xong, phát thêm voice "hype" (kiểu Unreal Tournament: Double Kill, Triple Kill, Godlike...) để tăng trải nghiệm. Không thay đổi behavior hiện tại của app.
Nguyên tắc

Non-invasive: không sửa logic tính điểm, chỉ subscribe vào event "point scored" có sẵn
Fail-safe: module lỗi không ảnh hưởng app chính (try-catch toàn bộ)
Toggle-able: user có thể tắt trong settings, mặc định ON
Event-driven: sau khi score announcement phát xong → mới phát hype voice
State management: GetX (theo convention hiện tại của app)

Assets
26 file mp3 đã có sẵn, bỏ vào assets/audio/hype/. Đặt tên snake_case:
double_kill, triple_kill, quadra_kill, penta_shot,
double_shot, triple_shot, quadra_shot,
hat_trick, nice_pair,
dominating, unstoppable, badminton_slayer, rampage,
godlike, legendary, to_the_moon, the_chosen_one,
shutdown,
game_on, lets_dance, here_we_go,
comeback_king, unbelievable, written_in_history,
did_you_see_that, mom_are_you_watching
Config (JSON)
Tạo assets/config/hype_voice_config.json với các trigger, mỗi trigger có priority và pool voice lines. Khi 1 event điểm match nhiều trigger, chọn priority cao nhất. Weighted random trong pool, tránh lặp 3 câu gần nhất.
Triggers cần có (priority cao → thấp):
TriggerKhi nàoPoolcomeback_kingThắng set sau khi từng bị dẫn ≥5 điểm trong set đócomeback_king, unbelievable, written_in_historyshutdownĐối thủ đang có streak ≥5 và bị phá (mình ăn lại 1 điểm)shutdownstreak_7_plusStreak ≥7godlike, legendary, to_the_moon, the_chosen_one, mom_are_you_watchingstreak_6Streak = 6rampage, did_you_see_thatstreak_5Streak = 5penta_shot, unstoppable, badminton_slayerstreak_4Streak = 4quadra_kill, quadra_shot, dominatingstreak_3Streak = 3triple_kill, triple_shot, hat_trickstreak_2Streak = 2double_kill, double_shot, nice_pairfirst_point_of_matchTỉ số 0-0 (chưa ai ghi điểm, trước khi giao cầu lần đầu)game_on, lets_dance, here_we_go
Note về first_point: user muốn phát lúc 0-0 → cần trigger ngay khi match bắt đầu, KHÔNG phải sau điểm đầu tiên. Xử lý riêng: khi user tạo match mới → phát ngay.
Thuật toán state cần track

Current streak: đội nào đang streak, streak bao nhiêu. Reset khi đội kia ghi điểm, reset khi qua set mới.
Last opponent streak: lưu lại streak của đối thủ ngay trước khi bị chặn → để check shutdown.
Max deficit per set: mỗi team trong mỗi set đã từng bị dẫn tối đa bao nhiêu điểm → để check comeback khi thắng set.
Recent voice IDs: queue 3 câu gần nhất đã phát → để tránh lặp.

Edge cases BẮT BUỘC handle

Undo điểm: phải revert toàn bộ state (streak, max deficit, voice history). Không trigger voice khi undo. Gợi ý: lưu history snapshot, undo = pop snapshot.
Qua set mới: streak reset về 0 cho cả 2 đội. Max deficit tracking riêng theo set.
Điểm đầu tiên của match: phát "game_on" lúc 0-0, không phải sau điểm 1-0.
Shutdown chỉ trigger 1 lần: khi vừa phá streak, không phát lại ở điểm tiếp theo.
Comeback chỉ trigger khi THẮNG SET, không phải khi gỡ hòa.

Integration point
Tìm chỗ score announcement (đọc "15 - 12") phát xong trong code hiện tại. Thêm hook ở đó để gọi hype voice player. Nếu chưa có callback onComplete thì thêm vào.
File structure đề xuất
lib/features/hype_voice/
models/ (voice_trigger, voice_line, game_state_snapshot)
services/ (hype_game_state, trigger_evaluator, hype_voice_player, config_loader)
hype_voice_controller.dart (GetX controller, inject vào app)

test/features/hype_voice/
(unit tests cho state tracker và trigger evaluator)

Toggle ON/OFF (default ON)
Volume slider (default 80%)
