# Nhạc nền

Thả file `.mp3` / `.m4a` / `.aac` vào thư mục này rồi `flutter run` — app tự đồng bộ
danh sách nhạc (xem `lib/services/music_service.dart`, hàm `_syncBundledTracks`).

Nhạc ở đây **không đưa lên git**: phần lớn là nhạc thương mại có bản quyền, repo để
public thì dễ bị DMCA gỡ cả repo. Mỗi máy tự giữ bộ nhạc riêng.

Thư mục này phải tồn tại (kể cả rỗng) vì `pubspec.yaml` khai báo `assets/audio/music/`.
