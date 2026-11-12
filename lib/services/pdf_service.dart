import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../models/scan_models.dart';

class PdfImportException implements Exception {
  final String message;
  const PdfImportException(this.message);

  @override
  String toString() => message;
}

/// Dịch vụ tạo và xử lý PDF ngoại tuyến:
/// - Nhúng trực tiếp phông Unicode Tiếng Việt (`BeVietnamPro-Regular.ttf` & `BeVietnamPro-Bold.ttf`)
///   để lớp văn bản OCR ẩn và ghi chú/con dấu giữ nguyên 100% dấu Tiếng Việt.
/// - Xuất PDF nhiều trang kèm lớp chữ tìm kiếm & sao chép được.
/// - Hỗ trợ chọn khổ giấy (A4, Letter, Legal, Hóa đơn, Tự động) và mức nén dung lượng.
/// - Nhập tệp PDF có sẵn thành các trang ảnh.
class PdfService {
  pw.Font? _cachedRegularFont;
  pw.Font? _cachedBoldFont;

  Future<pw.Font> _getVietnameseRegularFont() async {
    if (_cachedRegularFont != null) return _cachedRegularFont!;
    try {
      final data =
          await rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf');
      _cachedRegularFont = pw.Font.ttf(data);
      return _cachedRegularFont!;
    } catch (_) {
      try {
        final localFile = File('assets/fonts/BeVietnamPro-Regular.ttf');
        if (await localFile.exists()) {
          final bytes = await localFile.readAsBytes();
          _cachedRegularFont = pw.Font.ttf(ByteData.sublistView(bytes));
          return _cachedRegularFont!;
        }
      } catch (_) {}
      return pw.Font.helvetica();
    }
  }

  Future<pw.Font> _getVietnameseBoldFont() async {
    if (_cachedBoldFont != null) return _cachedBoldFont!;
    try {
      final data = await rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf');
      _cachedBoldFont = pw.Font.ttf(data);
      return _cachedBoldFont!;
    } catch (_) {
      try {
        final localFile = File('assets/fonts/BeVietnamPro-Bold.ttf');
        if (await localFile.exists()) {
          final bytes = await localFile.readAsBytes();
          _cachedBoldFont = pw.Font.ttf(ByteData.sublistView(bytes));
          return _cachedBoldFont!;
        }
      } catch (_) {}
      return pw.Font.helveticaBold();
    }
  }

  /// Tạo dữ liệu PDF nhiều trang từ một `ScanDocument` với đầy đủ dấu Tiếng Việt.
  Future<Uint8List> buildSearchablePdf({
    required ScanDocument document,
    PaperSizePreset paperSize = PaperSizePreset.a4,
    PdfQualityPreset quality = PdfQualityPreset.medium,
  }) async {
    final regularFont = await _getVietnameseRegularFont();
    final boldFont = await _getVietnameseBoldFont();

    final pdf = pw.Document(
      title: unorm.nfc(document.title),
      author: 'App Scan Cá Nhân',
      creator: 'App Scan Flutter',
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
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
        pageWidthPt = 595.28;
        pageHeightPt = (595.28 * imgH / imgW).clamp(200.0, 2000.0);
      } else {
        pageWidthPt = paperSize.widthPt!;
        pageHeightPt = paperSize.heightPt!;
      }

      final pageFormat = PdfPageFormat(pageWidthPt, pageHeightPt);
      final pdfImage = pw.MemoryImage(preparedBytes);

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
      final fullOcrText = unorm.nfc(page.ocrResult?.fullText ?? '');

      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                // 1. Lớp văn bản OCR ẩn với phông Unicode Tiếng Việt giúp tìm kiếm và sao chép chính xác dấu.
                if (ocrBoxes.isNotEmpty &&
                    ocrBoxes.any((b) => b.text.trim().isNotEmpty))
                  ...ocrBoxes
                      .where((b) => b.text.trim().isNotEmpty)
                      .map((box) {
                    final left = box.left * pageWidthPt;
                    final top = box.top * pageHeightPt;
                    final boxH = (box.height * pageHeightPt).clamp(6.0, 48.0);
                    return pw.Positioned(
                      left: left,
                      top: top,
                      child: pw.Text(
                        unorm.nfc(box.text),
                        style: pw.TextStyle(
                          font: regularFont,
                          fontSize: (boxH * 0.75).clamp(6.0, 36.0),
                          color: const PdfColor(0, 0, 0, 0.01),
                        ),
                      ),
                    );
                  }),
                if (fullOcrText.trim().isNotEmpty)
                  pw.Positioned(
                    left: 8,
                    top: 8,
                    right: 8,
                    child: pw.Text(
                      fullOcrText,
                      style: pw.TextStyle(
                        font: regularFont,
                        fontSize: 8,
                        color: const PdfColor(0, 0, 0, 0.01),
                      ),
                    ),
                  ),

                // 2. Lớp hình ảnh trang tài liệu chính.
                pw.Positioned.fill(
                  child: pw.FittedBox(
                    fit: pw.BoxFit.contain,
                    child: pw.Image(
                      pdfImage,
                      width: pageWidthPt,
                      height: pageHeightPt,
                    ),
                  ),
                ),

                // 3. Lớp chữ ký và con dấu/ghi chú Tiếng Việt.
                ...page.annotations.map((ann) {
                  final left =
                      (ann.x * pageWidthPt).clamp(0.0, pageWidthPt * 0.9);
                  final top =
                      (ann.y * pageHeightPt).clamp(0.0, pageHeightPt * 0.9);
                  final width =
                      (ann.width * pageWidthPt).clamp(30.0, pageWidthPt);
                  final height =
                      (ann.height * pageHeightPt).clamp(20.0, pageHeightPt);

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

                  final noteText = unorm.nfc(ann.text ?? '').trim();
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
                          font: boldFont,
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

  static bool isValidPdfBytes(Uint8List bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }
}
