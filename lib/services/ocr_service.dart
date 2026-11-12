import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import '../models/scan_models.dart';

/// Dịch vụ nhận dạng văn bản ngoại tuyến (Offline OCR) sử dụng Google ML Kit Text Recognition v2
/// với mô hình Latin đóng gói sẵn trong ứng dụng (hỗ trợ tiếng Việt có dấu và tiếng Anh).
/// Trả về văn bản đầy đủ cùng hộp tọa độ từ/dòng đã chuẩn hóa về [0.0, 1.0].
class OcrService {
  TextRecognizer? _recognizer;

  TextRecognizer get _instance {
    return _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Chạy OCR ngoại tuyến trên ảnh trang tài liệu (ưu tiên ảnh đã qua cắt & lọc).
  /// Nếu gặp lỗi môi trường hoặc ảnh không hợp lệ, trả về `OcrResult` rỗng an toàn
  /// để không làm gián đoạn luồng lưu tài liệu.
  Future<OcrResult> recognizePageImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return OcrResult(
        fullText: '',
        boxes: const [],
        recognizedAt: DateTime.now(),
      );
    }

    try {
      // Đọc kích thước ảnh thực tế để chuẩn hóa tọa độ hộp chữ về [0..1].
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      final imgWidth = (decoded?.width ?? 1000).toDouble();
      final imgHeight = (decoded?.height ?? 1400).toDouble();

      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _instance.processImage(inputImage);

      final List<OcrWordBox> normalizedBoxes = [];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final rect = element.boundingBox;
            final text = element.text.trim();
            if (text.isEmpty) continue;

            final left = (rect.left / imgWidth).clamp(0.0, 1.0);
            final top = (rect.top / imgHeight).clamp(0.0, 1.0);
            final right = (rect.right / imgWidth).clamp(left + 0.002, 1.0);
            final bottom = (rect.bottom / imgHeight).clamp(top + 0.002, 1.0);

            normalizedBoxes.add(
              OcrWordBox(
                text: text,
                left: left,
                top: top,
                right: right,
                bottom: bottom,
                confidence: element.confidence ?? 0.95,
              ),
            );
          }
        }
      }

      return OcrResult(
        fullText: recognized.text.trim(),
        boxes: normalizedBoxes,
        recognizedAt: DateTime.now(),
        languageHint: 'vi-en',
      );
    } catch (_) {
      // Đảm bảo lỗi OCR không làm mất trang hoặc crash ứng dụng (theo tiêu chí nghiệm thu).
      return OcrResult(
        fullText: '',
        boxes: const [],
        recognizedAt: DateTime.now(),
      );
    }
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

