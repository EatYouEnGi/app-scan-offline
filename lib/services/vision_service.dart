import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../models/scan_models.dart';

class _ProcessPagePayload {
  final Uint8List sourceBytes;
  final CropQuad cropQuad;
  final int rotationDegrees;
  final ScanFilterType filter;
  final int maxDimension;

  const _ProcessPagePayload({
    required this.sourceBytes,
    required this.cropQuad,
    required this.rotationDegrees,
    required this.filter,
    this.maxDimension = 2000,
  });
}

/// Dịch vụ thị giác máy tính:
/// - Kết nối cầu nối native `com.appscan.offline/vision` (OpenCV / Vision) nếu nền tảng cung cấp.
/// - Tích hợp sẵn bộ xử lý thuần Dart chạy trên `Isolate` (tự động xoay EXIF, nhận diện 4 góc giấy,
///   biến đổi phối cảnh Homography 4 góc, xoay trang, khử bóng đổ bằng ngưỡng thích nghi cục bộ).
class VisionService {
  static const MethodChannel _channel =
      MethodChannel('com.appscan.offline/vision');

  /// Nhận diện 4 góc tài liệu từ đường dẫn ảnh.
  /// Luôn trả về `CropQuad` hợp lệ; nếu ảnh quá tối hoặc nền trùng màu giấy,
  /// trả về khung lề an toàn để người dùng chỉnh góc thủ công.
  Future<CropQuad> detectDocumentCorners(String imagePath) async {
    try {
      final nativeMap = await _channel.invokeMapMethod<String, dynamic>(
        'detectDocumentCorners',
        {'imagePath': imagePath},
      );
      if (nativeMap != null) {
        final quad = CropQuad.fromJson(nativeMap);
        if (quad.isValidQuad) return quad;
      }
    } catch (_) {
      // Chuyển sang thuật toán nhận diện cạnh trên Isolate khi chạy độc lập.
    }

    final file = File(imagePath);
    if (!await file.exists()) {
      return CropQuad.inset(0.06);
    }
    final bytes = await file.readAsBytes();
    return compute(detectDocumentCornersFromBytes, bytes);
  }

  /// Thực thi cắt phối cảnh 4 góc, xoay và áp dụng bộ lọc màu mà không ghi đè ảnh gốc.
  Future<Uint8List> processPageImage({
    required String originalImagePath,
    required CropQuad cropQuad,
    required int rotationDegrees,
    required ScanFilterType filter,
    int maxDimension = 2000,
  }) async {
    final file = File(originalImagePath);
    if (!await file.exists()) {
      throw Exception('Không tìm thấy tệp ảnh gốc tại: $originalImagePath');
    }
    final sourceBytes = await file.readAsBytes();
    return compute(
      _processPageIsolate,
      _ProcessPagePayload(
        sourceBytes: sourceBytes,
        cropQuad: cropQuad,
        rotationDegrees: rotationDegrees,
        filter: filter,
        maxDimension: maxDimension,
      ),
    );
  }

  /// Hàm chạy trên Isolate để nhận diện 4 góc tờ giấy từ dữ liệu ảnh.
  static CropQuad detectDocumentCornersFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return CropQuad.inset(0.06);

    final oriented = img.bakeOrientation(decoded);
    // Thu nhỏ ảnh về cạnh dài ~240px để phân tích biên và độ sáng nhanh.
    final int analysisW;
    final int analysisH;
    if (oriented.width >= oriented.height) {
      analysisW = 240;
      analysisH =
          math.max(60, (oriented.height * 240 / oriented.width).round());
    } else {
      analysisH = 240;
      analysisW =
          math.max(60, (oriented.width * 240 / oriented.height).round());
    }

    final small = img.copyResize(
      oriented,
      width: analysisW,
      height: analysisH,
      interpolation: img.Interpolation.average,
    );

    // Tính histogram độ sáng và ngưỡng Otsu tách trang giấy sáng khỏi nền.
    final hist = List<int>.filled(256, 0);
    final luma = Uint8List(analysisW * analysisH);

    for (int y = 0; y < analysisH; y++) {
      for (int x = 0; x < analysisW; x++) {
        final p = small.getPixel(x, y);
        final v = ((p.r.toInt() * 77 + p.g.toInt() * 150 + p.b.toInt() * 29) >> 8)
            .clamp(0, 255)
            .toInt();
        luma[y * analysisW + x] = v;
        hist[v]++;
      }
    }

    final threshold = _computeOtsuThreshold(hist, analysisW * analysisH);

