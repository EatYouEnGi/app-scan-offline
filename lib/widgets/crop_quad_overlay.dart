import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_models.dart';

/// Lớp phủ tương tác 4 góc cắt phối cảnh (Perspective Quad Cropper - Stitch Screen 5):
/// - Cho phép kéo từng góc độc lập với lưới phối cảnh 1/3 (rule-of-thirds).
/// - Kính lúp phóng đại tròn 2.5x (Circular Magnifier Loupe 86x86) căn chính xác tọa độ đỉnh đang kéo vào đúng tâm chữ thập.
class CropQuadOverlay extends StatefulWidget {
  final CropQuad quad;
  final ValueChanged<CropQuad> onChanged;
  final String? imagePath;
  final bool isVi;

  const CropQuadOverlay({
    super.key,
    required this.quad,
    required this.onChanged,
    this.imagePath,
    this.isVi = true,
  });

  @override
  State<CropQuadOverlay> createState() => _CropQuadOverlayState();
}

class _CropQuadOverlayState extends State<CropQuadOverlay> {
  int _activeCornerIndex = 0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final isValid = widget.quad.isValidQuad;
        final lineColor =
            isValid ? const Color(0xFF00DAF3) : Colors.redAccent;
        final activeCorner = widget.quad.corners[_activeCornerIndex];

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(
                  quad: widget.quad,
                  lineColor: lineColor,
                ),
              ),
            ),

            // Kính lúp phóng đại góc 2.5x (hiển thị chính xác điểm đang kéo tại tâm chữ thập)
            Positioned(
              left: activeCorner.x > 0.48 ? 8 : null,
              right: activeCorner.x <= 0.48 ? 8 : null,
              top: activeCorner.y < 0.32 ? null : 8,
              bottom: activeCorner.y < 0.32 ? 8 : null,
              child: _buildMagnifierLoupe(
                activeCorner: activeCorner,
                canvasWidth: width,
                canvasHeight: height,
                lineColor: lineColor,
              ),
            ),

            // 4 nút kéo góc (Corner Handles)
            ...List.generate(4, (index) {
              final corner = widget.quad.corners[index];
              final cx = corner.x * width;
              final cy = corner.y * height;
              const handleRadius = 26.0;
              final isSelected = _activeCornerIndex == index;

              return Positioned(
                left: cx - handleRadius,
                top: cy - handleRadius,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    setState(() => _activeCornerIndex = index);
                  },
                  onPanStart: (_) {
                    setState(() {
                      _activeCornerIndex = index;
                      _isDragging = true;
                    });
                  },
                  onPanUpdate: (details) {
                    final nx =
                        ((cx + details.delta.dx) / width).clamp(0.0, 1.0);
                    final ny =
                        ((cy + details.delta.dy) / height).clamp(0.0, 1.0);
                    setState(() => _activeCornerIndex = index);
                    widget.onChanged(
                      widget.quad.withCorner(index, NormalizedPoint(nx, ny)),
                    );
                  },
                  onPanEnd: (_) {
                    setState(() => _isDragging = false);
                  },
                  child: SizedBox(
                    width: handleRadius * 2,
                    height: handleRadius * 2,
                    child: Center(
                      child: Container(
                        width: isSelected && _isDragging ? 30 : 26,
                        height: isSelected && _isDragging ? 30 : 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00695C).withValues(alpha: 0.88),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: lineColor.withValues(alpha: 0.75),
                              blurRadius: isSelected ? 12 : 6,
                              spreadRadius: isSelected ? 1.5 : 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: lineColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildMagnifierLoupe({
    required NormalizedPoint activeCorner,
    required double canvasWidth,
    required double canvasHeight,
    required Color lineColor,
  }) {
    final imgFile =
        widget.imagePath != null ? File(widget.imagePath!) : null;
    final hasImage = imgFile != null && imgFile.existsSync();
    const double loupeSize = 86.0;
    const double zoom = 2.5;

    // Dịch chuyển ảnh đã phóng to sao cho tọa độ (activeCorner.x * canvasWidth, activeCorner.y * canvasHeight)
    // nằm chính xác tại tâm kính lúp (loupeSize / 2, loupeSize / 2).
    final double offsetX =
        (loupeSize / 2.0) - (activeCorner.x * canvasWidth * zoom);
    final double offsetY =
        (loupeSize / 2.0) - (activeCorner.y * canvasHeight * zoom);

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: loupeSize,
            height: loupeSize,
            decoration: BoxDecoration(
              color: const Color(0xFF101316),
              shape: BoxShape.circle,
              border: Border.all(color: lineColor, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                     OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: canvasWidth * zoom,
                      maxWidth: canvasWidth * zoom,
                      minHeight: canvasHeight * zoom,
                      maxHeight: canvasHeight * zoom,
                      child: Transform.translate(
                        offset: Offset(offsetX, offsetY),
                        child: SizedBox(
                          width: canvasWidth * zoom,
                          height: canvasHeight * zoom,
                          child: Image.file(
                            imgFile,
                            fit: BoxFit.fill,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(color: const Color(0xFF101316)),
                  // Tâm ngắm chữ thập
                  CustomPaint(
                    painter: _LoupeCrosshairPainter(color: lineColor),
                  ),
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00695C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: lineColor.withValues(alpha: 0.6),
                ),
              ),
              child: Text(
                widget.isVi
                    ? 'Phóng đại 2.5x • Góc ${_activeCornerIndex + 1}'
                    : 'Zoom 2.5x • Corner ${_activeCornerIndex + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoupeCrosshairPainter extends CustomPainter {
  final Color color;

  _LoupeCrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.78)
      ..strokeWidth = 1.1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      p,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      p,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      3.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _LoupeCrosshairPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _QuadPainter extends CustomPainter {
  final CropQuad quad;
  final Color lineColor;

  _QuadPainter({
    required this.quad,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pts = quad.corners
        .map((p) => Offset(p.x * size.width, p.y * size.height))
        .toList();

    final quadPath = Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();

    final fullPath = Path()..addRect(Offset.zero & size);
    final maskPath =
        Path.combine(PathOperation.difference, fullPath, quadPath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );

    // Lớp phủ màu xanh ngọc mờ bên trong tứ giác
    canvas.drawPath(
      quadPath,
      Paint()
        ..color = const Color(0xFF00695C).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill,
    );

    // Lưới căn chỉnh phối cảnh 1/3 bên trong tứ giác
    final guidePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 2; i++) {
      final t = i / 3.0;
      final topPt = Offset.lerp(pts[0], pts[1], t)!;
      final bottomPt = Offset.lerp(pts[3], pts[2], t)!;
      canvas.drawLine(topPt, bottomPt, guidePaint);

      final leftPt = Offset.lerp(pts[0], pts[3], t)!;
      final rightPt = Offset.lerp(pts[1], pts[2], t)!;
      canvas.drawLine(leftPt, rightPt, guidePaint);
    }

    // Viền phát sáng ngoài
    canvas.drawPath(
      quadPath,
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Viền chính
    final borderPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    canvas.drawPath(quadPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) {
    return oldDelegate.quad != quad || oldDelegate.lineColor != lineColor;
  }
}
