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
    this.maxDimension = 2800,
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
    int maxDimension = 2800,
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

  /// Lấy kích thước (width, height) của ảnh sau khi đã chuẩn hóa hướng EXIF.
  Future<({int width, int height})?> getOrientedImageDimensions(
    String imagePath,
  ) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return compute(_decodeOrientedDimensionsIsolate, bytes);
  }

  static ({int width, int height})? _decodeOrientedDimensionsIsolate(
    Uint8List bytes,
  ) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    return (width: oriented.width, height: oriented.height);
  }

  /// Hàm chạy trên Isolate để nhận diện 4 góc tờ giấy từ dữ liệu ảnh.
  /// Kết hợp:
  /// 1) Phân tích ngưỡng Otsu + đạo hàm Sobel cho nền tương phản cao.
  /// 2) Lan truyền vùng trung tâm (Central-Seeded Chromatic & Edge Barrier Flood-Fill)
  ///    khi chụp giấy trên nền sáng (gạch men, bàn trắng, sàn nhà có nắng) để không bắt nhầm góc khung ảnh.
  static CropQuad detectDocumentCornersFromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return CropQuad.inset(0.06);

    final oriented = img.bakeOrientation(decoded);
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

    final totalPixels = analysisW * analysisH;
    final hist = List<int>.filled(256, 0);
    final luma = Uint8List(totalPixels);
    final rChan = Uint8List(totalPixels);
    final gChan = Uint8List(totalPixels);
    final bChan = Uint8List(totalPixels);

    for (int y = 0; y < analysisH; y++) {
      for (int x = 0; x < analysisW; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toInt().clamp(0, 255);
        final g = p.g.toInt().clamp(0, 255);
        final b = p.b.toInt().clamp(0, 255);
        final idx = y * analysisW + x;
        rChan[idx] = r;
        gChan[idx] = g;
        bChan[idx] = b;
        final v = ((r * 77 + g * 150 + b * 29) >> 8).clamp(0, 255);
        luma[idx] = v;
        hist[v]++;
      }
    }

    final threshold = _computeOtsuThreshold(hist, totalPixels);

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

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

    final fgRatio = fgCount / totalPixels;

    // Kiểm tra xem tứ giác Otsu có bị dính sát mép khung hình (do nền sàn nhà sáng màu) hay không.
    int frameEdgeTouches = 0;
    if (tl != null && tr != null && br != null && bl != null) {
      for (final pt in [tl, tr, br, bl]) {
        if (pt.x <= 0.035 ||
            pt.x >= 0.965 ||
            pt.y <= 0.035 ||
            pt.y >= 0.965) {
          frameEdgeTouches++;
        }
      }
    }

    // Nếu nền tối/tương phản tốt và không bị tràn ra sát 4 góc khung ảnh -> dùng kết quả Otsu
    if (tl != null &&
        tr != null &&
        br != null &&
        bl != null &&
        fgRatio > 0.08 &&
        fgRatio <= 0.74 &&
        frameEdgeTouches < 2) {
      final candidate = CropQuad(
        topLeft: tl.clamp(),
        topRight: tr.clamp(),
        bottomRight: br.clamp(),
        bottomLeft: bl.clamp(),
      );
      if (candidate.isValidQuad &&
          candidate.normalizedArea >= 0.10 &&
          candidate.normalizedArea <= 0.90) {
        return candidate;
      }
    }

    // Giai đoạn 2: Chuyên trị nền sáng / gạch men / bàn sáng màu (như ảnh chụp thực tế).
    // Dùng Flood-Fill từ tâm tài liệu kết hợp màu sắc giấy (Chromaticity) & rào cản cạnh Sobel.
    final floodQuad = _detectCornersByCentralFloodFill(
      analysisW: analysisW,
      analysisH: analysisH,
      rChan: rChan,
      gChan: gChan,
      bChan: bChan,
      luma: luma,
    );
    if (floodQuad != null &&
        floodQuad.isValidQuad &&
        floodQuad.normalizedArea >= 0.12 &&
        floodQuad.normalizedArea <= 0.92) {
      return floodQuad;
    }

    if (tl != null && tr != null && br != null && bl != null) {
      final fallbackCandidate = CropQuad(
        topLeft: tl.clamp(),
        topRight: tr.clamp(),
        bottomRight: br.clamp(),
        bottomLeft: bl.clamp(),
      );
      if (fallbackCandidate.isValidQuad &&
          fallbackCandidate.normalizedArea >= 0.10 &&
          fallbackCandidate.normalizedArea <= 0.92) {
        return fallbackCandidate;
      }
    }

    return CropQuad.inset(0.08);
  }

  /// Thuật toán tách tờ giấy khỏi nền sáng (sàn gạch, mặt bàn sáng) bằng cách:
  /// 1) Làm mượt cục bộ 3x3 để khử nhiễu chữ in bên trong tờ giấy.
  /// 2) Lấy mẫu màu nền giấy ở vùng tâm `[0.32..0.68] x [0.35..0.68]`.
  /// 3) Lan truyền (BFS Flood-Fill) từ tâm ra tới rào cản cạnh ngang/dọc hoặc nơi đổi màu nền.
  static CropQuad? _detectCornersByCentralFloodFill({
    required int analysisW,
    required int analysisH,
    required Uint8List rChan,
    required Uint8List gChan,
    required Uint8List bChan,
    required Uint8List luma,
  }) {
    final total = analysisW * analysisH;
    // Làm mượt 5x5 bằng bộ lọc hộp nhanh (loại bỏ nét chữ mảnh để giữ màu nền giấy đồng nhất)
    final smoothR = Uint8List(total);
    final smoothG = Uint8List(total);
    final smoothB = Uint8List(total);
    final smoothL = Uint8List(total);

    for (int y = 0; y < analysisH; y++) {
      final y0 = math.max(0, y - 2);
      final y1 = math.min(analysisH - 1, y + 2);
      for (int x = 0; x < analysisW; x++) {
        final x0 = math.max(0, x - 2);
        final x1 = math.min(analysisW - 1, x + 2);
        // Lấy pixel sáng thứ nhì (dilation nhẹ) trong lân cận để lấp chữ đen trên giấy
        int maxL = 0;
        int bestR = rChan[y * analysisW + x];
        int bestG = gChan[y * analysisW + x];
        int bestB = bChan[y * analysisW + x];
        for (int yy = y0; yy <= y1; yy += 2) {
          final rowOff = yy * analysisW;
          for (int xx = x0; xx <= x1; xx += 2) {
            final idx = rowOff + xx;
            final lv = luma[idx];
            if (lv > maxL) {
              maxL = lv;
              bestR = rChan[idx];
              bestG = gChan[idx];
              bestB = bChan[idx];
            }
          }
        }
        final outIdx = y * analysisW + x;
        smoothR[outIdx] = bestR;
        smoothG[outIdx] = bestG;
        smoothB[outIdx] = bestB;
        smoothL[outIdx] = maxL;
      }
    }

    // Lấy mẫu màu giấy ở vùng trung tâm
    final cx0 = (analysisW * 0.33).round();
    final cx1 = (analysisW * 0.67).round();
    final cy0 = (analysisH * 0.36).round();
    final cy1 = (analysisH * 0.68).round();

    double sumR = 0, sumG = 0, sumB = 0, sumL = 0;
    int sampleCount = 0;
    for (int y = cy0; y <= cy1; y++) {
      for (int x = cx0; x <= cx1; x++) {
        final idx = y * analysisW + x;
        if (smoothL[idx] >= 90) {
          sumR += smoothR[idx];
          sumG += smoothG[idx];
          sumB += smoothB[idx];
          sumL += smoothL[idx];
          sampleCount++;
        }
      }
    }
    if (sampleCount < 20) return null;

    final meanR = sumR / sampleCount;
    final meanG = sumG / sampleCount;
    final meanB = sumB / sampleCount;
    final meanL = sumL / sampleCount;
    // Độ lệch màu sắc chuẩn hóa (R-B, G-B) giúp phân biệt giấy trắng/vàng kem với gạch sàn xanh/xám
    final meanRG = meanR - meanG;
    final meanRB = meanR - meanB;

    // Tính bản đồ biên Sobel trên ảnh đã khử chữ (chỉ còn biên thật của mép giấy và đường gạch)
    final edgeGrad = Uint8List(total);
    for (int y = 1; y < analysisH - 1; y++) {
      for (int x = 1; x < analysisW - 1; x++) {
        final idx = y * analysisW + x;
        final gxL = (smoothL[idx + 1] - smoothL[idx - 1]).abs();
        final gyL = (smoothL[idx + analysisW] - smoothL[idx - analysisW]).abs();
        final gxC = (smoothR[idx + 1] -
                    smoothB[idx + 1] -
                    (smoothR[idx - 1] - smoothB[idx - 1]))
                .abs();
        final gyC = (smoothR[idx + analysisW] -
                    smoothB[idx + analysisW] -
                    (smoothR[idx - analysisW] - smoothB[idx - analysisW]))
                .abs();
        edgeGrad[idx] = math.min(255, gxL + gyL + ((gxC + gyC) >> 1));
      }
    }

    // Flood-fill từ tâm ra xung quanh
    final visited = Uint8List(total);
    final queue = Int32List(total);
    int qHead = 0;
    int qTail = 0;

    final seedX = analysisW ~/ 2;
    final seedY = (analysisH * 0.52).round();
    for (int dy = -6; dy <= 6; dy += 3) {
      for (int dx = -6; dx <= 6; dx += 3) {
        final sx = (seedX + dx).clamp(2, analysisW - 3);
        final sy = (seedY + dy).clamp(2, analysisH - 3);
        final sIdx = sy * analysisW + sx;
        if (visited[sIdx] == 0) {
          visited[sIdx] = 1;
          queue[qTail++] = sIdx;
        }
      }
    }

    while (qHead < qTail) {
      final curr = queue[qHead++];
      final cy = curr ~/ analysisW;
      final cx = curr - cy * analysisW;

      if (cx <= 2 ||
          cx >= analysisW - 3 ||
          cy <= 2 ||
          cy >= analysisH - 3) {
        continue;
      }

      final neighbors = [
        curr - 1,
        curr + 1,
        curr - analysisW,
        curr + analysisW,
      ];

      for (final nIdx in neighbors) {
        if (visited[nIdx] != 0) continue;
        if (edgeGrad[nIdx] > 34) continue;

        final dr = (smoothR[nIdx] - meanR).abs();
        final dg = (smoothG[nIdx] - meanG).abs();
        final db = (smoothB[nIdx] - meanB).abs();
        final dl = (smoothL[nIdx] - meanL).abs();

        final rgDiff = ((smoothR[nIdx] - smoothG[nIdx]) - meanRG).abs();
        final rbDiff = ((smoothR[nIdx] - smoothB[nIdx]) - meanRB).abs();

        final colorScore =
            (dr + dg + db) * 0.35 + dl * 0.45 + (rgDiff + rbDiff) * 0.95;
        if (colorScore <= 42.0) {
          visited[nIdx] = 1;
          queue[qTail++] = nIdx;
        }
      }
    }

    if (qTail < total * 0.08) return null;

    // Thu thập các điểm biên của vùng giấy vừa lan truyền
    final borderPts = <NormalizedPoint>[];
    for (int y = 2; y < analysisH - 2; y++) {
      for (int x = 2; x < analysisW - 2; x++) {
        final idx = y * analysisW + x;
        if (visited[idx] == 1) {
          if (visited[idx - 1] == 0 ||
              visited[idx + 1] == 0 ||
              visited[idx - analysisW] == 0 ||
              visited[idx + analysisW] == 0) {
            borderPts.add(
              NormalizedPoint(x / (analysisW - 1), y / (analysisH - 1)),
            );
          }
        }
      }
    }

    if (borderPts.length < 24) return null;

    // Tìm 4 đỉnh tứ giác từ tập điểm biên (kết hợp khoảng cách góc cực trị)
    NormalizedPoint bestTL = borderPts.first;
    NormalizedPoint bestTR = borderPts.first;
    NormalizedPoint bestBR = borderPts.first;
    NormalizedPoint bestBL = borderPts.first;

    double minTL = double.infinity;
    double maxTR = -double.infinity;
    double maxBR = -double.infinity;
    double minBL = double.infinity;

    for (final pt in borderPts) {
      final sum = pt.x + pt.y;
      final diff = pt.x - pt.y;
      if (sum < minTL) {
        minTL = sum;
        bestTL = pt;
      }
      if (sum > maxBR) {
        maxBR = sum;
        bestBR = pt;
      }
      if (diff > maxTR) {
        maxTR = diff;
        bestTR = pt;
      }
      if (diff < minBL) {
        minBL = diff;
        bestBL = pt;
      }
    }

    return CropQuad(
      topLeft: bestTL.clamp(),
      topRight: bestTR.clamp(),
      bottomRight: bestBR.clamp(),
      bottomLeft: bestBL.clamp(),
    );
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

    return Uint8List.fromList(img.encodeJpg(working, quality: 94));
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

  /// Bộ lọc "Màu sắc nét" (Magic Color chuẩn CamScanner):
  /// 1) Ước lượng bản đồ ánh sáng nền cục bộ (Local Illumination Flattening) trên lưới 24x32
  ///    để khử bóng đổ/ánh đèn không đều, giúp nền giấy trắng sáng đồng nhất từ trên xuống dưới.
  /// 2) Cân bằng chữ đen đậm sâu & bảo toàn/tăng nhẹ độ rực cho con dấu đỏ, chữ ký xanh, hoa văn.
  /// 3) Làm nét chữ thông minh (Adaptive Unsharp Mask) chỉ tác động lên biên chữ, không tăng nhiễu nền.
  static img.Image _applyMagicColor(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w < 8 || h < 8) return src.clone();

    // Bước 1: Ước lượng nền sáng cục bộ trên lưới thô (24x32) bằng giá trị sáng 90th-percentile
    const int gridX = 24;
    const int gridY = 32;
    final bgR = Float64List(gridX * gridY);
    final bgG = Float64List(gridX * gridY);
    final bgB = Float64List(gridX * gridY);

    for (int gy = 0; gy < gridY; gy++) {
      final yStart = (gy * h) ~/ gridY;
      final yEnd = math.max(yStart + 1, ((gy + 1) * h) ~/ gridY);
      final yStep = math.max(1, (yEnd - yStart) ~/ 6);

      for (int gx = 0; gx < gridX; gx++) {
        final xStart = (gx * w) ~/ gridX;
        final xEnd = math.max(xStart + 1, ((gx + 1) * w) ~/ gridX);
        final xStep = math.max(1, (xEnd - xStart) ~/ 6);

        final samples = <({int l, int r, int g, int b})>[];
        for (int y = yStart; y < yEnd; y += yStep) {
          for (int x = xStart; x < xEnd; x += xStep) {
            final p = src.getPixel(x, y);
            final r = p.r.toInt();
            final g = p.g.toInt();
            final b = p.b.toInt();
            final l = (r * 77 + g * 150 + b * 29) >> 8;
            samples.add((l: l, r: r, g: g, b: b));
          }
        }
        samples.sort((a, b) => a.l.compareTo(b.l));
        final pickIdx = ((samples.length - 1) * 0.88).round().clamp(0, samples.length - 1);
        final picked = samples[pickIdx];
        final gIdx = gy * gridX + gx;
        bgR[gIdx] = math.max(95.0, picked.r.toDouble());
        bgG[gIdx] = math.max(95.0, picked.g.toDouble());
        bgB[gIdx] = math.max(95.0, picked.b.toDouble());
      }
    }

    // Làm mịn 3x3 bản đồ nền để chuyển tiếp ánh sáng mượt mà không bị viền ô
    final smoothBgR = Float64List(gridX * gridY);
    final smoothBgG = Float64List(gridX * gridY);
    final smoothBgB = Float64List(gridX * gridY);
    for (int gy = 0; gy < gridY; gy++) {
      for (int gx = 0; gx < gridX; gx++) {
        double sr = 0, sg = 0, sb = 0;
        int cnt = 0;
        for (int dy = -1; dy <= 1; dy++) {
          final ny = gy + dy;
          if (ny < 0 || ny >= gridY) continue;
          for (int dx = -1; dx <= 1; dx++) {
            final nx = gx + dx;
            if (nx < 0 || nx >= gridX) continue;
            final nIdx = ny * gridX + nx;
            sr += bgR[nIdx];
            sg += bgG[nIdx];
            sb += bgB[nIdx];
            cnt++;
          }
        }
        final idx = gy * gridX + gx;
        smoothBgR[idx] = sr / cnt;
        smoothBgG[idx] = sg / cnt;
        smoothBgB[idx] = sb / cnt;
      }
    }

    // Bước 2: Chuẩn hóa nền + Chroma-Aware Tone Curve
    final toned = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      final fy = ((y + 0.5) * gridY / h - 0.5).clamp(0.0, (gridY - 1).toDouble());
      final gy0 = fy.floor();
      final gy1 = math.min(gridY - 1, gy0 + 1);
      final ty = fy - gy0;

      for (int x = 0; x < w; x++) {
        final fx = ((x + 0.5) * gridX / w - 0.5).clamp(0.0, (gridX - 1).toDouble());
        final gx0 = fx.floor();
        final gx1 = math.min(gridX - 1, gx0 + 1);
        final tx = fx - gx0;

        final i00 = gy0 * gridX + gx0;
        final i10 = gy0 * gridX + gx1;
        final i01 = gy1 * gridX + gx0;
        final i11 = gy1 * gridX + gx1;

        final localBgR = (smoothBgR[i00] * (1 - tx) + smoothBgR[i10] * tx) * (1 - ty) +
            (smoothBgR[i01] * (1 - tx) + smoothBgR[i11] * tx) * ty;
        final localBgG = (smoothBgG[i00] * (1 - tx) + smoothBgG[i10] * tx) * (1 - ty) +
            (smoothBgG[i01] * (1 - tx) + smoothBgG[i11] * tx) * ty;
        final localBgB = (smoothBgB[i00] * (1 - tx) + smoothBgB[i10] * tx) * (1 - ty) +
            (smoothBgB[i01] * (1 - tx) + smoothBgB[i11] * tx) * ty;

        final p = src.getPixel(x, y);
        final r0 = p.r.toDouble();
        final g0 = p.g.toDouble();
        final b0 = p.b.toDouble();

        // Chia theo ánh sáng nền cục bộ (giữ 12% sắc độ gốc để không cháy hoa văn vàng nhạt)
        double r = (r0 * 252.0 / localBgR) * 0.88 + r0 * 0.12;
        double g = (g0 * 252.0 / localBgG) * 0.88 + g0 * 0.12;
        double b = (b0 * 252.0 / localBgB) * 0.88 + b0 * 0.12;

        r = r.clamp(0.0, 255.0);
        g = g.clamp(0.0, 255.0);
        b = b.clamp(0.0, 255.0);

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        final chroma = maxC - minC;
        final luma = 0.299 * r + 0.587 * g + 0.114 * b;

        if (luma >= 216 && chroma < 24) {
          // Đẩy nền giấy trắng sạch tinh khiết như CamScanner
          final t = ((luma - 216) / 39.0).clamp(0.0, 1.0);
          final boost = t * (255.0 - luma);
          r = (r + boost).clamp(0.0, 255.0);
          g = (g + boost).clamp(0.0, 255.0);
          b = (b + boost).clamp(0.0, 255.0);
        } else if (chroma >= 26) {
          // Bảo toàn & làm rực nét con dấu đỏ, chữ ký mực xanh, hoa văn màu
          final satBoost = 1.24;
          r = (luma + (r - luma) * satBoost).clamp(0.0, 255.0);
          g = (luma + (g - luma) * satBoost).clamp(0.0, 255.0);
          b = (luma + (b - luma) * satBoost).clamp(0.0, 255.0);
          if (luma < 175) {
            r *= 0.90;
            g *= 0.90;
            b *= 0.90;
          }
        } else {
          // Vùng chữ in đen / đường kẻ: kéo tương phản sâu (S-curve) cho chữ đanh sắc nét
          final normL = (luma / 216.0).clamp(0.0, 1.0);
          final targetL = math.pow(normL, 1.38) * 216.0;
          final scale = luma > 1.0 ? (targetL / luma) : 1.0;
          r = (r * scale).clamp(0.0, 255.0);
          g = (g * scale).clamp(0.0, 255.0);
          b = (b * scale).clamp(0.0, 255.0);
        }

        toned.setPixelRgb(x, y, r.round(), g.round(), b.round());
      }
    }

    // Bước 3: Adaptive Unsharp Mask 3x3 (chỉ làm nét biên chữ, giữ nền trắng mịn)
    final out = toned.clone();
    const double sharpAmount = 0.48;
    const int sharpThreshold = 6;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final c = toned.getPixel(x, y);
        final u = toned.getPixel(x, y - 1);
        final d = toned.getPixel(x, y + 1);
        final l = toned.getPixel(x - 1, y);
        final rPx = toned.getPixel(x + 1, y);

        final avgR = (u.r + d.r + l.r + rPx.r + c.r * 2) / 6.0;
        final avgG = (u.g + d.g + l.g + rPx.g + c.g * 2) / 6.0;
        final avgB = (u.b + d.b + l.b + rPx.b + c.b * 2) / 6.0;

        final diffR = c.r - avgR;
        final diffG = c.g - avgG;
        final diffB = c.b - avgB;

        if (diffR.abs() >= sharpThreshold ||
            diffG.abs() >= sharpThreshold ||
            diffB.abs() >= sharpThreshold) {
          out.setPixelRgb(
            x,
            y,
            (c.r + diffR * sharpAmount).round().clamp(0, 255),
            (c.g + diffG * sharpAmount).round().clamp(0, 255),
            (c.b + diffB * sharpAmount).round().clamp(0, 255),
          );
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

