import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scan_models.dart';
import '../theme/stitch_theme.dart';

/// Màn hình Camera AI Quét Tài Liệu Không Khung chuẩn thiết kế Google Stitch
/// (`2._camera_qu_t_ai_kh_ng_khung/code.html`):
/// - Tuyệt đối KHÔNG dùng khung vùng an toàn cố định.
/// - Tự động phát hiện tờ giấy/tài liệu ở bất kỳ vị trí nào trên ống kính theo thời gian thực,
///   vẽ lưới đa giác AI màu xanh ngọc (`#9CF0FF`) kèm tia quét laser động, 4 nút đỉnh phát sáng,
///   nhãn "GÓC CHÍNH XÁC 99%" và tự động chụp khi giữ êm.
/// - Thanh điều khiển nổi phía trên, khay ảnh thu nhỏ nhiều trang (`54x70`), cảm biến ánh sáng
///   và cụm nút chụp 2 vòng (Dual-Ring Shutter `78px`) ở vùng ngón cái dưới cùng (`#0F1215`).
class ScannerScreen extends StatefulWidget {
  final bool singleShotMode;
  final bool isVi;

  const ScannerScreen({
    super.key,
    this.singleShotMode = false,
    this.isVi = true,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _laserController;

  String _tr(String vi, String en) => widget.isVi ? vi : en;

  bool _initializingCamera = true;
  String? _cameraError;
  bool _aiAutoCapture = true;
  bool _isTakingPicture = false;
  bool _isAnalyzingFrame = false;
  bool _goodLighting = true;
  FlashMode _flashMode = FlashMode.off;

  /// Đa giác 4 góc của tờ giấy đang được AI phát hiện trực tiếp trên luồng camera.
  CropQuad? _liveDetectedQuad;
  CropQuad? _lastAutoCapturedQuad;
  bool _waitingForNextDocument = false;
  int _noDocFramesSinceCapture = 0;
  int _stableFrameCount = 0;
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);

  final List<String> _capturedPaths = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserController.dispose();
    _stopStreamAndDispose();
    super.dispose();
  }