    // Tìm các điểm thuộc biên tờ giấy (vùng sáng hơn ngưỡng và có biến thiên biên).
    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity; // x - y nhỏ nhất -> bottomLeft
    double maxDiff = -double.infinity; // x - y lớn nhất -> topRight

    NormalizedPoint? tl;
    NormalizedPoint? tr;
    NormalizedPoint? br;
    NormalizedPoint? bl;

    int fgCount = 0;
    final marginX = (analysisW * 0.015).round().clamp(1, 10);
    final marginY = (analysisH * 0.015).round().clamp(1, 10);

    for (int y = marginY; y < analysisH - marginY; y++) {
      for (int x = marginX; x < analysisW - marginX; x++) {
        final idx = y * analysisW + x;
        final val = luma[idx];
        if (val >= threshold) {
          fgCount++;
          // Kiểm tra điểm biên: có ít nhất 1 lân cận tối hơn hoặc độ dốc Sobel cao.
          final gx = (luma[idx + 1] - luma[idx - 1]).abs();
          final gy = (luma[idx + analysisW] - luma[idx - analysisW]).abs();
          final isBorder = (gx + gy) > 18 ||
              luma[idx - 1] < threshold ||
              luma[idx + 1] < threshold ||
              luma[idx - analysisW] < threshold ||
              luma[idx + analysisW] < threshold;

          if (isBorder) {
            final nx = x / (analysisW - 1);
            final ny = y / (analysisH - 1);
            final sum = nx + ny;
            final diff = nx - ny;

            if (sum < minSum) {
              minSum = sum;
              tl = NormalizedPoint(nx, ny);
            }
            if (sum > maxSum) {
              maxSum = sum;
              br = NormalizedPoint(nx, ny);
            }
            if (diff > maxDiff) {
              maxDiff = diff;
              tr = NormalizedPoint(nx, ny);
            }
            if (diff < minDiff) {
              minDiff = diff;
              bl = NormalizedPoint(nx, ny);
            }
          }
        }
      }
    }

    final fgRatio = fgCount / (analysisW * analysisH);
    if (tl != null &&
        tr != null &&
        br != null &&
        bl != null &&
        fgRatio > 0.08 &&
        fgRatio < 0.98) {
      final candidate = CropQuad(
        topLeft: tl.clamp(),
        topRight: tr.clamp(),
        bottomRight: br.clamp(),
        bottomLeft: bl.clamp(),
      );
      if (candidate.isValidQuad && candidate.normalizedArea >= 0.10) {
        return candidate;
      }
    }

