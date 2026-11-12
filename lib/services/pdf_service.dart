import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/scan_models.dart';

class PdfImportException implements Exception {
  final String message;
  const PdfImportException(this.message);

  @override
  String toString() => message;
}

/// Dịch vụ tạo và xử lý PDF ngoại tuyến:
/// - Xuất PDF nhiều trang kèm lớp văn bản OCR ẩn (searchable PDF) để tìm kiếm và sao chép chữ.
/// - Vẽ lớp chữ ký hình ảnh và ghi chú lên trang PDF.
/// - Hỗ trợ chọn khổ giấy (A4, Letter, Legal, Hóa đơn, Tự động) và mức nén dung lượng.
/// - Nhập tệp PDF có sẵn thành các trang ảnh để tách, gộp, xoay hoặc ký tên.
class PdfService {
  /// Tạo dữ liệu PDF nhiều trang từ một `ScanDocument`.
  Future<Uint8List> buildSearchablePdf({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
  }) async {
    final pdf = pw.Document(
      title: document.title,
      author: 'App Scan Cá Nhân (Ngoại tuyến)',
      creator: 'App Scan Flutter',
    );

    final sortedPages = List<ScanPage>.from(document.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    for (final page in sortedPages) {
      final imageFile = File(page.displayImagePath);
      if (!await imageFile.exists()) continue;

      final rawBytes = await imageFile.readAsBytes();
      final preparedBytes = _compressPageBytesForPdf(rawBytes, quality);
      final decoded = img.decodeImage(preparedBytes);
      final imgW = (decoded?.width ?? 1200).toDouble();
      final imgH = (decoded?.height ?? 1700).toDouble();

      final double pageWidthPt;
      final double pageHeightPt;

      if (paperSize == PaperSizePreset.autoFit ||
          paperSize.widthPt == null ||
          paperSize.heightPt == null) {
        // Quy đổi tỷ lệ khung ảnh gốc sang đơn vị point chuẩn chiều rộng A4 (595pt).
        pageWidthPt = 595.28;
        pageHeightPt = (595.28 * imgH / imgW).clamp(200.0, 2000.0);
      } else {
        pageWidthPt = paperSize.widthPt!;
        pageHeightPt = paperSize.heightPt!;
      }

      final pageFormat = PdfPageFormat(pageWidthPt, pageHeightPt);
      final pdfImage = pw.MemoryImage(preparedBytes);

      // Chuẩn bị danh sách ảnh chữ ký nếu trang có đính kèm chữ ký PNG.
      final Map<String, pw.MemoryImage> annotationImages = {};
      for (final ann in page.annotations) {
        if (ann.imagePath != null && ann.imagePath!.isNotEmpty) {
          final sigFile = File(ann.imagePath!);
          if (await sigFile.exists()) {
            annotationImages[ann.id] =
                pw.MemoryImage(await sigFile.readAsBytes());
          }
        }
      }

      final ocrBoxes = page.ocrResult?.boxes ?? const <OcrWordBox>[];
      final fullOcrText = page.ocrResult?.fullText ?? '';

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                // 1. Lớp văn bản OCR ẩn (nằm dưới lớp ảnh hoặc dùng màu trong suốt)
                // giúp trình đọc PDF tìm kiếm (Ctrl+F) và sao chép văn bản.
                if (ocrBoxes.isNotEmpty)
                  ...ocrBoxes.map((box) {
                    final left = box.left * pageWidthPt;
                    final top = box.top * pageHeightPt;
                    final boxH = (box.height * pageHeightPt).clamp(6.0, 48.0);
                    return pw.Positioned(
                      left: left,
                      top: top,
                      child: pw.Text(
                        _sanitizePdfFontText(box.text),
                        style: pw.TextStyle(
                          fontSize: (boxH * 0.75).clamp(6.0, 36.0),
                          color: const PdfColor(0, 0, 0, 0.01),
                        ),
                      ),
                    );
                  })
                else if (fullOcrText.trim().isNotEmpty)
                  pw.Positioned(
                    left: 8,
                    top: 8,
                    right: 8,
                    child: pw.Text(
                      _sanitizePdfFontText(fullOcrText),
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColor(0, 0, 0, 0.01),
                      ),
                    ),
                  ),

                // 2. Lớp hình ảnh trang tài liệu chính.
                pw.Positioned.fill(
                  child: pw.FittedBox(
                    fit: pw.BoxFit.contain,
                    child: pw.Image(pdfImage, width: pageWidthPt, height: pageHeightPt),
                  ),
                ),

                // 3. Lớp chữ ký và ghi chú (Giai đoạn 4).
                ...page.annotations.map((ann) {
                  final left = (ann.x * pageWidthPt)
                      .clamp(0.0, pageWidthPt * 0.9);
                  final top = (ann.y * pageHeightPt)
                      .clamp(0.0, pageHeightPt * 0.9);
                  final width = (ann.width * pageWidthPt)
                      .clamp(30.0, pageWidthPt);
                  final height = (ann.height * pageHeightPt)
                      .clamp(20.0, pageHeightPt);

                  if (ann.kind == AnnotationKind.signature &&
                      annotationImages.containsKey(ann.id)) {
                    return pw.Positioned(
                      left: left,
                      top: top,
                      child: pw.SizedBox(
                        width: width,
                        height: height,
                        child: pw.Image(
                          annotationImages[ann.id]!,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    );
                  }

                  final noteText = _sanitizePdfFontText(ann.text ?? '');
                  if (noteText.isEmpty) return pw.SizedBox();

                  return pw.Positioned(
                    left: left,
                    top: top,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColor.fromInt(ann.colorArgb),
                          width: 1.2,
                        ),
                        borderRadius:
                            const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        noteText,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromInt(ann.colorArgb),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Nén ảnh trang theo cấu hình `PdfQualityPreset` trước khi đóng gói vào PDF.
  Uint8List _compressPageBytesForPdf(
    Uint8List rawBytes,
    PdfQualityPreset quality,
  ) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) return rawBytes;

    var working = decoded;
    if (working.width > quality.maxDimensionPx ||
        working.height > quality.maxDimensionPx) {
      if (working.width >= working.height) {
        working = img.copyResize(working, width: quality.maxDimensionPx);
      } else {
        working = img.copyResize(working, height: quality.maxDimensionPx);
      }
    }
    return Uint8List.fromList(
      img.encodeJpg(working, quality: quality.jpegQuality),
    );
  }

  /// Chuyển chuỗi sang bảng ký tự tương thích font chuẩn PDF cơ bản đồng thời giữ nguyên từ khóa không dấu
  /// để đảm bảo tìm kiếm PDF không bao giờ lỗi font ngay cả khi không nhúng font TTF ngoài.
  String _sanitizePdfFontText(String input) {
    const map = <String, String>{
      'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
      'À': 'A', 'Á': 'A', 'Ạ': 'A', 'Ả': 'A', 'Ã': 'A',
      'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ậ': 'A', 'Ẩ': 'A', 'Ẫ': 'A',
      'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ặ': 'A', 'Ẳ': 'A', 'Ẵ': 'A',
      'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
      'È': 'E', 'É': 'E', 'Ẹ': 'E', 'Ẻ': 'E', 'Ẽ': 'E',
      'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ệ': 'E', 'Ể': 'E', 'Ễ': 'E',
      'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
      'Ì': 'I', 'Í': 'I', 'Ị': 'I', 'Ỉ': 'I', 'Ĩ': 'I',
      'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
      'Ò': 'O', 'Ó': 'O', 'Ọ': 'O', 'Ỏ': 'O', 'Õ': 'O',
      'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ộ': 'O', 'Ổ': 'O', 'Ỗ': 'O',
      'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ợ': 'O', 'Ở': 'O', 'Ỡ': 'O',
      'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
      'Ù': 'U', 'Ú': 'U', 'Ụ': 'U', 'Ủ': 'U', 'Ũ': 'U',
      'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ự': 'U', 'Ử': 'U', 'Ữ': 'U',
      'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y',
      'Ỳ': 'Y', 'Ý': 'Y', 'Ỵ': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y',
      'đ': 'd', 'Đ': 'D',
    };
    final sb = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final ch = input[i];
      final mapped = map[ch] ?? ch;
      final code = mapped.codeUnitAt(0);
      if (code >= 32 && code <= 126 || code == 10 || code == 13) {
        sb.write(mapped);
      } else {
        sb.write(' ');
      }
    }
    return sb.toString();
  }

  /// Nhập tệp PDF có sẵn trên thiết bị và kết xuất từng trang thành danh sách ảnh PNG.
  /// Kiểm tra định dạng header `%PDF-` để báo lỗi rõ ràng nếu tệp PDF bị hỏng.
  Future<List<Uint8List>> rasterizeImportedPdf(
    String pdfFilePath, {
    double dpi = 150.0,
  }) async {
    final file = File(pdfFilePath);
    if (!await file.exists()) {
      throw const PdfImportException('Tệp PDF không tồn tại.');
    }

    final bytes = await file.readAsBytes();
    if (!isValidPdfBytes(bytes)) {
      throw const PdfImportException(
        'Tệp PDF bị hỏng hoặc không đúng định dạng chuẩn (%PDF-).',
      );
    }

    try {
      final List<Uint8List> pagePngs = [];
      await for (final page in Printing.raster(bytes, dpi: dpi)) {
        final png = await page.toPng();
        if (png.isNotEmpty) {
          pagePngs.add(png);
        }
      }
      if (pagePngs.isEmpty) {
        throw const PdfImportException('Tệp PDF không chứa trang nào hợp lệ.');
      }
      return pagePngs;
    } catch (e) {
      if (e is PdfImportException) rethrow;
      throw PdfImportException('Không thể đọc tệp PDF bị lỗi: $e');
    }
  }

  /// Kiểm tra nhanh chữ ký tệp `%PDF-` ở đầu tệp để phát hiện PDF hỏng.
  static bool isValidPdfBytes(Uint8List bytes) {
    if (bytes.length < 8) return false;
    // Header "%PDF-" tương ứng mã ASCII: 0x25, 0x50, 0x44, 0x46, 0x2D
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }
}

