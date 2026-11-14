import 'dart:convert';
import 'dart:math' as math;

/// Điểm tọa độ chuẩn hóa trong khoảng [0.0, 1.0] theo chiều rộng và chiều cao ảnh gốc.
class NormalizedPoint {
  final double x;
  final double y;

  const NormalizedPoint(this.x, this.y);

  NormalizedPoint clamp() {
    return NormalizedPoint(
      x.clamp(0.0, 1.0),
      y.clamp(0.0, 1.0),
    );
  }

  double distanceTo(NormalizedPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory NormalizedPoint.fromJson(Map<String, dynamic> json) {
    return NormalizedPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedPoint &&
          (x - other.x).abs() < 1e-6 &&
          (y - other.y).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(x.toStringAsFixed(6), y.toStringAsFixed(6));
}

/// Bốn góc cắt phối cảnh theo thứ tự:
/// topLeft (trên-trái), topRight (trên-phải), bottomRight (dưới-phải), bottomLeft (dưới-trái).
class CropQuad {
  final NormalizedPoint topLeft;
  final NormalizedPoint topRight;
  final NormalizedPoint bottomRight;
  final NormalizedPoint bottomLeft;

  const CropQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Khung mặc định bao trọn trang ảnh.
  factory CropQuad.fullPage() {
    return const CropQuad(
      topLeft: NormalizedPoint(0.0, 0.0),
      topRight: NormalizedPoint(1.0, 0.0),
      bottomRight: NormalizedPoint(1.0, 1.0),
      bottomLeft: NormalizedPoint(0.0, 1.0),
    );
  }

  /// Khung mặc định có lề an toàn khi tự động nhận diện cần người dùng chỉnh tay.
  factory CropQuad.inset([double margin = 0.06]) {
    return CropQuad(
      topLeft: NormalizedPoint(margin, margin),
      topRight: NormalizedPoint(1.0 - margin, margin),
      bottomRight: NormalizedPoint(1.0 - margin, 1.0 - margin),
      bottomLeft: NormalizedPoint(margin, 1.0 - margin),
    );
  }

  List<NormalizedPoint> get corners => [
        topLeft,
        topRight,
        bottomRight,
        bottomLeft,
      ];

  CropQuad withCorner(int index, NormalizedPoint point) {
    final clamped = point.clamp();
    switch (index) {
      case 0:
        return CropQuad(
          topLeft: clamped,
          topRight: topRight,
          bottomRight: bottomRight,
          bottomLeft: bottomLeft,
        );
      case 1:
        return CropQuad(
          topLeft: topLeft,
          topRight: clamped,
          bottomRight: bottomRight,
          bottomLeft: bottomLeft,
        );
      case 2:
        return CropQuad(
          topLeft: topLeft,
          topRight: topRight,
          bottomRight: clamped,
          bottomLeft: bottomLeft,
        );
      case 3:
        return CropQuad(
          topLeft: topLeft,
          topRight: topRight,
          bottomRight: bottomRight,
          bottomLeft: clamped,
        );
      default:
        return this;
    }
  }

  /// Tính diện tích tứ giác (Shoelace formula) trên không gian chuẩn hóa [0,1]x[0,1].
  double get normalizedArea {
    final pts = corners;
    double sum = 0.0;
    for (int i = 0; i < 4; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % 4];
      sum += (p1.x * p2.y) - (p2.x * p1.y);
    }
    return sum.abs() / 2.0;
  }

  /// Kiểm tra tứ giác lồi và diện tích hợp lệ (> 5% diện tích ảnh).
  bool get isValidQuad {
    if (normalizedArea < 0.05) return false;
    final pts = corners;
    bool? sign;
    for (int i = 0; i < 4; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 4];
      final c = pts[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-5) return false;
      final currentSign = cross > 0;
      sign ??= currentSign;
      if (sign != currentSign) return false;
    }
    return true;
  }

  bool get isFullPage =>
      topLeft.distanceTo(const NormalizedPoint(0, 0)) < 0.005 &&
      topRight.distanceTo(const NormalizedPoint(1, 0)) < 0.005 &&
      bottomRight.distanceTo(const NormalizedPoint(1, 1)) < 0.005 &&
      bottomLeft.distanceTo(const NormalizedPoint(0, 1)) < 0.005;

  /// Độ tương đồng góc trung bình (1.0 = trùng khớp tuyệt đối) để kiểm thử nhận diện mép.
  double similarityTo(CropQuad other) {
    final d0 = topLeft.distanceTo(other.topLeft);
    final d1 = topRight.distanceTo(other.topRight);
    final d2 = bottomRight.distanceTo(other.bottomRight);
    final d3 = bottomLeft.distanceTo(other.bottomLeft);
    final avgDist = (d0 + d1 + d2 + d3) / 4.0;
    return (1.0 - avgDist).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'topLeft': topLeft.toJson(),
        'topRight': topRight.toJson(),
        'bottomRight': bottomRight.toJson(),
        'bottomLeft': bottomLeft.toJson(),
      };

