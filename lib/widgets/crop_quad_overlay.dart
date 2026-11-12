import 'package:flutter/material.dart';
import '../models/scan_models.dart';

/// Lớp phủ tương tác 4 góc cắt phối cảnh (Perspective Quad Cropper).
/// Cho phép kéo từng góc độc lập, hiển thị đường nối tứ giác và cảnh báo nếu tứ giác bị tự cắt.
class CropQuadOverlay extends StatelessWidget {
  final CropQuad quad;
  final ValueChanged<CropQuad> onChanged;

  const CropQuadOverlay({
    super.key,
    required this.quad,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final isValid = quad.isValidQuad;
        final lineColor =
            isValid ? const Color(0xFF00E676) : Colors.redAccent;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(
                  quad: quad,
                  lineColor: lineColor,
                ),
              ),
            ),
            ...List.generate(4, (index) {
              final corner = quad.corners[index];
              final cx = corner.x * width;
              final cy = corner.y * height;
              const handleRadius = 22.0;

              return Positioned(
                left: cx - handleRadius,
                top: cy - handleRadius,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final nx = ((cx + details.delta.dx) / width).clamp(0.0, 1.0);
                    final ny =
                        ((cy + details.delta.dy) / height).clamp(0.0, 1.0);
                    onChanged(quad.withCorner(index, NormalizedPoint(nx, ny)));
                  },
                  child: Container(
                    width: handleRadius * 2,
                    height: handleRadius * 2,
                    alignment: Alignment.center,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: lineColor.withOpacity(0.28),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 2),
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
              );
            }),
          ],
        );
      },
    );
  }
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
    final maskPath = Path.combine(PathOperation.difference, fullPath, quadPath);

    canvas.drawPath(
      maskPath,
      Paint()..color = Colors.black.withOpacity(0.52),
    );

    // Vẽ lưới căn chỉnh bên trong tứ giác.
    final guidePaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
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

    final borderPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;

    canvas.drawPath(quadPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _QuadPainter oldDelegate) {
    return oldDelegate.quad != quad || oldDelegate.lineColor != lineColor;
  }
}

