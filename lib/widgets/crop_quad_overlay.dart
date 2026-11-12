import 'dart:io';
import 'package:flutter/material.dart';
import '../models/scan_models.dart';

/// Lớp phủ tương tác 4 góc cắt phối cảnh (Perspective Quad Cropper - Stitch Screen 5):
/// - Cho phép kéo từng góc độc lập với lưới phối cảnh 1/3 (rule-of-thirds).
/// - Kính lúp phóng đại tròn 2.5x (Circular Magnifier Loupe 86x86) kèm tâm ngắm chữ thập giúp đặt góc chính xác từng pixel.
class CropQuadOverlay extends StatefulWidget {
  final CropQuad quad;
  final ValueChanged<CropQuad> onChanged;
  final String? imagePath;

  const CropQuadOverlay({
    super.key,
    required this.quad,
    required this.onChanged,
    this.imagePath,
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

            // Kính lúp phóng đại góc 2.5x (Circular Magnifier Loupe - Stitch Screen 5)
            Positioned(
              left: activeCorner.x > 0.45 ? 10 : null,
              right: activeCorner.x <= 0.45 ? 10 : null,
              top: 10,
              child: _buildMagnifierLoupe(
                activeCorner: activeCorner,
                lineColor: lineColor,
              ),
            ),

            // 4 nút kéo góc (Corner Handles)
            ...List.generate(4, (index) {
              final corner = widget.quad.corners[index];
              final cx = corner.x * width;
              final cy = corner.y * height;
              const handleRadius = 24.0;
              final isSelected = _activeCornerIndex == index;

              return Positioned(
                left: cx - handleRadius,
                top: cy - handleRadius,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
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
    required Color lineColor,
  }) {
    final imgFile =
        widget.imagePath != null ? File(widget.imagePath!) : null;
    final hasImage = imgFile != null && imgFile.existsSync();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: const Color(0xFF1C2126),
            shape: BoxShape.circle,
            border: Border.all(color: lineColor, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
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
                  Transform.scale(
                    scale: 2.5,
                    alignment: Alignment(
                      (activeCorner.x * 2 - 1).clamp(-1.0, 1.0),
                      (activeCorner.y * 2 - 1).clamp(-1.0, 1.0),
                    ),
                    child: Image.file(
                      imgFile,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Container(color: const Color(0xFF101316)),
                // Crosshair reticle
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
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF00695C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: lineColor.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              'Phóng đại 2.5x • Góc ${_activeCornerIndex + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoupeCrosshairPainter extends CustomPainter {
  final Color color;

  _LoupeCrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.0;
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
      4,
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