  factory CropQuad.fromJson(Map<String, dynamic> json) {
    return CropQuad(
      topLeft: NormalizedPoint.fromJson(json['topLeft'] as Map<String, dynamic>),
      topRight: NormalizedPoint.fromJson(json['topRight'] as Map<String, dynamic>),
      bottomRight:
          NormalizedPoint.fromJson(json['bottomRight'] as Map<String, dynamic>),
      bottomLeft:
          NormalizedPoint.fromJson(json['bottomLeft'] as Map<String, dynamic>),
    );
  }
}

/// Bộ lọc hình ảnh áp dụng không phá hủy (non-destructive) lên trang tài liệu.
enum ScanFilterType {
  original('Gốc', 'Giữ nguyên màu sắc từ ảnh chụp'),
  magicColor('Màu sắc nét', 'Tự động làm sáng nền giấy và tăng độ nét chữ màu'),
  grayscale('Thang xám', 'Chuyển sang xám dịu mắt cho văn bản nhiều trang'),
  blackAndWhite('Trắng đen', 'Khử bóng đổ, làm trắng nền giấy và đen chữ in'),
  highContrast('Tương phản cao', 'Làm rõ nét chữ mờ, hóa đơn nhiệt');

  final String label;
  final String description;
  const ScanFilterType(this.label, this.description);

  static ScanFilterType fromName(String? name) {
    return ScanFilterType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ScanFilterType.magicColor,
    );
  }
}

/// Khổ giấy khi xuất PDF.
enum PaperSizePreset {
  autoFit('Tự động theo trang', null, null),
  a4('A4 (210 × 297 mm)', 595.28, 841.89),
  letter('Letter (216 × 279 mm)', 612.0, 792.0),
  legal('Legal (216 × 356 mm)', 612.0, 1008.0),
  receipt('Hóa đơn (80 mm)', 226.77, 650.0);

  final String label;
  final double? widthPt;
  final double? heightPt;
  const PaperSizePreset(this.label, this.widthPt, this.heightPt);
}

/// Mức nén khi xuất hoặc nén PDF.
enum PdfQualityPreset {
  high('Chất lượng cao (In ấn 300 DPI)', 94, 3200),
  medium('Cân bằng sắc nét (Khuyên dùng)', 88, 2480),
  compressed('Dung lượng nhỏ (Gửi nhanh)', 72, 1650);

  final String label;
  final int jpegQuality;
  final int maxDimensionPx;
  const PdfQualityPreset(this.label, this.jpegQuality, this.maxDimensionPx);
}

