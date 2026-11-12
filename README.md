# Ứng dụng Scan Tài Liệu Cá Nhân (Offline iOS 16+ & Android 10+)

Mã nguồn hoàn chỉnh triển khai toàn bộ 4 giai đoạn trong [app scan markdown.md](file:///f:/AI%20Code%20Productions/App%20Scan/app%20scan%20markdown.md):
- **100% Ngoại tuyến (Offline-First)**: Không tài khoản, không máy chủ, không quảng cáo, loại bỏ quyền `INTERNET` trong bản phát hành Android (`tools:node="remove"`).
- **Nhận diện mép giấy & Chỉnh phối cảnh 4 góc**: Tích hợp cầu nối native (`com.appscan.offline/vision` sử dụng Apple Vision `VNDetectRectanglesRequest` trên iOS và xử lý Otsu/Sobel trên Android) kết hợp bộ biến đổi phối cảnh Homography 4 góc chạy trên `Isolate`.
- **Chỉnh sửa Không phá hủy (Non-Destructive)**: Ảnh chụp gốc luôn được bảo toàn tại `app_scan_vault/originals/`; mọi thao tác cắt 4 góc, xoay 90°, áp bộ lọc (*Gốc, Màu sắc nét, Thang xám, Trắng đen khử bóng đổ, Tương phản cao*) và ký tên đều tạo bản đệm riêng.
- **OCR Ngoại tuyến Tiếng Việt & Tiếng Anh**: Đóng gói mô hình Latin của **Google ML Kit Text Recognition v2** kèm hộp tọa độ chuẩn hóa `[0..1]`, nhúng lớp văn bản ẩn vào PDF (Searchable PDF) và tìm kiếm toàn văn trong SQLite (khớp cả tiếng Việt có dấu và không dấu).
- **Lưu nháp & Khôi phục tự động**: Tự động lưu trạng thái `is_draft = 1` vào SQLite sau từng trang chụp để khôi phục ngay khi mở lại ứng dụng nếu bị đóng đột ngột.
- **Công cụ PDF Mở rộng & Chữ ký**: Nhập PDF có sẵn (kiểm tra an toàn PDF hỏng), gộp PDF, tách trang, chọn khổ giấy (*A4, Letter, Legal, Hóa đơn, Tự động*), nén dung lượng, vẽ chữ ký tay PNG trong suốt và đóng dấu ghi chú.
- **Khóa ứng dụng Sinh trắc học**: Hỗ trợ Face ID, Touch ID và vân tay Android qua `local_auth`.

---

## Cấu trúc thư mục chính

- [`pubspec.yaml`](file:///f:/AI%20Code%20Productions/App%20Scan/pubspec.yaml): Khai báo dependencies Flutter.
- [`lib/models/scan_models.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/models/scan_models.dart): Mô hình dữ liệu `ScanDocument`, `ScanPage`, `CropQuad`, `OcrResult`, `OcrWordBox`, `PageAnnotation` và hàm tính tỷ lệ lỗi ký tự `calculateCer`.
- [`lib/services/storage_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/storage_service.dart): Quản lý vùng lưu trữ cục bộ bất biến (`originals/`, `processed/`, `exports/`, `signatures/`) và ghi tệp nguyên tử qua `.tmp`.
- [`lib/services/database_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/database_service.dart): Cơ sở dữ liệu SQLite, lưu/khôi phục bản nháp và tìm kiếm toàn văn tiếng Việt/Anh.
- [`lib/services/vision_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/vision_service.dart): Nhận diện 4 góc tài liệu, biến đổi phối cảnh Homography và 5 bộ lọc tài liệu.
- [`lib/services/ocr_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/ocr_service.dart): Nhận dạng chữ in tiếng Việt & tiếng Anh ngoại tuyến bằng Google ML Kit Text Recognition v2.
- [`lib/services/pdf_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/pdf_service.dart): Tạo PDF nhiều trang có lớp chữ OCR ẩn (Searchable PDF), nhập PDF, gộp/tách và nén PDF.
- [`lib/services/benchmark_service.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/services/benchmark_service.dart): Bộ kiểm chuẩn tự động 30 mẫu tài liệu (kiểm tra tiêu chí >= 27/30 mép giấy và CER <= 5%).
- [`lib/screens/`](file:///f:/AI%20Code%20Productions/App%20Scan/lib/screens/library_screen.dart): Giao diện tiếng Việt gồm `LibraryScreen`, `ScannerScreen`, `PageEditorScreen`, `DocumentDetailScreen` và `PdfToolsScreen`.
- [`test/scanner_acceptance_test.dart`](file:///f:/AI%20Code%20Productions/App%20Scan/test/scanner_acceptance_test.dart): Bộ kiểm thử nghiệm thu tự động.
- [`.github/workflows/build.yml`](file:///f:/AI%20Code%20Productions/App%20Scan/.github/workflows/build.yml): Luồng CI/CD tự động build **Signed Android APK** và **iOS 16+ IPA**.

---

## Cách tự động Build APK Android & iOS IPA

### Cách 1: Tự động Build cả iOS (`.ipa`) và Android (`.apk`) trên GitHub Actions (Không cần cài Xcode/Android Studio trên máy)
1. Đẩy thư mục dự án này lên một kho chứa GitHub (có thể để chế độ **Private**).
2. Vào tab **Actions** trên GitHub -> chọn workflow **Build Android APK & iOS IPA (App Scan Offline)** -> bấm **Run workflow**.
3. Sau khi chạy xong, tải về 2 gói cài đặt tại mục **Artifacts**:
   - `AppScan-Android-Signed-APK` (`app-release.apk` đã ký sẵn, cài trực tiếp lên điện thoại Android 10+).
   - `AppScan-iOS-IPA` (`AppScan-iOS-16Plus.ipa` dành cho iOS 16+, có thể ký Ad-Hoc hoặc cài qua Sideloadly / AltStore / Xcode).

### Cách 2: Build trực tiếp trên máy Windows bằng Script tự động
Mở PowerShell tại thư mục dự án và chạy:
```powershell
.\scripts\build_local.ps1 -InstallFlutterIfMissing
```
Script sẽ tự động kiểm tra/tải Flutter SDK, chạy toàn bộ bài kiểm thử nghiệm thu 30 mẫu (`flutter test`), tự sinh keystore ký số cá nhân và xuất file `build\app\outputs\flutter-apk\app-release.apk`.

