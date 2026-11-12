import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/scan_models.dart';

/// Màn hình Camera AI Quét Tài Liệu:
/// - KHÔNG dùng khung vùng an toàn cố định.
/// - Tự động phát hiện tờ giấy/tài liệu ở bất kỳ vị trí nào trên ống kính theo thời gian thực
///   từ luồng YUV/BGRA của Camera, vẽ đa giác 4 góc bám sát mép giấy thật và tự chụp khi giữ êm.
/// - Tích hợp nút chuyển nhanh sang trình quét AI gốc của hệ điều hành (ML Kit / VisionKit).
class ScannerScreen extends StatefulWidget {
  final bool singleShotMode;

  const ScannerScreen({
    super.key,
    this.singleShotMode = false,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final ImagePicker _picker = ImagePicker();

  bool _initializingCamera = true;
  String? _cameraError;
  bool _aiAutoCapture = true;
  bool _isTakingPicture = false;
  bool _isAnalyzingFrame = false;
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
    _setupCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final step = 8;

    // Trên điện thoại cầm dọc (portrait), cảm biến camera thường xoay 90 độ.
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

    // Tính ngưỡng Otsu phân tách vùng giấy sáng.
    final total = gW * gH;
    double sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
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

    for (int gy = 1; gy < gH - 1; gy++) {
      for (int gx = 1; gx < gW - 1; gx++) {
        final idx = gy * gW + gx;
        final v = grid[idx];
        if (v >= threshold) {
          paperCount++;
          final grad = (grid[idx + 1] - grid[idx - 1]).abs() +
              (grid[idx + gW] - grid[idx - gW]).abs();
          if (grad > 22) {
            edgeCount++;
            // Chuyển tọa độ cảm biến ngang sang khung hiển thị dọc của điện thoại.
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
        ratio > 0.94) {
      return null;
    }

    final quad = CropQuad(
      topLeft: tl.clamp(),
      topRight: tr.clamp(),
      bottomRight: br.clamp(),
      bottomLeft: bl.clamp(),
    );
    return (quad.isValidQuad && quad.normalizedArea >= 0.08) ? quad : null;
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.singleShotMode ? 'Quét lại trang' : 'Camera AI Quét Tài Liệu',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _switchToNativeOsAiScanner,
            tooltip: 'Mở trình quét AI Hệ thống (ML Kit / VisionKit)',
            icon: const Icon(Icons.auto_awesome, color: Colors.amberAccent),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _aiAutoCapture = !_aiAutoCapture;
                _stableFrameCount = 0;
              });
            },
            tooltip: _aiAutoCapture ? 'Đang bật AI Tự chụp' : 'Chế độ chụp tay',
            icon: Icon(
              _aiAutoCapture ? Icons.motion_photos_auto : Icons.touch_app,
              color: _aiAutoCapture ? Colors.tealAccent : Colors.white70,
            ),
          ),
          IconButton(
            onPressed: _cycleFlashMode,
            tooltip: 'Đèn Flash',
            icon: Icon(
              switch (_flashMode) {
                FlashMode.off => Icons.flash_off_rounded,
                FlashMode.auto => Icons.flash_auto_rounded,
                _ => Icons.flashlight_on_rounded,
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildCameraViewport(),
          ),
          _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildCameraViewport() {
    if (_initializingCamera) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      );
    }

    if (_cameraError != null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 56,
              color: Colors.amberAccent,
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
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Chọn ảnh từ thư viện'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final hasDoc = _liveDetectedQuad != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(_controller!),
        ),

        // Vẽ đa giác AI động ôm sát mép tờ giấy thật (hoàn toàn KHÔNG có khung cố định).
        if (hasDoc)
          IgnorePointer(
            child: CustomPaint(
              painter: _LiveAiDocumentPolygonPainter(
                quad: _liveDetectedQuad!,
                stabilityProgress: (_stableFrameCount / 5.0).clamp(0.0, 1.0),
              ),
            ),
          ),

        // Nhãn trạng thái AI nhỏ gọn phía trên.
        Positioned(
          top: 14,
          left: 20,
          right: 20,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: hasDoc
                    ? Colors.teal.shade900.withOpacity(0.85)
                    : Colors.black54,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasDoc ? Colors.tealAccent : Colors.white24,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasDoc ? Icons.auto_awesome : Icons.radar_rounded,
                    size: 15,
                    color: hasDoc ? Colors.tealAccent : Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hasDoc
                          ? (_aiAutoCapture
                              ? 'AI đã bắt mép tài liệu — Giữ êm để tự chụp...'
                              : 'AI đã bắt mép tài liệu — Bấm nút chụp')
                          : 'Hướng camera vào trang giấy để AI tự nhận diện',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              onPressed: _pickFromGallery,
              iconSize: 24,
              tooltip: 'Nhập ảnh từ thư viện',
              icon: const Icon(Icons.photo_library_rounded),
            ),
            GestureDetector(
              onTap: _isTakingPicture ? null : () => _capturePhoto(),
              child: Container(
                width: 70,
                height: 70,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _liveDetectedQuad != null
                        ? Colors.tealAccent
                        : Colors.white,
                    width: 3,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isTakingPicture ? Colors.grey : Colors.white,
                  ),
                  child: _isTakingPicture
                      ? const Padding(
                          padding: EdgeInsets.all(18.0),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(
                          Icons.camera_rounded,
                          color: Colors.black87,
                          size: 30,
                        ),
                ),
              ),
            ),
            if (_capturedPaths.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(_capturedPaths);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: CircleAvatar(
                  radius: 12,
                  backgroundImage: FileImage(File(_capturedPaths.last)),
                ),
                label: Text('Xong (${_capturedPaths.length})'),
              )
            else
              const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}

/// Vẽ đa giác 4 góc ôm sát mép tờ giấy thật khi AI nhận diện được tài liệu.
class _LiveAiDocumentPolygonPainter extends CustomPainter {
  final CropQuad quad;
  final double stabilityProgress;

  _LiveAiDocumentPolygonPainter({
    required this.quad,
    required this.stabilityProgress,
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

    final fillPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.18 + 0.12 * stabilityProgress)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF00E676)
      ..strokeWidth = 3.0
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, borderPaint);

    for (final pt in pts) {
      canvas.drawCircle(pt, 6, Paint()..color = Colors.white);
      canvas.drawCircle(pt, 4, Paint()..color = const Color(0xFF00E676));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveAiDocumentPolygonPainter oldDelegate) {
    return oldDelegate.quad != quad ||
        oldDelegate.stabilityProgress != stabilityProgress;
  }
}
