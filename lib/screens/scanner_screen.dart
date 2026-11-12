import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Màn hình chụp tài liệu bằng Camera:
/// - Hỗ trợ chế độ Chụp tự động (Auto-scan khi giữ máy ổn định) và Chụp thủ công.
/// - Cho phép chọn nhiều ảnh từ thư viện hệ điều hành.
/// - Xử lý an toàn khi người dùng từ chối quyền Camera.
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
  bool _autoCaptureEnabled = false;
  bool _isTakingPicture = false;
  FlashMode _flashMode = FlashMode.off;

  Timer? _autoCaptureTimer;
  int _autoCountdown = 0;

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
    _autoCaptureTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
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
              'Không tìm thấy phần cứng Camera trên thiết bị này. Bạn vẫn có thể chọn ảnh tài liệu từ thư viện.';
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
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFlashMode(_flashMode);

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializingCamera = false;
      });

      if (_autoCaptureEnabled) {
        _startAutoCaptureCountdown();
      }
    } on CameraException catch (e) {
      if (!mounted) return;
      final isDenied = e.code.toLowerCase().contains('access') ||
          e.code.toLowerCase().contains('permission');
      setState(() {
        _initializingCamera = false;
        _cameraError = isDenied
            ? 'Quyền Camera đã bị từ chối. Vui lòng cấp quyền Camera trong Cài đặt hệ thống hoặc nhập ảnh từ thư viện.'
            : 'Không thể khởi động Camera (${e.description ?? e.code}).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializingCamera = false;
        _cameraError = 'Lỗi khởi tạo Camera: $e';
      });
    }
  }

  void _toggleAutoCapture(bool enabled) {
    setState(() {
      _autoCaptureEnabled = enabled;
    });
    if (enabled) {
      _startAutoCaptureCountdown();
    } else {
      _autoCaptureTimer?.cancel();
      setState(() => _autoCountdown = 0);
    }
  }

  void _startAutoCaptureCountdown() {
    _autoCaptureTimer?.cancel();
    if (!_autoCaptureEnabled ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    setState(() => _autoCountdown = 3);
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_autoCaptureEnabled) {
        timer.cancel();
        return;
      }
      if (_isTakingPicture) return;

      if (_autoCountdown > 1) {
        setState(() => _autoCountdown--);
      } else {
        timer.cancel();
        setState(() => _autoCountdown = 0);
        _capturePhoto(fromAutoTrigger: true);
      }
    });
  }

  Future<void> _capturePhoto({bool fromAutoTrigger = false}) async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized || _isTakingPicture) return;

    setState(() => _isTakingPicture = true);
    try {
      final XFile photo = await cam.takePicture();
      if (!mounted) return;

      if (widget.singleShotMode) {
        Navigator.of(context).pop(<String>[photo.path]);
        return;
      }

      setState(() {
        _capturedPaths.add(photo.path);
      });

      if (fromAutoTrigger && _autoCaptureEnabled && mounted) {
        // Nghỉ ngắn để người dùng lật sang trang tiếp theo khi quét tự động.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted && _autoCaptureEnabled) {
          _startAutoCaptureCountdown();
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.singleShotMode ? 'Chụp lại trang' : 'Quét tài liệu',
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          FilterChip(
            label: Text(
              _autoCaptureEnabled ? 'Tự động: BẬT' : 'Thủ công',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            selected: _autoCaptureEnabled,
            selectedColor: Colors.teal.shade700,
            backgroundColor: Colors.grey.shade800,
            checkmarkColor: Colors.white,
            onSelected: _toggleAutoCapture,
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _cycleFlashMode,
            tooltip: 'Đèn Flash',
            icon: Icon(
              switch (_flashMode) {
                FlashMode.off => Icons.flash_off,
                FlashMode.auto => Icons.flash_auto,
                _ => Icons.highlight,
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
              size: 64,
              color: Colors.amberAccent,
            ),
            const SizedBox(height: 16),
            Text(
              _cameraError ?? 'Camera chưa sẵn sàng.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
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
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử cấp quyền lại'),
                ),
                FilledButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh từ thư viện'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(_controller!),
        ),
        // Khung định vị mép tài liệu trực quan.
        IgnorePointer(
          child: CustomPaint(
            painter: _ScannerGuideOverlayPainter(
              isAutoMode: _autoCaptureEnabled,
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 20,
          right: 20,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _autoCaptureEnabled
                    ? (_autoCountdown > 0
                        ? 'Giữ êm máy — Tự động chụp sau $_autoCountdown giây...'
                        : 'Đang tự động nhận diện mép trang giấy...')
                    : 'Căn tài liệu vào khung xanh rồi bấm nút chụp',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      color: Colors.black87,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Nút chọn nhiều ảnh từ thư viện.
            IconButton.filledTonal(
              onPressed: _pickFromGallery,
              iconSize: 28,
              tooltip: 'Nhập ảnh từ thư viện',
              icon: const Icon(Icons.photo_library_outlined),
            ),

            // Nút chụp chính.
            GestureDetector(
              onTap: _isTakingPicture ? null : () => _capturePhoto(),
              child: Container(
                width: 74,
                height: 74,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _autoCaptureEnabled
                        ? Colors.tealAccent
                        : Colors.white,
                    width: 3.5,
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
                          Icons.camera_alt,
                          color: Colors.black87,
                          size: 30,
                        ),
                ),
              ),
            ),

            // Nút Hoàn tất phiên chụp nhiều trang.
            if (_capturedPaths.isNotEmpty)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(_capturedPaths);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.tealAccent.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: CircleAvatar(
                  radius: 13,
                  backgroundImage: FileImage(File(_capturedPaths.last)),
                ),
                label: Text('Xong (${_capturedPaths.length})'),
              )
            else
              const SizedBox(width: 88),
          ],
        ),
      ),
    );
  }
}

class _ScannerGuideOverlayPainter extends CustomPainter {
  final bool isAutoMode;

  _ScannerGuideOverlayPainter({required this.isAutoMode});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.82,
      height: size.height * 0.74,
    );

    final paint = Paint()
      ..color = isAutoMode ? Colors.tealAccent : Colors.white70
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerGuideOverlayPainter oldDelegate) {
    return oldDelegate.isAutoMode != isAutoMode;
  }
}

