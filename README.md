# CFinder 

**CFinder** là bộ công cụ tiện ích cao cấp dành riêng cho macOS, tối ưu hóa phần cứng Apple Silicon (M1/M2/M3/M4). Ứng dụng tích hợp các tính năng thiết yếu trong một giao diện Dark Obsidian & Azure Blue chuẩn ngôn ngữ thiết kế Liquid Glass.

---

## ✨ Tính năng nổi bật

### 1. 🎥 Quay màn hình siêu mượt (Screen Recording)
- Tận dụng phần cứng **Apple Silicon VideoToolbox** mã hoá phần cứng zero-copy (60 / 120 FPS Retina).
- **Quét vùng chọn linh hoạt**: Kéo chuột để chọn chính xác vùng cần quay, hoặc bấm Phím cách (Space) để quay toàn màn hình.
- Lớp phủ trong suốt tàng hình (`sharingType = .none`), không dính viền đỏ hay thanh công cụ vào video xuất ra.
- Thanh điều khiển nổi (Floating HUD) với thời gian đếm thời lượng trực quan và nút Dừng nhanh (phím tắt `⌥R`).
- Tự động lưu `.mov` chất lượng cao ra Desktop và sao chép đường dẫn vào Clipboard.

### 2. ⚡ Chống ngủ & Tự ngủ thông minh (Power & Wake Engine)
- **Chống ngủ Mac (Keep-Awake)**:
  - Chọn nhanh thời lượng: `∞ Vô hạn`, `15 phút`, `30 phút`, `1 giờ`, `2 giờ`, `4 giờ`, `Đến 18:00`.
  - Tuỳ chọn **Màn hình ngủ (Display Sleep)**: Màn hình tự tắt tiết kiệm điện nhưng CPU vẫn chạy tiếp tục để tải tệp hoặc render đồ hoạ.
  - Tự ngắt chống ngủ khi pin MacBook yếu (<10%).
- **Hẹn giờ ngủ máy (Sleep Timer - Ban đêm)**:
  - Tự động đưa Mac vào giấc ngủ sau: `15m`, `30m`, `45m`, `1h`, `2h`.
  - Đa dạng hành động: Ngủ máy (Sleep), Tắt máy (Shut Down), Khoá màn hình (Lock), Tắt màn hình.
- **Tự ngủ khi tải xong (Network Idle Sleep)**:
  - Giám sát tốc độ truyền tải mạng theo thời gian thực (hỗ trợ Fshare, Torrent, Google Drive, Rclone).
  - Tự động ngủ/tắt máy an toàn khi mạng rỗi liên tục theo thời gian bảo vệ (Grace Period).

### 3. 🔍 Nhận diện chữ tức thì (Screen OCR)
- Quét và trích xuất văn bản từ bất kỳ vị trí nào trên màn hình bằng Apple Vision Framework.
- Hỗ trợ tiếng Việt đầy đủ dấu và độ chính xác cao.
- Lưu lại lịch sử quét và sao chép 1-chạm vào Clipboard (phím tắt `⌥C`).

### 4. 🪟 Chia màn hình cửa sổ (Snap Areas)
- Kéo cửa sổ vào các cạnh hoặc 4 góc màn hình để chia đôi (trái/phải), chia tư hoặc tối đa hoá tương tự macOS Sequoia / Windows Snap.
- Khung xem trước vùng chia trong suốt, mượt mà và tự bắt dính tự nhiên.

### 5. 🏷️ Đổi tên tệp hàng loạt (Batch Rename)
- Đổi tên tệp nhanh chóng trực tiếp từ menu chuột phải Finder: đánh số thứ tự, tìm & thay thế chữ, đổi đuôi mở rộng.
- Hỗ trợ hoàn tác tức thì (`⌘Z`) khôi phục lại tên tệp cũ.

### 6. 📋 Quản lý thanh Menu Bar (Menu Bar Icons)
- Giấu bớt các biểu tượng ứng dụng ít dùng để thanh Menu Bar luôn gọn gàng, tinh tế.
- Tự động mở rộng khi rê chuột hoặc nhấp chuột vào nút mũi tên điều khiển.

### 7. 📊 Giám sát phần cứng & Tốc độ mạng
- Đo lường thời gian thực nhiệt độ CPU/GPU, dung lượng RAM sử dụng và áp lực bộ nhớ (Memory Pressure).
- Hiển thị tốc độ tải xuống/tải lên trực tiếp trên thanh menu và đo tốc độ mạng Internet.

---

## 🛠️ Cài đặt & Biên dịch

### Yêu cầu hệ thống:
- macOS 14.0 (Sonoma) hoặc mới hơn.
- Apple Silicon Mac (M1/M2/M3/M4) hoặc Intel Mac.
- Xcode Command Line Tools (`xcode-select --install`).

### Biên dịch ứng dụng:
```bash
# Cấp quyền thực thi cho các script
chmod +x ./Scripts/*.sh

# Biên dịch toàn bộ gói ứng dụng Release
./Scripts/build.sh
```

### Cài đặt vào hệ thống:
```bash
./Scripts/install_extension.sh
```
Ứng dụng sẽ được cài đặt trực tiếp vào thư mục `/Applications/CFinder.app`.

---

## 📄 Bản quyền
Phát triển bởi đội ngũ CFinder Team.
Mã nguồn mở theo giấy phép MIT License.