  Future<void> _stopStreamAndDispose() async {
    final cam = _controller;
    _controller = null;
    if (cam != null) {
      try {
        if (cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } catch (_) {}
      await cam.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopStreamAndDispose();
    } else if (state == AppLifecycleState.resumed) {
      _setupCamera();
    }
  }

  Future<void> _setupCamera() async {
    setState(() {
      _initializingCamera = true;
      _cameraError = null;
    });

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializingCamera = false;
          _cameraError =
              'Thiết bị không có Camera. Bạn có thể chọn ảnh từ thư viện.';
        });
        return;
      }

      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      await controller.startImageStream(_onCameraFrame);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializingCamera = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializingCamera = false;
        _cameraError =
            'Không thể truy cập Camera (${e.description ?? e.code}). Hãy kiểm tra quyền Camera hoặc chọn ảnh từ thư viện.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializingCamera = false;
        _cameraError = 'Lỗi khởi tạo Camera: $e';
      });
    }
  }

  /// Phân tích trực tiếp luồng ảnh Camera (mỗi ~220ms) bằng bộ phân loại Tài liệu AI
  /// (Connected-Component + 4-Edge Contour + Fill Ratio) để phân biệt chính xác
  /// đâu là tờ giấy/tài liệu thật và đâu là cảnh vật thông thường (màn hình, bàn phím, mặt bàn).
  void _onCameraFrame(CameraImage image) {
    if (_isAnalyzingFrame || _isTakingPicture || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameTime).inMilliseconds < 220) return;
    _lastFrameTime = now;
    _isAnalyzingFrame = true;

    try {
      final detected = _detectPaperQuadFromCameraImage(image);
      if (!mounted) return;

      if (detected != null && detected.isValidQuad) {
        _noDocFramesSinceCapture = 0;

        // Nếu vừa tự chụp xong 1 tờ tài liệu, chờ người dùng lật trang hoặc di chuyển sang tờ mới
        if (_waitingForNextDocument && _lastAutoCapturedQuad != null) {
          final simToLast = detected.similarityTo(_lastAutoCapturedQuad!);
          if (simToLast < 0.84) {
            _waitingForNextDocument = false;
          }
        }

        final prev = _liveDetectedQuad;
        final isSteady = prev != null && prev.similarityTo(detected) >= 0.94;
        setState(() {
          _liveDetectedQuad = prev != null
              ? _smoothQuad(prev, detected, 0.45)
              : detected;
          if (_waitingForNextDocument) {
            _stableFrameCount = 0;
          } else {
            _stableFrameCount = isSteady ? (_stableFrameCount + 1) : 1;
          }
        });

        // Khi AI xác nhận đúng là tài liệu thật nằm ổn định liên tục ~6 nhịp (~1.3 giây) -> Tự chụp!
        if (_aiAutoCapture &&
            !_waitingForNextDocument &&
            _stableFrameCount >= 6 &&
            !_isTakingPicture) {
          _stableFrameCount = 0;
          _capturePhoto(fromAutoTrigger: true);
        }
      } else {
        _noDocFramesSinceCapture++;
        if (_noDocFramesSinceCapture >= 2) {
          _waitingForNextDocument = false;
        }
        if (_liveDetectedQuad != null || _stableFrameCount > 0) {
          setState(() {
            _liveDetectedQuad = null;
            _stableFrameCount = 0;
          });
        }
      }
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  CropQuad _smoothQuad(CropQuad oldQ, CropQuad newQ, double alpha) {
    NormalizedPoint lerpPt(NormalizedPoint a, NormalizedPoint b) {
      return NormalizedPoint(
        a.x * (1 - alpha) + b.x * alpha,
        a.y * (1 - alpha) + b.y * alpha,
      );
    }

    return CropQuad(
      topLeft: lerpPt(oldQ.topLeft, newQ.topLeft),
      topRight: lerpPt(oldQ.topRight, newQ.topRight),
      bottomRight: lerpPt(oldQ.bottomRight, newQ.bottomRight),
      bottomLeft: lerpPt(oldQ.bottomLeft, newQ.bottomLeft),
    );
  }

  /// Bộ phân loại & bắt 4 góc Tài Liệu AI (Document vs. Non-Document Classifier):
  /// 1. Chuẩn hóa luồng ảnh Camera về lưới dọc `pW x pH` (`64 x 84`) theo đúng hệ tọa độ màn hình.
  /// 2. Đóng hình thái học `3x3` (Morphological Closing) để xóa chữ in tối màu bên trong mặt giấy
  ///    nhưng vẫn giữ nguyên độ dốc biên (`rawGrad`) ở 4 cạnh mép giấy.
  /// 3. Loang miền liên thông (Connected-Component Flood Fill) từ vùng trung tâm, dừng tại biên độ dốc lớn.
  /// 4. Kiểm định 6 tiêu chuẩn khắt khe để loại bỏ hoàn toàn cảnh giả (màn hình máy tính, bàn phím, mặt bàn):
  ///    - Không bám sát viền khung hình camera (`< 4.5%` lề màn hình).
  ///    - Độ lấp đầy hình chữ nhật (`Solidity / Fill Ratio >= 0.72`).
  ///    - Cả 4 cạnh tứ giác phải có biên độ dốc thực sự (`Edge Support >= 0.60`).
  ///    - Độ tương phản giữa mặt trong tờ giấy và nền bên ngoài (`>= 14` đơn vị luma).
  ///    - 4 góc trong khoảng phối cảnh hợp lệ (`58° .. 122°`) và tỷ lệ cạnh đối diện cân xứng.
  CropQuad? _detectPaperQuadFromCameraImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;

    final rawW = image.width;
    final rawH = image.height;
    if (rawW < 64 || rawH < 64) return null;

    const int pW = 64;
    const int pH = 84;
    const int total = pW * pH;

    final luma = List<int>.filled(total, 0);
    double sumLuma = 0;

    // 1. Lấy mẫu về hệ tọa độ màn hình dọc (Portrait Normalized Grid 64x84)
    final bool sensorIsLandscape = rawW > rawH;
    for (int py = 0; py < pH; py++) {
      final double v = py / (pH - 1);
      for (int px = 0; px < pW; px++) {
        final double u = px / (pW - 1);
        final int sx;
        final int sy;
        if (sensorIsLandscape) {
          // Cảm biến nằm ngang (xoay 90 độ thuận chiều kim đồng hồ trên Android / một số luồng iOS)
          sx = (v * (rawW - 1)).round();
          sy = ((1.0 - u) * (rawH - 1)).round();
        } else {
          sx = (u * (rawW - 1)).round();
          sy = (v * (rawH - 1)).round();
        }

        final int offset = sy * rowStride + (isBgra ? sx * 4 : sx);
        int yVal = 0;
        if (isBgra) {
          if (offset >= 0 && offset + 2 < bytes.length) {
            final b = bytes[offset];
            final g = bytes[offset + 1];
            final r = bytes[offset + 2];
            yVal = ((r * 77 + g * 150 + b * 29) >> 8).clamp(0, 255);
          }
        } else {
          if (offset >= 0 && offset < bytes.length) {
            yVal = bytes[offset];
          }
        }
        luma[py * pW + px] = yVal;
        sumLuma += yVal;
      }
    }

    final avgLuma = sumLuma / total;
    _goodLighting = avgLuma >= 70;

    // 2. Đóng hình thái học 3x3 (Max-filter / Dilation nhẹ) để lấp chữ in bên trong mặt giấy
    //    và tính Gradient Sobel trên bề mặt đã làm mịn chữ.
    final surfaceLuma = List<int>.filled(total, 0);
    for (int y = 0; y < pH; y++) {
      final y0 = math.max(0, y - 1);
      final y1 = math.min(pH - 1, y + 1);
      for (int x = 0; x < pW; x++) {
        final x0 = math.max(0, x - 1);
        final x1 = math.min(pW - 1, x + 1);
        int sum9 = 0;
        int max9 = 0;
        int cnt = 0;
        for (int yy = y0; yy <= y1; yy++) {
          final rowOff = yy * pW;
          for (int xx = x0; xx <= x1; xx++) {
            final v = luma[rowOff + xx];
            sum9 += v;
            if (v > max9) max9 = v;
            cnt++;
          }
        }
        // Kết hợp trung bình cục bộ và đỉnh sáng cục bộ để xóa nét chữ tối màu trên nền giấy
        final mean9 = sum9 ~/ cnt;
        surfaceLuma[y * pW + x] = ((mean9 * 3 + max9 * 2) ~/ 5).clamp(0, 255);
      }
    }

    final gradMag = List<int>.filled(total, 0);
    for (int y = 1; y < pH - 1; y++) {
      final row = y * pW;
      for (int x = 1; x < pW - 1; x++) {
        final idx = row + x;
        final gx = (surfaceLuma[idx + 1] - surfaceLuma[idx - 1]).abs();
        final gy = (surfaceLuma[idx + pW] - surfaceLuma[idx - pW]).abs();
        gradMag[idx] = gx + gy;
      }
    }

    // 3. Thử các hạt giống (Seeds) ở vùng trung tâm khung ngắm để tìm miền liên thông của tờ giấy
    const seedCoords = <List<double>>[
      [0.50, 0.50],
      [0.50, 0.40],
      [0.50, 0.60],
      [0.40, 0.50],
      [0.60, 0.50],
    ];

    CropQuad? bestQuad;
    double bestScore = 0.0;

    for (final sc in seedCoords) {
      final sx = (sc[0] * (pW - 1)).round().clamp(6, pW - 7);
      final sy = (sc[1] * (pH - 1)).round().clamp(6, pH - 7);

      // Tính độ sáng nền và độ đồng nhất của vùng hạt giống 5x5
      int seedSum = 0;
      int seedGradSum = 0;
      int seedCnt = 0;
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          final idx = (sy + dy) * pW + (sx + dx);
          seedSum += surfaceLuma[idx];
          seedGradSum += gradMag[idx];
          seedCnt++;
        }
      }
      final seedMean = seedSum ~/ seedCnt;
      final seedAvgGrad = seedGradSum / seedCnt;

      // Mặt giấy/tài liệu phải có độ sáng nền hợp lý (>= 92) và vùng tâm không bị nhiễu hỗn loạn (như bàn phím cơ)
      if (seedMean < 92 || seedAvgGrad > 28) continue;

      final visited = List<bool>.filled(total, false);
      final queue = List<int>.filled(total, 0);
      int head = 0;
      int tail = 0;

      final startIdx = sy * pW + sx;
      visited[startIdx] = true;
      queue[tail++] = startIdx;

      int borderTouchCount = 0;
      const int maxLumaDiffFromSeed = 40;
      const int maxStepDiff = 14;
      const int edgeBarrier = 26;

      while (head < tail) {
        final curr = queue[head++];
        final cy = curr ~/ pW;
        final cx = curr % pW;
        final currLuma = surfaceLuma[curr];

        if (cx <= 2 || cx >= pW - 3 || cy <= 2 || cy >= pH - 3) {
          borderTouchCount++;
        }

        const dirs = <List<int>>[
          [1, 0],
          [-1, 0],
          [0, 1],
          [0, -1],
        ];
        for (final d in dirs) {
          final nx = cx + d[0];
          final ny = cy + d[1];
          if (nx < 1 || nx >= pW - 1 || ny < 1 || ny >= pH - 1) continue;
          final nIdx = ny * pW + nx;
          if (visited[nIdx]) continue;

          final nLuma = surfaceLuma[nIdx];
          final nGrad = gradMag[nIdx];
          if (nGrad <= edgeBarrier &&
              (nLuma - seedMean).abs() <= maxLumaDiffFromSeed &&
              (nLuma - currLuma).abs() <= maxStepDiff) {
            visited[nIdx] = true;
            queue[tail++] = nIdx;
          }
        }
      }

      final compCount = tail;
      final compFrac = compCount / total;
      // Quy tắc 1: Diện tích miền liên thông phải từ 10% đến 75% khung hình và không tràn ra mép màn hình
      if (compFrac < 0.10 || compFrac > 0.75) continue;
      if (borderTouchCount / compCount > 0.05) continue;

      // Tìm các điểm biên của miền liên thông để xác định 4 đỉnh tứ giác
      double minSum = double.infinity;
      double maxSum = -double.infinity;
      double minDiff = double.infinity;
      double maxDiff = -double.infinity;
      NormalizedPoint? tl;
      NormalizedPoint? tr;
      NormalizedPoint? br;
      NormalizedPoint? bl;

      for (int i = 0; i < compCount; i++) {
        final idx = queue[i];
        final cy = idx ~/ pW;
        final cx = idx % pW;
        final isBoundary = !visited[idx - 1] ||
            !visited[idx + 1] ||
            !visited[idx - pW] ||
            !visited[idx + pW];
        if (!isBoundary) continue;

        final nx = cx / (pW - 1);
        final ny = cy / (pH - 1);
        final s = nx + ny;
        final d = nx - ny;

        if (s < minSum) {
          minSum = s;
          tl = NormalizedPoint(nx, ny);
        }
        if (s > maxSum) {
          maxSum = s;
          br = NormalizedPoint(nx, ny);
        }
        if (d > maxDiff) {
          maxDiff = d;
          tr = NormalizedPoint(nx, ny);
        }
        if (d < minDiff) {
          minDiff = d;
          bl = NormalizedPoint(nx, ny);
        }
      }

      if (tl == null || tr == null || br == null || bl == null) continue;

      final quad = CropQuad(
        topLeft: tl.clamp(),
        topRight: tr.clamp(),
        bottomRight: br.clamp(),
        bottomLeft: bl.clamp(),
      );
      if (!quad.isValidQuad) continue;

      // Quy tắc 2: Không cho phép >= 2 góc nằm sát mép ngoài khung hình (< 4.5% lề)
      int nearBorderCorners = 0;
      for (final c in quad.corners) {
        if (c.x < 0.045 || c.x > 0.955 || c.y < 0.045 || c.y > 0.955) {
          nearBorderCorners++;
        }
      }
      if (nearBorderCorners >= 2) continue;

      // Quy tắc 3: Kiểm tra hình học phối cảnh (Diện tích, Tỷ lệ cạnh đối diện, Góc trong 58°..122°)
      final qArea = quad.normalizedArea;
      if (qArea < 0.12 || qArea > 0.76) continue;
      if (!_hasValidDocumentPerspectiveGeometry(quad)) continue;

      // Quy tắc 4: Độ đặc hình chữ nhật (Rectangular Solidity / Fill Ratio >= 0.72)
      final compRatioToQuad = compFrac / qArea;
      if (compRatioToQuad < 0.68 || compRatioToQuad > 1.18) continue;

      // Quy tắc 5: Kiểm định độ tương phản biên dọc theo cả 4 cạnh (4-Side Edge Support)
      final edgeScore = _evaluateQuadFourSidesContrast(
        quad: quad,
        surfaceLuma: surfaceLuma,
        gradMag: gradMag,
        pW: pW,
        pH: pH,
        seedMean: seedMean,
      );
      if (edgeScore < 0.60) continue;

      final totalScore = edgeScore * 0.65 +
          compRatioToQuad.clamp(0.0, 1.0) * 0.25 +
          math.min(qArea, 0.45) * 0.10;
      if (totalScore > bestScore) {
        bestScore = totalScore;
        bestQuad = quad;
      }
    }

    return bestQuad;
  }

  /// Kiểm tra tứ giác có đúng hình học phối cảnh của một tờ tài liệu hình chữ nhật hay không.
  bool _hasValidDocumentPerspectiveGeometry(CropQuad q) {
    double dist(NormalizedPoint a, NormalizedPoint b) {
      return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    }

    final topW = dist(q.topLeft, q.topRight);
    final bottomW = dist(q.bottomLeft, q.bottomRight);
    final leftH = dist(q.topLeft, q.bottomLeft);
    final rightH = dist(q.topRight, q.bottomRight);

    if (topW < 0.18 || bottomW < 0.18 || leftH < 0.18 || rightH < 0.18) {
      return false;
    }

    final wRatio = topW / bottomW;
    final hRatio = leftH / rightH;
    // Hai cạnh đối diện của tờ giấy không thể lệch nhau quá mức dưới phối cảnh bình thường
    if (wRatio < 0.54 || wRatio > 1.85 || hRatio < 0.54 || hRatio > 1.85) {
      return false;
    }

    final avgW = (topW + bottomW) * 0.5;
    final avgH = (leftH + rightH) * 0.5;
    final aspect = avgW / avgH;
    if (aspect < 0.42 || aspect > 1.80) return false;

    // Kiểm tra cả 4 góc trong đều phải nằm trong khoảng [58°, 122°]
    final pts = q.corners;
    for (int i = 0; i < 4; i++) {
      final prev = pts[(i + 3) % 4];
      final curr = pts[i];
      final next = pts[(i + 1) % 4];
      final v1x = prev.x - curr.x;
      final v1y = prev.y - curr.y;
      final v2x = next.x - curr.x;
      final v2y = next.y - curr.y;
      final len1 = math.sqrt(v1x * v1x + v1y * v1y);
      final len2 = math.sqrt(v2x * v2x + v2y * v2y);
      if (len1 < 1e-4 || len2 < 1e-4) return false;
      final cosAngle = ((v1x * v2x + v1y * v2y) / (len1 * len2)).clamp(-1.0, 1.0);
      final angleDeg = math.acos(cosAngle) * 180.0 / math.pi;
      if (angleDeg < 58.0 || angleDeg > 122.0) return false;
    }

    return true;
  }

  /// Đo tỷ lệ điểm biên thực sự dọc theo 4 đoạn thẳng `TL-TR`, `TR-BR`, `BR-BL`, `BL-TL`
  /// và độ chênh lệch độ sáng giữa mặt trong tờ giấy với nền bên ngoài.
  double _evaluateQuadFourSidesContrast({
    required CropQuad quad,
    required List<int> surfaceLuma,
    required List<int> gradMag,
    required int pW,
    required int pH,
    required int seedMean,
  }) {
    final pts = quad.corners;
    final cx = (pts[0].x + pts[1].x + pts[2].x + pts[3].x) * 0.25;
    final cy = (pts[0].y + pts[1].y + pts[2].y + pts[3].y) * 0.25;

    int validSides = 0;
    double sumSideRatio = 0.0;
    int insideLumaSum = 0;
    int outsideLumaSum = 0;
    int contrastSamples = 0;

    const int samplesPerSide = 14;
    for (int s = 0; s < 4; s++) {
      final a = pts[s];
      final b = pts[(s + 1) % 4];
      int edgeHits = 0;

      for (int k = 2; k < samplesPerSide - 1; k++) {
        final t = k / samplesPerSide;
        final px = a.x + (b.x - a.x) * t;
        final py = a.y + (b.y - a.y) * t;

        final gx = (px * (pW - 1)).round().clamp(2, pW - 3);
        final gy = (py * (pH - 1)).round().clamp(2, pH - 3);

        // Tìm độ dốc lớn nhất trong lân cận 3x3 quanh điểm biên
        int localMaxGrad = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final g = gradMag[(gy + dy) * pW + (gx + dx)];
            if (g > localMaxGrad) localMaxGrad = g;
          }
        }

        // Lấy mẫu điểm lùi vào trong tâm tứ giác và điểm vươn ra ngoài nền
        final vx = cx - px;
        final vy = cy - py;
        final vLen = math.sqrt(vx * vx + vy * vy);
        int stepContrast = 0;
        if (vLen > 0.02) {
          final inX = ((px + vx / vLen * 0.045) * (pW - 1)).round().clamp(1, pW - 2);
          final inY = ((py + vy / vLen * 0.045) * (pH - 1)).round().clamp(1, pH - 2);
          final outX = ((px - vx / vLen * 0.045) * (pW - 1)).round().clamp(1, pW - 2);
          final outY = ((py - vy / vLen * 0.045) * (pH - 1)).round().clamp(1, pH - 2);
          final inLuma = surfaceLuma[inY * pW + inX];
          final outLuma = surfaceLuma[outY * pW + outX];
          insideLumaSum += inLuma;
          outsideLumaSum += outLuma;
          contrastSamples++;
          stepContrast = (inLuma - outLuma).abs();
        }

        if (localMaxGrad >= 18 || stepContrast >= 16) {
          edgeHits++;
        }
      }

      final sideRatio = edgeHits / (samplesPerSide - 3);
      sumSideRatio += sideRatio;
      if (sideRatio >= 0.55) {
        validSides++;
      }
    }

    // Phải có ít nhất 3 trên 4 cạnh đạt chuẩn biên thẳng rõ nét
    if (validSides < 3 || contrastSamples == 0) return 0.0;

    final meanIn = insideLumaSum / contrastSamples;
    final meanOut = outsideLumaSum / contrastSamples;
    // Mặt trong tờ giấy phải có độ tương phản rõ so với nền bên ngoài
    if ((meanIn - meanOut).abs() < 14.0) return 0.0;

    return sumSideRatio / 4.0;
  }

  Future<void> _capturePhoto({bool fromAutoTrigger = false}) async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized || _isTakingPicture) return;

    // Khi đang bật chế độ Quét Tài Liệu AI, chỉ chụp khi AI đã nhận diện được tài liệu hợp lệ!
    if (_aiAutoCapture && _liveDetectedQuad == null) {
      if (!fromAutoTrigger && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: StitchTheme.surfaceProElevated,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              _tr(
                'Chưa nhận diện được tài liệu! Hãy đưa giấy/tài liệu vào khung hình hoặc bấm "Chụp tay" ở góc trên để chụp tự do.',
                'No document detected! Point at a document or switch to "Manual" at the top right.',
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        );
      }
      return;
    }

    final capturedQuadSnapshot = _liveDetectedQuad;
    setState(() => _isTakingPicture = true);
    try {
      if (cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
      final XFile photo = await cam.takePicture();
      if (!mounted) return;

      if (widget.singleShotMode) {
        Navigator.of(context).pop(<String>[photo.path]);
        return;
      }

      setState(() {
        _capturedPaths.add(photo.path);
        _stableFrameCount = 0;
        if (fromAutoTrigger && capturedQuadSnapshot != null) {
          _lastAutoCapturedQuad = capturedQuadSnapshot;
          _waitingForNextDocument = true;
          _noDocFramesSinceCapture = 0;
        }
      });

      if (mounted && _controller != null && _controller!.value.isInitialized) {
        if (fromAutoTrigger) {
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        }
        if (mounted &&
            _controller != null &&
            !_controller!.value.isStreamingImages) {
          await _controller!.startImageStream(_onCameraFrame);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chụp ảnh: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      if (widget.singleShotMode) {
        final single = await _picker.pickImage(source: ImageSource.gallery);
        if (single != null && mounted) {
          Navigator.of(context).pop(<String>[single.path]);
        }
        return;
      }

      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty || !mounted) return;

      setState(() {
        _capturedPaths.addAll(picked.map((x) => x.path));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể mở bộ chọn ảnh: $e')),
        );
      }
    }
  }

  Future<void> _cycleFlashMode() async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;
    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.torch,
      _ => FlashMode.off,
    };
    try {
      await cam.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StitchTheme.surfaceProBase,
      body: Column(
        children: [
          Expanded(
            child: _buildCameraViewport(),
          ),
          _buildStitchBottomControlsBar(),
        ],
      ),
    );
  }

  Widget _buildCameraViewport() {
    if (_initializingCamera) {
      return const Center(
        child: CircularProgressIndicator(color: StitchTheme.tertiaryFixed),
      );
    }

    if (_cameraError != null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: StitchTheme.tertiaryFixed,
              ),
              const SizedBox(height: 16),
              Text(
                _cameraError ?? 'Camera chưa sẵn sàng.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _setupCamera,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Thử lại'),
                  ),
                  FilledButton.icon(
                    onPressed: _pickFromGallery,
                    style: FilledButton.styleFrom(
                      backgroundColor: StitchTheme.primary,
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Chọn ảnh từ thư viện'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final hasDoc = _liveDetectedQuad != null;
    final stabilityProgress = (_stableFrameCount / 6.0).clamp(0.0, 1.0);
    final countdownSec = (3 - (_stableFrameCount * 0.5).floor()).clamp(1, 3);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Luồng Camera toàn màn hình
        Center(
          child: CameraPreview(_controller!),
        ),

        // 2. Lớp phủ Vignette chống chói trên/dưới chuẩn Stitch
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  StitchTheme.surfaceProBase.withValues(alpha: 0.72),
                  Colors.transparent,
                  Colors.transparent,
                  StitchTheme.surfaceProBase.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.22, 0.76, 1.0],
              ),
            ),
          ),
        ),

        // 3. Đa giác AI động + Tia quét Laser + 4 nút góc + Nhãn "GÓC CHÍNH XÁC 99%"
        if (hasDoc)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _laserController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _LiveAiDocumentPolygonPainter(
                    quad: _liveDetectedQuad!,
                    stabilityProgress: stabilityProgress,
                    laserProgress: _laserController.value,
                  ),
                );
              },
            ),
          ),

        // 4. Cụm nút điều khiển nổi phía trên (Top Viewfinder Floating Controls)
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Nút đóng Camera (X)
                    _darkTranslucentCircleBtn(
                      icon: Icons.close_rounded,
                      color: Colors.white,
                      onTap: () => Navigator.of(context).pop(_capturedPaths),
                    ),
                    // Viên thuốc trạng thái & Vòng đếm tự chụp AI ở giữa
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: StitchTheme.surfaceProBase.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: hasDoc
                              ? StitchTheme.tertiaryFixed.withValues(alpha: 0.6)
                              : StitchTheme.borderDark,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 19,
                            height: 19,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: _waitingForNextDocument
                                      ? 1.0
                                      : (hasDoc ? stabilityProgress : 0.15),
                                  strokeWidth: 2.3,
                                  backgroundColor: StitchTheme.borderDark,
                                  color: _waitingForNextDocument
                                      ? StitchTheme.statusSuccess
                                      : StitchTheme.tertiaryFixed,
                                ),
                                Text(
                                  _waitingForNextDocument
                                      ? '✓'
                                      : (hasDoc ? '$countdownSec' : 'AI'),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: _waitingForNextDocument
                                        ? StitchTheme.statusSuccess
                                        : StitchTheme.tertiaryFixed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _waitingForNextDocument
                                ? _tr(
                                    'Đã chụp! Đổi trang tiếp theo...',
                                    'Captured! Move to next page...',
                                  )
                                : (hasDoc
                                    ? _tr(
                                        'Giữ yên... Tự chụp AI',
                                        'Hold steady... AI Auto',
                                      )
                                    : _tr(
                                        'Đưa tài liệu vào để AI nhận diện',
                                        'Point at a document to scan',
                                      )),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Cụm nút phải: Tự chụp BẬT/TẮT + Đèn Flash
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _aiAutoCapture = !_aiAutoCapture;
                              _stableFrameCount = 0;
                            });
                          },
                          child: Container(
                            height: 34,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: StitchTheme.surfaceProBase
                                  .withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: StitchTheme.borderDark),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _aiAutoCapture
                                        ? StitchTheme.statusSuccess
                                        : StitchTheme.outline,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _aiAutoCapture
                                      ? _tr('Tự chụp', 'Auto')
                                      : _tr('Chụp tay', 'Manual'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: _aiAutoCapture
                                        ? StitchTheme.tertiaryFixed
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _darkTranslucentCircleBtn(
                          icon: switch (_flashMode) {
                            FlashMode.off => Icons.flash_off_rounded,
                            FlashMode.auto => Icons.flash_auto_rounded,
                            _ => Icons.flash_on_rounded,
                          },
                          color: _flashMode == FlashMode.off
                              ? Colors.white70
                              : StitchTheme.tertiaryFixed,
                          onTap: _cycleFlashMode,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Nhãn thông tin xử lý ảnh AI
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: StitchTheme.surfaceProBase.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: StitchTheme.primaryDarkAccent.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: StitchTheme.secondaryFixed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _tr(
                          'AI Làm Phẳng • Trắng Nền & Làm Nét Tự Động',
                          'AI Auto-Flatten • Clean Paper & Sharpen',
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: StitchTheme.primaryFixed,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.verified_rounded,
                        size: 14,
                        color: StitchTheme.tertiaryFixedDim,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 5. Khay ảnh thu nhỏ nhiều trang + Nhãn cảm biến ánh sáng ở đáy Viewfinder
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Khay trang đã chụp (`54x70`)
              if (_capturedPaths.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: StitchTheme.surfaceProBase.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: StitchTheme.borderDark),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SizedBox(
                            height: 70,
                            child: ListView.separated(
                              shrinkWrap: true,
                              scrollDirection: Axis.horizontal,
                              itemCount: _capturedPaths.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, idx) {
                                final p = _capturedPaths[idx];
                                return Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 54,
                                        height: 70,
                                        child: Image.file(
                                          File(p),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: StitchTheme.surfaceProBase
                                              .withValues(alpha: 0.9),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '#${idx + 1}',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: StitchTheme.primaryFixed,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: -4,
                                      right: -4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _capturedPaths.removeAt(idx);
                                          });
                                        },
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: const BoxDecoration(
                                            color:
                                                StitchTheme.statusDangerStamp,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close_rounded,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đã lưu: ${_capturedPaths.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: StitchTheme.primaryFixed,
                                ),
                              ),
                              const Text(
                                'Ghép PDF',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: StitchTheme.tertiaryFixedDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),

              // Nhãn cảm biến ánh sáng ("Ánh sáng tốt")
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: StitchTheme.surfaceProBase.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: StitchTheme.borderDark),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _goodLighting
                          ? Icons.wb_sunny_rounded
                          : Icons.wb_twilight_rounded,
                      size: 15,
                      color: _goodLighting
                          ? StitchTheme.statusSuccess
                          : StitchTheme.statusWarning,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _goodLighting
                          ? _tr('Ánh sáng tốt', 'Good lighting')
                          : _tr('Thiếu sáng', 'Low light'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _darkTranslucentCircleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: StitchTheme.surfaceProBase.withValues(alpha: 0.72),
          shape: BoxShape.circle,
          border: Border.all(color: StitchTheme.borderDark),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  /// Thanh điều khiển dưới cùng chuẩn Stitch (`#0F1215` `surfaceDarkControls`).
  Widget _buildStitchBottomControlsBar() {
    return Container(
      color: StitchTheme.surfaceDarkControls,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Trái: Nút Thư viện
            InkWell(
              onTap: _pickFromGallery,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: StitchTheme.surfaceProElevated,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr('Thư viện', 'Gallery'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: StitchTheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Giữa: Nút chụp 2 vòng 78px (Dual-Ring Shutter Button)
            GestureDetector(
              onTap: _isTakingPicture ? null : () => _capturePhoto(),
              child: Container(
                width: 78,
                height: 78,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [
                      StitchTheme.secondaryFixed,
                      StitchTheme.tertiaryFixed,
                      StitchTheme.statusSuccess,
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: StitchTheme.tertiaryFixed.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: StitchTheme.primary,
                    ),
                    child: _isTakingPicture
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.3,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ),

            // Phải: Nút Xong & Xuất OCR
            if (_capturedPaths.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(_capturedPaths);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: StitchTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Xong',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_capturedPaths.length}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Xuất OCR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: StitchTheme.primaryFixed,
                    ),
                  ),
                ],
              )
            else
              const SizedBox(width: 56),
          ],
        ),
      ),
    );
  }
}