/// Hộp tọa độ một từ hoặc cụm từ OCR đã chuẩn hóa về [0.0, 1.0].
class OcrWordBox {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  const OcrWordBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 1.0,
  });

  double get width => (right - left).clamp(0.001, 1.0);
  double get height => (bottom - top).clamp(0.001, 1.0);

  Map<String, dynamic> toJson() => {
        'text': text,
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'confidence': confidence,
      };

  factory OcrWordBox.fromJson(Map<String, dynamic> json) {
    return OcrWordBox(
      text: json['text'] as String? ?? '',
      left: (json['left'] as num?)?.toDouble() ?? 0.0,
      top: (json['top'] as num?)?.toDouble() ?? 0.0,
      right: (json['right'] as num?)?.toDouble() ?? 0.1,
      bottom: (json['bottom'] as num?)?.toDouble() ?? 0.05,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Kết quả OCR của một trang tài liệu, bao gồm văn bản toàn trang và danh sách hộp tọa độ.
class OcrResult {
  final String fullText;
  final List<OcrWordBox> boxes;
  final DateTime recognizedAt;
  final String languageHint;

  const OcrResult({
    required this.fullText,
    required this.boxes,
    required this.recognizedAt,
    this.languageHint = 'vi-en',
  });

  bool get hasText => fullText.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'fullText': fullText,
        'boxes': boxes.map((b) => b.toJson()).toList(),
        'recognizedAt': recognizedAt.toIso8601String(),
        'languageHint': languageHint,
      };

  factory OcrResult.fromJson(Map<String, dynamic> json) {
    final rawBoxes = json['boxes'] as List<dynamic>? ?? const [];
    return OcrResult(
      fullText: json['fullText'] as String? ?? '',
      boxes: rawBoxes
          .map((e) => OcrWordBox.fromJson(e as Map<String, dynamic>))
          .toList(),
      recognizedAt: DateTime.tryParse(json['recognizedAt'] as String? ?? '') ??
          DateTime.now(),
      languageHint: json['languageHint'] as String? ?? 'vi-en',
    );
  }

  /// Tính Tỷ lệ lỗi ký tự (Character Error Rate - CER) dùng khoảng cách Levenshtein
  /// để đối chiếu với tiêu chí nghiệm thu <= 5% trên tài liệu in rõ.
  static double calculateCer(String reference, String hypothesis) {
    final normRef = _normalizeForCer(reference);
    final normHyp = _normalizeForCer(hypothesis);
    if (normRef.isEmpty) {
      return normHyp.isEmpty ? 0.0 : 1.0;
    }
    final dist = _levenshteinDistance(normRef, normHyp);
    return dist / normRef.length;
  }

  static String _normalizeForCer(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int _levenshteinDistance(String s, String t) {
    final m = s.length;
    final n = t.length;
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }
}

/// Loại ghi chú hoặc chữ ký chèn lên trang tài liệu (Giai đoạn 4).
enum AnnotationKind {
  signature,
  note,
  stamp,
}

class PageAnnotation {
  final String id;
  final AnnotationKind kind;
  /// Tọa độ chuẩn hóa [0.0, 1.0] của tâm hoặc góc trên-trái trên trang.
  final double x;
  final double y;
  final double width;
  final double height;
  /// Đường dẫn ảnh PNG trong suốt (đối với chữ ký) hoặc nội dung chữ (đối với ghi chú/con dấu).
  final String? imagePath;
  final String? text;
  final int colorArgb;

  const PageAnnotation({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    this.width = 0.28,
    this.height = 0.12,
    this.imagePath,
    this.text,
    this.colorArgb = 0xFF1A237E,
  });

  PageAnnotation copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? imagePath,
    String? text,
    int? colorArgb,
  }) {
    return PageAnnotation(
      id: id,
      kind: kind,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      imagePath: imagePath ?? this.imagePath,
      text: text ?? this.text,
      colorArgb: colorArgb ?? this.colorArgb,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'imagePath': imagePath,
        'text': text,
        'colorArgb': colorArgb,
      };

  factory PageAnnotation.fromJson(Map<String, dynamic> json) {
    final kindStr = json['kind'] as String? ?? 'note';
    final kind = AnnotationKind.values.firstWhere(
      (e) => e.name == kindStr,
      orElse: () => AnnotationKind.note,
    );
    return PageAnnotation(
      id: json['id'] as String,
      kind: kind,
      x: (json['x'] as num?)?.toDouble() ?? 0.6,
      y: (json['y'] as num?)?.toDouble() ?? 0.8,
      width: (json['width'] as num?)?.toDouble() ?? 0.28,
      height: (json['height'] as num?)?.toDouble() ?? 0.12,
      imagePath: json['imagePath'] as String?,
      text: json['text'] as String?,
      colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFF1A237E,
    );
  }
}

/// Mô hình `Page`: Lưu đường dẫn ảnh gốc (không bao giờ bị ghi đè),
/// thông số cắt 4 góc, góc xoay, bộ lọc, vị trí trang, kết quả OCR và chữ ký/ghi chú.
class ScanPage {
  final String id;
  final String documentId;
  final int pageIndex;
  final String originalImagePath;
  final String? processedImagePath;
  final CropQuad cropQuad;
  final int rotationDegrees;
  final ScanFilterType filter;
  final OcrResult? ocrResult;
  final List<PageAnnotation> annotations;
  final DateTime updatedAt;

  const ScanPage({
    required this.id,
    required this.documentId,
    required this.pageIndex,
    required this.originalImagePath,
    this.processedImagePath,
    required this.cropQuad,
    this.rotationDegrees = 0,
    this.filter = ScanFilterType.magicColor,
    this.ocrResult,
    this.annotations = const [],
    required this.updatedAt,
  });

  /// Đường dẫn ảnh hiển thị ưu tiên bản đã xử lý (cắt + xoay + lọc), nếu chưa có thì dùng ảnh gốc.
  String get displayImagePath => processedImagePath ?? originalImagePath;

  ScanPage copyWith({
    String? documentId,
    int? pageIndex,
    String? originalImagePath,
    String? processedImagePath,
    bool clearProcessedImage = false,
    CropQuad? cropQuad,
    int? rotationDegrees,
    ScanFilterType? filter,
    OcrResult? ocrResult,
    List<PageAnnotation>? annotations,
    DateTime? updatedAt,
  }) {
    return ScanPage(
      id: id,
      documentId: documentId ?? this.documentId,
      pageIndex: pageIndex ?? this.pageIndex,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      processedImagePath: clearProcessedImage
          ? null
          : (processedImagePath ?? this.processedImagePath),
      cropQuad: cropQuad ?? this.cropQuad,
      rotationDegrees: (rotationDegrees ?? this.rotationDegrees) % 360,
      filter: filter ?? this.filter,
      ocrResult: ocrResult ?? this.ocrResult,
      annotations: annotations ?? this.annotations,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'document_id': documentId,
        'page_index': pageIndex,
        'original_image_path': originalImagePath,
        'processed_image_path': processedImagePath,
        'crop_quad_json': jsonEncode(cropQuad.toJson()),
        'rotation_degrees': rotationDegrees % 360,
        'filter_name': filter.name,
        'ocr_text': ocrResult?.fullText ?? '',
        'ocr_json': ocrResult != null ? jsonEncode(ocrResult!.toJson()) : null,
        'annotations_json':
            jsonEncode(annotations.map((a) => a.toJson()).toList()),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ScanPage.fromDbMap(Map<String, dynamic> map) {
    final cropJson = map['crop_quad_json'] as String?;
    final ocrJson = map['ocr_json'] as String?;
    final annotationsJson = map['annotations_json'] as String?;

    CropQuad quad = CropQuad.fullPage();
    if (cropJson != null && cropJson.isNotEmpty) {
      try {
        quad = CropQuad.fromJson(jsonDecode(cropJson) as Map<String, dynamic>);
      } catch (_) {
        quad = CropQuad.fullPage();
      }
    }

    OcrResult? ocr;
    if (ocrJson != null && ocrJson.isNotEmpty) {
      try {
        ocr = OcrResult.fromJson(jsonDecode(ocrJson) as Map<String, dynamic>);
      } catch (_) {
        ocr = null;
      }
    }

    List<PageAnnotation> parsedAnnotations = const [];
    if (annotationsJson != null && annotationsJson.isNotEmpty) {
      try {
        final rawList = jsonDecode(annotationsJson) as List<dynamic>;
        parsedAnnotations = rawList
            .map((e) => PageAnnotation.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        parsedAnnotations = const [];
      }
    }

    return ScanPage(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      pageIndex: (map['page_index'] as num).toInt(),
      originalImagePath: map['original_image_path'] as String,
      processedImagePath: map['processed_image_path'] as String?,
      cropQuad: quad,
      rotationDegrees: ((map['rotation_degrees'] as num?)?.toInt() ?? 0) % 360,
      filter: ScanFilterType.fromName(map['filter_name'] as String?),
      ocrResult: ocr,
      annotations: parsedAnnotations,
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Mô hình `Document`: đại diện cho một bộ tài liệu nhiều trang.
/// Hỗ trợ trạng thái `isDraft` để tự động lưu và khôi phục khi ứng dụng bị đóng đột ngột.
class ScanDocument {
  final String id;
  final String title;
  final String folder;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDraft;
  final String? lastExportedPdfPath;
  final List<ScanPage> pages;

  const ScanDocument({
    required this.id,
    required this.title,
    this.folder = 'Tất cả tài liệu',
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isDraft = false,
    this.lastExportedPdfPath,
    this.pages = const [],
  });

  int get pageCount => pages.length;

  /// Tổng hợp toàn bộ văn bản OCR của các trang theo đúng thứ tự.
  String get combinedOcrText {
    final sorted = List<ScanPage>.from(pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return sorted
        .map((p) => p.ocrResult?.fullText.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n\n--- Trang tiếp theo ---\n\n');
  }

  ScanDocument copyWith({
    String? title,
    String? folder,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDraft,
    String? lastExportedPdfPath,
    List<ScanPage>? pages,
  }) {
    return ScanDocument(
      id: id,
      title: title ?? this.title,
      folder: folder ?? this.folder,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isDraft: isDraft ?? this.isDraft,
      lastExportedPdfPath: lastExportedPdfPath ?? this.lastExportedPdfPath,
      pages: pages ?? this.pages,
    );
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'title': title,
        'folder': folder,
        'tags_json': jsonEncode(tags),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_draft': isDraft ? 1 : 0,
        'last_exported_pdf_path': lastExportedPdfPath,
      };

  factory ScanDocument.fromDbMap(
    Map<String, dynamic> map, {
    List<ScanPage> pages = const [],
  }) {
    List<String> parsedTags = const [];
    final rawTags = map['tags_json'] as String?;
    if (rawTags != null && rawTags.isNotEmpty) {
      try {
        parsedTags =
            (jsonDecode(rawTags) as List<dynamic>).map((e) => '$e').toList();
      } catch (_) {
        parsedTags = const [];
      }
    }

    final sortedPages = List<ScanPage>.from(pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    return ScanDocument(
      id: map['id'] as String,
      title: map['title'] as String? ?? 'Tài liệu mới',
      folder: map['folder'] as String? ?? 'Tất cả tài liệu',
      tags: parsedTags,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
      isDraft: ((map['is_draft'] as num?)?.toInt() ?? 0) == 1,
      lastExportedPdfPath: map['last_exported_pdf_path'] as String?,
      pages: sortedPages,
    );
  }
}