    // Nếu không tách được biên rõ ràng, trả về khung gợi ý để người dùng kéo 4 góc.
    return CropQuad.inset(0.06);
  }

  static int _computeOtsuThreshold(List<int> hist, int totalPixels) {
    double sum = 0;
    for (int t = 0; t < 256; t++) {
      sum += t * hist[t];
    }

    double sumB = 0;
    int wB = 0;
    int wF = 0;
    double varMax = 0;
    int threshold = 140;

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      wF = totalPixels - wB;
      if (wF == 0) break;

      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final varBetween = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);

      if (varBetween > varMax) {
        varMax = varBetween;
        threshold = t;
      }
    }
    return threshold.clamp(70, 220);
  }

  /// Xử lý toàn diện một trang: chuẩn hóa hướng EXIF -> cắt phối cảnh 4 góc -> xoay -> áp bộ lọc.
  static Uint8List _processPageIsolate(_ProcessPagePayload payload) {
    final decoded = img.decodeImage(payload.sourceBytes);
    if (decoded == null) {
      throw Exception('Không thể giải mã tệp hình ảnh.');
    }

    // 1. Chuẩn hóa hướng EXIF để khắc phục ảnh bị nghiêng/ngược từ camera.
    var working = img.bakeOrientation(decoded);

    // Giảm kích thước hợp lý nếu ảnh quá lớn để tối ưu bộ nhớ và tốc độ.
    if (working.width > payload.maxDimension ||
        working.height > payload.maxDimension) {
      if (working.width >= working.height) {
        working = img.copyResize(working, width: payload.maxDimension);
      } else {
        working = img.copyResize(working, height: payload.maxDimension);
      }
    }

    // 2. Biến đổi phối cảnh 4 góc (Perspective Warp / Homography) nếu không phải fullPage.
    if (!payload.cropQuad.isFullPage && payload.cropQuad.isValidQuad) {
      working = warpPerspective(working, payload.cropQuad);
    }

    // 3. Xoay trang theo bội số 90 độ.
    final rot = payload.rotationDegrees % 360;
    if (rot == 90) {
      working = img.copyRotate(working, angle: 90);
    } else if (rot == 180) {
      working = img.copyRotate(working, angle: 180);
    } else if (rot == 270) {
      working = img.copyRotate(working, angle: 270);
    }

    // 4. Áp dụng bộ lọc tài liệu.
    working = applyDocumentFilter(working, payload.filter);

    return Uint8List.fromList(img.encodeJpg(working, quality: 90));
  }

  /// Biến đổi phối cảnh 4 góc (Homography + nội suy song tuyến tính) để làm phẳng trang bị nghiêng.
  static img.Image warpPerspective(img.Image src, CropQuad quad) {
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    final p0 = math.Point<double>(quad.topLeft.x * w, quad.topLeft.y * h);
    final p1 = math.Point<double>(quad.topRight.x * w, quad.topRight.y * h);
    final p2 =
        math.Point<double>(quad.bottomRight.x * w, quad.bottomRight.y * h);
    final p3 =
        math.Point<double>(quad.bottomLeft.x * w, quad.bottomLeft.y * h);

    final widthTop = p0.distanceTo(p1);
    final widthBottom = p3.distanceTo(p2);
    final dstW = math.max(widthTop, widthBottom).round().clamp(64, src.width);

    final heightLeft = p0.distanceTo(p3);
    final heightRight = p1.distanceTo(p2);
    final dstH =
        math.max(heightLeft, heightRight).round().clamp(64, src.height);

    // Giải ma trận Homography ánh xạ từ tọa độ đích (u, v) sang tọa độ ảnh gốc (x, y).
    final hMatrix = _solveHomography(
      srcPoints: [
        const math.Point<double>(0, 0),
        math.Point<double>((dstW - 1).toDouble(), 0),
        math.Point<double>((dstW - 1).toDouble(), (dstH - 1).toDouble()),
        math.Point<double>(0, (dstH - 1).toDouble()),
      ],
      dstPoints: [p0, p1, p2, p3],
    );

    final dst = img.Image(width: dstW, height: dstH);
    final maxX = src.width - 1;
    final maxY = src.height - 1;

    for (int v = 0; v < dstH; v++) {
      for (int u = 0; u < dstW; u++) {
        final denom = hMatrix[6] * u + hMatrix[7] * v + 1.0;
        if (denom.abs() < 1e-9) continue;
        final srcX = (hMatrix[0] * u + hMatrix[1] * v + hMatrix[2]) / denom;
        final srcY = (hMatrix[3] * u + hMatrix[4] * v + hMatrix[5]) / denom;

        final x0 = srcX.floor().clamp(0, maxX);
        final y0 = srcY.floor().clamp(0, maxY);
        final x1 = (x0 + 1).clamp(0, maxX);
        final y1 = (y0 + 1).clamp(0, maxY);

        final dx = (srcX - x0).clamp(0.0, 1.0);
        final dy = (srcY - y0).clamp(0.0, 1.0);

        final c00 = src.getPixel(x0, y0);
        final c10 = src.getPixel(x1, y0);
        final c01 = src.getPixel(x0, y1);
        final c11 = src.getPixel(x1, y1);

        final r = _bilerp(c00.r, c10.r, c01.r, c11.r, dx, dy);
        final g = _bilerp(c00.g, c10.g, c01.g, c11.g, dx, dy);
        final b = _bilerp(c00.b, c10.b, c01.b, c11.b, dx, dy);

        dst.setPixelRgb(u, v, r, g, b);
      }
    }
    return dst;
  }

  static int _bilerp(
    num c00,
    num c10,
    num c01,
    num c11,
    double dx,
    double dy,
  ) {
    final top = c00 * (1.0 - dx) + c10 * dx;
    final bottom = c01 * (1.0 - dx) + c11 * dx;
    return (top * (1.0 - dy) + bottom * dy).round().clamp(0, 255);
  }

  /// Giải hệ phương trình tuyến tính 8 ẩn cho ma trận biến đổi phối cảnh 3x3.
  static List<double> _solveHomography({
    required List<math.Point<double>> srcPoints,
    required List<math.Point<double>> dstPoints,
  }) {
    final a = List.generate(8, (_) => List<double>.filled(9, 0.0));
    for (int i = 0; i < 4; i++) {
      final x = srcPoints[i].x;
      final y = srcPoints[i].y;
      final u = dstPoints[i].x;
      final v = dstPoints[i].y;

      final r1 = i * 2;
      final r2 = r1 + 1;

      a[r1][0] = x;
      a[r1][1] = y;
      a[r1][2] = 1.0;
      a[r1][6] = -x * u;
      a[r1][7] = -y * u;
      a[r1][8] = u;

      a[r2][3] = x;
      a[r2][4] = y;
      a[r2][5] = 1.0;
      a[r2][6] = -x * v;
      a[r2][7] = -y * v;
      a[r2][8] = v;
    }

    // Khử Gauss với chọn phần tử trụ từng phần (Partial Pivoting).
    for (int col = 0; col < 8; col++) {
      int pivot = col;
      for (int row = col + 1; row < 8; row++) {
        if (a[row][col].abs() > a[pivot][col].abs()) {
          pivot = row;
        }
      }
      final tmp = a[col];
      a[col] = a[pivot];
      a[pivot] = tmp;

      final div = a[col][col];
      if (div.abs() < 1e-12) continue;

      for (int j = col; j <= 8; j++) {
        a[col][j] /= div;
      }

      for (int row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = a[row][col];
        for (int j = col; j <= 8; j++) {
          a[row][j] -= factor * a[col][j];
        }
      }
    }

    return List<double>.generate(8, (i) => a[i][8]);
  }

  /// Áp dụng các bộ lọc nâng cao chất lượng tài liệu scan.
  static img.Image applyDocumentFilter(
    img.Image input,
    ScanFilterType filter,
  ) {
    switch (filter) {
      case ScanFilterType.original:
        return input;

      case ScanFilterType.grayscale:
        return img.grayscale(input.clone());

      case ScanFilterType.magicColor:
        return _applyMagicColor(input);

      case ScanFilterType.blackAndWhite:
        return _applyAdaptiveBlackAndWhite(input);

      case ScanFilterType.highContrast:
        final gray = img.grayscale(input.clone());
        return img.adjustColor(gray, contrast: 1.45, brightness: 1.05);
    }
  }

  /// Bộ lọc "Màu sắc nét" (Magic Color): làm trắng nền giấy bị ngả vàng/bóng mờ
  /// nhưng vẫn giữ nguyên màu mực bút ký và con dấu đỏ.
  static img.Image _applyMagicColor(img.Image src) {
    final out = src.clone();
    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final luma = (r * 77 + g * 150 + b * 29) >> 8;

        if (luma > 185) {
          // Đẩy vùng nền giấy sáng lên trắng sạch.
          final boost = ((luma - 185) * 1.15).round();
          out.setPixelRgb(
            x,
            y,
            (r + boost).clamp(0, 255),
            (g + boost).clamp(0, 255),
            (b + boost).clamp(0, 255),
          );
        } else {
          // Tăng độ đậm cho nét chữ và con dấu.
          final nr = ((r - 128) * 1.28 + 128).round().clamp(0, 255);
          final ng = ((g - 128) * 1.28 + 128).round().clamp(0, 255);
          final nb = ((b - 128) * 1.28 + 128).round().clamp(0, 255);
          out.setPixelRgb(x, y, nr, ng, nb);
        }
      }
    }
    return out;
  }

  /// Bộ lọc "Trắng đen" dùng ảnh tích phân (Integral Image) để tính ngưỡng thích nghi cục bộ,
  /// giúp loại bỏ bóng đổ khi chụp dưới ánh đèn nghiêng mà không làm mất chữ.
  static img.Image _applyAdaptiveBlackAndWhite(img.Image src) {
    final w = src.width;
    final h = src.height;
    final out = img.Image(width: w, height: h);
    final integral = Int32List((w + 1) * (h + 1));
    final luma = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final v = ((p.r.toInt() * 77 + p.g.toInt() * 150 + p.b.toInt() * 29) >> 8)
            .clamp(0, 255)
            .toInt();
        luma[y * w + x] = v;
        rowSum += v;
        integral[(y + 1) * (w + 1) + (x + 1)] =
            integral[y * (w + 1) + (x + 1)] + rowSum;
      }
    }

    final radius = math.max(12, (math.min(w, h) ~/ 28));
    const bias = 11;

    for (int y = 0; y < h; y++) {
      final y0 = math.max(0, y - radius);
      final y1 = math.min(h - 1, y + radius);
      for (int x = 0; x < w; x++) {
        final x0 = math.max(0, x - radius);
        final x1 = math.min(w - 1, x + radius);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);

        final sum = integral[(y1 + 1) * (w + 1) + (x1 + 1)] -
            integral[y0 * (w + 1) + (x1 + 1)] -
            integral[(y1 + 1) * (w + 1) + x0] +
            integral[y0 * (w + 1) + x0];

        final localMean = sum ~/ area;
        final pixelVal = luma[y * w + x];
        final bw = pixelVal < (localMean - bias) ? 18 : 255;
        out.setPixelRgb(x, y, bw, bw, bw);
      }
    }
    return out;
  }
}

