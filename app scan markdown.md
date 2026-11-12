# Kế hoạch phát triển ứng dụng scan tài liệu cá nhân

## Tóm tắt

Xây dựng ứng dụng Flutter cho iOS và Android, chạy ngoại tuyến và lưu tài liệu trên thiết bị. Bản đầu tập trung đạt chất lượng tốt ở quy trình cốt lõi: chụp tài liệu, chỉnh trang, tạo PDF nhiều trang, OCR tiếng Việt và tiếng Anh, tìm kiếm và xuất file. CamScanner và Adobe Scan đều có OCR, tạo PDF và chỉnh sửa trang; CamScanner còn có nhiều công cụ PDF mở rộng. [Adobe Scan](https://www.adobe.com/devnet-docs/acrobat/ios/en/scan.html), [CamScanner FAQ](https://www.camscanner.com/faq)

Không làm tài khoản, máy chủ, đồng bộ đám mây, quảng cáo hay gói thuê bao. Chuyển đổi Word/Excel/PowerPoint và tính năng AI qua máy chủ để ngoài các giai đoạn đầu.

## Lộ trình và cách triển khai

1. **Chốt chuẩn scan và dựng nền tảng — khoảng 1 tuần.** Tạo ứng dụng Flutter mới; mặc định hỗ trợ iOS 16+ và Android 10+. Chuẩn bị bộ 30 ảnh mẫu gồm giấy A4, hóa đơn, tài liệu tiếng Việt/Anh, trang lệch và ảnh có bóng để so sánh với hai ứng dụng tham chiếu trên cùng thiết bị.

2. **Luồng scan và PDF cơ bản — khoảng 4–5 tuần.** Hỗ trợ chụp tự động hoặc thủ công, nhập nhiều ảnh đã chọn, nhận diện mép giấy, chỉnh bốn góc và phối cảnh, xoay, lọc màu/xám/trắng đen, thêm/xóa/đổi thứ tự/chụp lại trang. Lưu nháp để khôi phục sau khi ứng dụng bị đóng. Tạo PDF nhiều trang và xuất ảnh qua trình chia sẻ của hệ điều hành.

3. **OCR và thư viện tài liệu — khoảng 3–4 tuần.** Thêm OCR ngoại tuyến tiếng Việt/Anh, lớp văn bản ẩn trong PDF để tìm kiếm và sao chép, tìm kiếm toàn văn trong thư viện, đổi tên và gắn thẻ tài liệu. Thêm tùy chọn khóa ứng dụng bằng Face ID, Touch ID hoặc sinh trắc học Android.

4. **Công cụ PDF và hoàn thiện — khoảng 3–5 tuần.** Nhập PDF có sẵn; gộp, tách, xoay, sắp xếp và xóa trang; nén và chọn khổ giấy. Bổ sung ghi chú và chữ ký dạng hình ảnh, cùng kiểm tra cài đặt riêng trên thiết bị iOS và Android.

Ước lượng tổng thể là **12–16 tuần cho một lập trình viên Flutter có kinh nghiệm làm toàn thời gian**, chưa tính thời gian chuẩn bị máy Mac và hiệu chỉnh chất lượng theo thiết bị thực.

## Kiến trúc và dữ liệu

- Dùng Flutter cho giao diện; xử lý nhận diện mép giấy, hiệu chỉnh phối cảnh và bộ lọc bằng module OpenCV native dùng chung trên hai nền tảng.
- Dùng Google ML Kit Text Recognition v2 với mô hình Latin được đóng gói trong ứng dụng để OCR không cần mạng. Tài liệu Google liệt kê tiếng Việt là ngôn ngữ được hỗ trợ; mô hình Latin làm tăng dung lượng ứng dụng khoảng 38 MB trên iOS và 4 MB mỗi kiến trúc Android. [Tài liệu iOS](https://developers.google.com/ml-kit/vision/text-recognition/v2/ios), [Android](https://developers.google.com/ml-kit/vision/text-recognition/v2/android), [ngôn ngữ hỗ trợ](https://developers.google.com/ml-kit/vision/text-recognition/v2/languages)
- Lưu metadata bằng SQLite và ảnh/PDF trong vùng riêng của ứng dụng. Mỗi trang giữ ảnh gốc cùng thông tin cắt, xoay, bộ lọc, thứ tự và kết quả OCR; thao tác chỉnh sửa không ghi đè ảnh gốc.
- Mô hình dữ liệu nội bộ gồm `Document` (tên, ngày tạo, thư mục, thẻ) và `Page` (đường dẫn ảnh gốc, vùng cắt, xoay, bộ lọc, vị trí trang, văn bản OCR và hộp tọa độ). Cầu nối native trả về văn bản OCR cùng tọa độ đã chuẩn hóa; bộ tạo PDF dùng kết quả đó để tạo lớp chữ tìm kiếm được.
- Không gửi ảnh, PDF hay OCR lên mạng. Chỉ yêu cầu quyền camera khi chụp và dùng bộ chọn ảnh/tệp của hệ điều hành khi nhập.

## Kiểm thử và tiêu chí nghiệm thu

- Trên bộ ảnh mẫu, tự nhận diện đúng mép ít nhất **27/30 tài liệu phẳng, đủ sáng**; luôn có chỉnh góc thủ công nếu tự động nhận diện thất bại.
- OCR đạt tỷ lệ lỗi ký tự không quá **5% trên tài liệu in rõ**, với mẫu tiếng Việt và tiếng Anh; đánh giá riêng ảnh thiếu sáng hoặc cong để xác định giới hạn thực tế.
- PDF 20 trang giữ đúng thứ tự, đủ trang và có thể tìm kiếm nội dung OCR sau khi đóng rồi mở lại ứng dụng.
- Chụp, OCR, tìm kiếm và xuất PDF hoạt động ở chế độ máy bay; ứng dụng không tự gửi yêu cầu mạng.
- Kiểm tra từ chối quyền camera, thiếu dung lượng, ảnh sai hướng, ứng dụng bị đóng giữa lúc scan/xuất, lỗi OCR và PDF nhập bị hỏng; xác nhận bản nháp và ảnh gốc không bị mất.
- Chạy thử trên ít nhất một iPhone và một điện thoại Android trước khi phát hành bản riêng.

## Giả định và phát hành

- Giao diện mặc định bằng tiếng Việt; OCR bản đầu ưu tiên tài liệu in tiếng Việt và tiếng Anh. Nhận dạng chữ viết tay chỉ ở mức thử nghiệm.
- “Ngang tầm” nghĩa là hoàn thiện luồng scan, PDF, OCR và tìm kiếm cốt lõi; chưa bao gồm toàn bộ dịch vụ đám mây hay chuyển đổi định dạng nâng cao của CamScanner.
- Phân phối riêng: APK đã ký cho Android và bản iOS Ad Hoc cho thiết bị đã đăng ký. Flutter yêu cầu macOS/Xcode để dựng ứng dụng iOS, nên workspace Windows hiện tại cần máy Mac hoặc CI chạy macOS; Ad Hoc cũng cần hồ sơ ký và thiết bị đăng ký theo hướng dẫn Apple. [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup), [Apple Ad Hoc distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
