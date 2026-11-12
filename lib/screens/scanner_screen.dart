import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
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

  /// Phân tích trực tiếp luồng ảnh Camera (mỗi ~220ms) để tự động tìm 4 góc tờ giấy
  /// ở bất kỳ đâu trên màn hình mà không cần khung cố định.
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
        final prev = _liveDetectedQuad;
        final isSteady = prev != null && prev.similarityTo(detected) >= 0.94;
        setState(() {
          _liveDetectedQuad = prev != null
              ? _smoothQuad(prev, detected, 0.45)
              : detected;
          _stableFrameCount = isSteady ? (_stableFrameCount + 1) : 1;
        });

        // Khi AI thấy tờ giấy nằm ổn định liên tục ~5 nhịp (~1.1 giây) và bật chế độ AI Tự chụp -> Tự chụp!
        if (_aiAutoCapture && _stableFrameCount >= 5 && !_isTakingPicture) {
          _stableFrameCount = 0;
          _capturePhoto(fromAutoTrigger: true);
        }
      } else {
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

  /// Thuật toán AI Vision nhẹ chạy trực tiếp trên kênh độ sáng (Y-plane / BGRA)
  /// để bắt biên tờ giấy/tài liệu ở bất kỳ vị trí nào trong khung hình.
  CropQuad? _detectPaperQuadFromCameraImage(CameraImage image) {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final isBgra = image.format.group == ImageFormatGroup.bgra8888;
    const step = 8;

    final rawW = image.width;
    final rawH = image.height;
    final gW = rawW ~/ step;
    final gH = rawH ~/ step;
    if (gW < 16 || gH < 16) return null;

    final hist = List<int>.filled(256, 0);
    final grid = List<int>.filled(gW * gH, 0);

    for (int gy = 0; gy < gH; gy++) {
      final sy = gy * step;
      for (int gx = 0; gx < gW; gx++) {
        final sx = gx * step;
        final offset = sy * rowStride + (isBgra ? sx * 4 + 1 : sx);
        if (offset >= 0 && offset < bytes.length) {
          final luma = bytes[offset];
          grid[gy * gW + gx] = luma;
          hist[luma]++;
        }
      }
    }

    final total = gW * gH;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    final avgLuma = sum / total;
    _goodLighting = avgLuma >= 75;

    double sumB = 0;
    int wB = 0;
    double maxVar = 0;
    int threshold = 145;
    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (between > maxVar) {
        maxVar = between;
        threshold = t;
      }
    }
    threshold = threshold.clamp(85, 225);

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    NormalizedPoint? tl;
    NormalizedPoint? tr;
    NormalizedPoint? br;
    NormalizedPoint? bl;
    int paperCount = 0;
    int edgeCount = 0;

    final marginX = (gW * 0.05).round().clamp(2, 8);
    final marginY = (gH * 0.05).round().clamp(2, 8);

    for (int gy = marginY; gy < gH - marginY; gy++) {
      for (int gx = marginX; gx < gW - marginX; gx++) {
        final idx = gy * gW + gx;
        final v = grid[idx];
        if (v >= threshold) {
          paperCount++;
          final grad = (grid[idx + 1] - grid[idx - 1]).abs() +
              (grid[idx + gW] - grid[idx - gW]).abs();
          if (grad > 24) {
            edgeCount++;
            final double nx = Platform.isIOS
                ? gx / (gW - 1)
                : 1.0 - (gy / (gH - 1));
            final double ny = Platform.isIOS
                ? gy / (gH - 1)
                : gx / (gW - 1);

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
        }
      }
    }

    final ratio = paperCount / total;
    if (tl == null ||
        tr == null ||
        br == null ||
        bl == null ||
        edgeCount < 14 ||
        ratio < 0.08 ||
        ratio > 0.88) {
      return null;
    }

    final quad = CropQuad(
      topLeft: tl.clamp(),
      topRight: tr.clamp(),
      bottomRight: br.clamp(),
      bottomLeft: bl.clamp(),
    );
    return (quad.isValidQuad &&
            quad.normalizedArea >= 0.10 &&
            quad.normalizedArea <= 0.86)
        ? quad
        : null;
  }

  Future<void> _capturePhoto({bool fromAutoTrigger = false}) async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized || _isTakingPicture) return;

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
      });

      if (mounted && _controller != null && _controller!.value.isInitialized) {
        if (fromAutoTrigger) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
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

  /// Mở trình quét AI gốc của hệ điều hành (Google ML Kit Document Scanner / Apple VisionKit).
  Future<void> _switchToNativeOsAiScanner() async {
    try {
      await _stopStreamAndDispose();
      final result = await CunningDocumentScanner.scanDocuments(
        noOfPages: widget.singleShotMode ? 1 : 100,
        scannerSource: ScannerSource.cameraAndGallery,
        output: ScanOutput.images,
        androidScannerMode: AndroidScannerMode.full,
      );
      if (!mounted) return;
      if (result != null && result.images.isNotEmpty) {
        Navigator.of(context).pop(result.images.toList());
      } else {
        await _setupCamera();
      }
    } catch (_) {
      if (mounted) await _setupCamera();
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
    final stabilityProgress = (_stableFrameCount / 5.0).clamp(0.0, 1.0);
    final countdownSec = (3 - (_stableFrameCount * 0.6).floor()).clamp(1, 3);

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
                                  value: hasDoc ? stabilityProgress : 0.25,
                                  strokeWidth: 2.3,
                                  backgroundColor: StitchTheme.borderDark,
                                  color: StitchTheme.tertiaryFixed,
                                ),
                                Text(
                                  hasDoc ? '$countdownSec' : 'AI',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: StitchTheme.tertiaryFixed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasDoc
                                ? _tr('Giữ yên... Tự chụp AI', 'Hold steady... AI Auto')
                                : _tr('Hướng vào giấy để AI bắt mép', 'Point at document for AI edge'),
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
                // Nhãn nổi chuyển sang Trình quét AI gốc ("AI Tự Động Làm Phẳng & Khử Bóng Mờ")
                GestureDetector(
                  onTap: _switchToNativeOsAiScanner,
                  child: Container(
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
                            'AI Tự Động Làm Phẳng & Khử Bóng Mờ',
                            'AI Auto-Flatten & Shadow Removal',
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
              InkWell(
                onTap: _switchToNativeOsAiScanner,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: StitchTheme.primaryContainerDark,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: StitchTheme.tertiaryFixed,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _tr('AI Gốc', 'Native AI'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: StitchTheme.tertiaryFixed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