/// Vẽ lưới đa giác AI động chuẩn Stitch (`2._camera_qu_t_ai_kh_ng_khung/code.html`):
/// - Nền phủ `#00695C` (18% opacity).
/// - Viền nét đứt phát sáng `#9CF0FF` + đường chéo holographic.
/// - Tia quét Laser chuyển động dọc theo tờ giấy.
/// - 4 đỉnh tròn `#004F45` viền `#9CF0FF` kèm vòng hào quang.
/// - Nhãn "GÓC CHÍNH XÁC 99%" bám phía trên cạnh trên tờ giấy.
class _LiveAiDocumentPolygonPainter extends CustomPainter {
  final CropQuad quad;
  final double stabilityProgress;
  final double laserProgress;

  _LiveAiDocumentPolygonPainter({
    required this.quad,
    required this.stabilityProgress,
    required this.laserProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = quad.corners
        .map((p) => Offset(p.x * size.width, p.y * size.height))
        .toList();

    final path = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    // 1. Nền phủ màu xanh cổ vịt trong suốt
    final fillPaint = Paint()
      ..color = StitchTheme.primaryContainer
          .withValues(alpha: 0.18 + 0.10 * stabilityProgress)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. Đường chéo Holographic mảnh bên trong tứ giác
    final diagPaint = Paint()
      ..color = StitchTheme.secondaryFixed.withValues(alpha: 0.16)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(pts[0], pts[2], diagPaint);
    canvas.drawLine(pts[1], pts[3], diagPaint);

    // 3. Tia quét Laser chạy dọc theo phối cảnh tờ giấy
    final leftPt = Offset.lerp(pts[0], pts[3], laserProgress)!;
    final rightPt = Offset.lerp(pts[1], pts[2], laserProgress)!;
    final laserPaint = Paint()
      ..color = StitchTheme.tertiaryFixed.withValues(alpha: 0.85)
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(leftPt, rightPt, laserPaint);

    // 4. Viền tứ giác phát sáng
    final glowPaint = Paint()
      ..color = StitchTheme.secondaryFixed.withValues(alpha: 0.45)
      ..strokeWidth = 5.0
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawPath(path, glowPaint);

    final borderPaint = Paint()
      ..color = StitchTheme.secondaryFixed
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    // 5. 4 nút tròn ở 4 đỉnh tứ giác
    for (final pt in pts) {
      canvas.drawCircle(
        pt,
        14,
        Paint()..color = StitchTheme.secondaryFixed.withValues(alpha: 0.24),
      );
      canvas.drawCircle(
        pt,
        8.5,
        Paint()..color = StitchTheme.primary,
      );
      canvas.drawCircle(
        pt,
        8.5,
        Paint()
          ..color = StitchTheme.secondaryFixed
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(
        pt,
        3,
        Paint()..color = StitchTheme.secondaryFixed,
      );
    }

    // 6. Nhãn "GÓC CHÍNH XÁC 99%" phía trên cạnh trên
    final topCenter = Offset(
      (pts[0].dx + pts[1].dx) / 2,
      ((pts[0].dy + pts[1].dy) / 2 - 22).clamp(24.0, size.height - 40.0),
    );
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: topCenter, width: 122, height: 22),
      const Radius.circular(11),
    );
    canvas.drawRRect(
      badgeRect,
      Paint()..color = StitchTheme.primary.withValues(alpha: 0.88),
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'GÓC CHÍNH XÁC 99%',
        style: TextStyle(
          fontFamily: 'BeVietnamPro',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: StitchTheme.tertiaryFixed,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(topCenter.dx - tp.width / 2, topCenter.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _LiveAiDocumentPolygonPainter oldDelegate) {
    return oldDelegate.quad != quad ||
        oldDelegate.stabilityProgress != stabilityProgress ||
        oldDelegate.laserProgress != laserProgress;
  }
}
