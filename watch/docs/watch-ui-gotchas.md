# Bẫy UI của Vela QuickApp trên Mi Band 10

Những thứ đã mất thời gian debug rồi mới ra. **Đọc trước khi làm UI mới.**

Không cái nào trong đây có trong tài liệu chính thức — tất cả đều rút ra từ việc
đối chiếu trang chạy được với trang hỏng, hoặc từ probe chạy thẳng trên máy.

---

## 1. 🔴 `<list-item>` KHÔNG CÓ `height` THÌ KHÔNG VẼ GÌ CẢ

Đây là bẫy đắt nhất. Item cao 0px, **kéo theo toàn bộ con của nó biến mất**.
Không lỗi, không cảnh báo, không log — chỉ là một vùng trống.

Bằng chứng, cùng một app:

| Trang | style của list-item | Kết quả |
|---|---|---|
| `settings` | `height: 100px` | ✅ hiện |
| `media_list` | *không có* | ❌ trắng trơn |
| `diag` | *không có* | ❌ trắng trơn |

**Hậu quả thực tế:** danh sách nhạc **chưa bao giờ có thể hiển thị**, kể cả những
lần dữ liệu về tới nơi. Ta đã đi đuổi bug ở tầng truyền dữ liệu trong khi lỗi nằm
ở CSS.

```css
/* SAI — item biến mất */
.row { width: 100%; padding: 4px 10px; }

/* ĐÚNG */
.row { width: 100%; height: 20px; padding: 0 10px; }
```

Nếu nội dung phải xuống dòng thì **tự cắt chuỗi cho vừa** rồi cho mỗi khúc một
row cao cố định. Đừng trông vào việc item tự giãn theo nội dung.

Kèm theo: cho `<list>` **`height` tường minh** thay vì `flex: 1` — sample `<list>`
chính chủ của Xiaomi làm vậy. `flex: 1` có chỗ chạy có chỗ không.

## 2. 🔴 Đừng đặt nút ở 4 góc

Màn hình Mi Band 10 là hình chữ nhật **bo tròn**. Góc vừa bị bezel che vừa khó
bấm trúng bằng ngón tay.

- Chừa **~30px padding-top** cho mọi header. Chưa chừa thì tiêu đề và nút bị cắt
  (đã dính ở cả `diag` lẫn `media_list` — nút SYNC nằm lọt trong phần cong).
- Nút bấm nên **chiếm hết chiều ngang**, đặt ở giữa theo phương dọc.
- Badge/trang trí thì đặt góc được, nhưng đừng đặt thứ cần bấm.

## 3. `right:` bị bỏ qua với con absolute của `<stack>`

Chỉ `left` / `top` / `bottom` là ăn. Đặt `right` thì phần tử lặng lẽ rơi về
`left: 0` — badge streak từng bị lệch vì lỗi này.

Muốn căn giữa theo chiều ngang thì dùng **`align-self: center`** (đúng cách mà
`.score-watermark` đang dùng), đừng tính `left` cố định — nó chỉ đúng ở một bề
rộng duy nhất.

## 4. Toast hệ thống không đổi được vị trí

`prompt.showToast` vẽ **giữa màn hình**, đè lên đúng chỗ điểm số. Runtime dùng
`g_toastStyle` cố định, JS chỉ nhận `message` và `duration`.

Muốn đặt chỗ khác thì **tự làm toast**: một `<text>` `position: absolute` trong
stack gốc + `setTimeout` xoá. Xem `.toast` trong `pages/index`.

## 5. Thứ CHẠY ĐƯỢC (đã kiểm chứng trên máy)

- `transform: rotate(Ndeg)` — có hỗ trợ, compile ra `{"rotate":"45deg"}`.
- `overflow: hidden` **có** clip cả con đã bị xoay. Badge streak dựa hẳn vào điều
  này: một hình vuông xoay 45° bị cắt còn lại hình nêm.
- `align-self: center` trong `<stack>`.
- `text-align: center` + `width` cố định trên `<text>` — cách duy nhất để chữ
  đứng yên khi số ký tự thay đổi (`x1` vs `x12`).
- `lines: N` giới hạn số dòng; bỏ `text-overflow: ellipsis` nếu muốn nó xuống
  dòng thay vì bị cắt.

## 6. Mọi interface phải khai trong `manifest.json`

Thiếu thì build cảnh báo mà vẫn cho qua, rồi chết lúc chạy. `system.prompt` từng
bị thiếu suốt một thời gian dài.

```json
"features": [
  { "name": "system.interconnect" },
  { "name": "system.prompt" }
]
```

## 7. Mẹo: gắn nhãn build vào UI

Mỗi lần flash tốn nguyên quy trình cài lại, nên **"đây là bản mới hay bản cũ?"**
là câu hỏi tốn tiền. Trang `diag` có nhãn `DIAG b9` ngay trên tiêu đề. Đã mất 2
vòng debug chỉ vì câu hỏi này trước khi thêm nhãn.

## 8. Hai kiểu dòng trong một `<list>`: chưa có tiền lệ, đừng dùng

Chưa có code band nào dùng `<block for>` + `list-item if/else` để trộn hai kiểu
dòng. Dự án ebook mẫu còn **comment bỏ** đúng kiểu `list-item if=...`. Build có
cảnh báo: *"list-item cùng type phải có cấu trúc DOM giống hệt nhau"*.

Cách đang dùng (`match_history`): **một type, một cấu trúc cho mọi dòng**. Dòng
nào không cần phần phụ thì để chuỗi rỗng, và chiều cao đổi bằng style binding:

```html
<list-item type="match" for="{{ rows }}" class="record" style="height: {{ $item.h }}px">
```

`class` vẫn mang `height` mặc định. Nếu binding không ăn thì dòng chỉ thấp lại,
**không biến mất** (xem §1). ⚠️ Binding `height` trên `list-item` chưa được xác
nhận trên máy thật; `style` binding mới chỉ được chứng minh trên `div` (thanh
cooldown).

## 9. Thuộc tính làm việc của page: khai báo trong `private`

Gán ad hoc `this.foo = ...` cho thứ không khai báo là đánh cược. Lỗi Sound list
rỗng xảy ra vì một thuộc tính không nằm trong data bị framework bỏ đi. Mọi state
làm việc (kể cả không hiển thị) khai báo trong `private`. Mảng thì gán lại
(`this.red = this.red.concat([id])`) thay vì `push`, để thay đổi chắc chắn được
thấy.

## 10. Kiểm tra CSS sau build: tìm đúng định dạng

Bảng style biên dịch nằm trong `build/pages/<page>/<page>.js` dưới dạng
`[[0, "ten-class"]], {...}`, không phải `".ten-class"`. Một rule mất (ví dụ do
comment `/* */` không đóng) sẽ **không có** mục này. Tìm theo regex
`\[\s*0,\s*"ten-class"\s*\]`.
