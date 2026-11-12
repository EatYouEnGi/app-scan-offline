import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Hộp thoại vẽ chữ ký tay xuất ra ảnh PNG nền trong suốt (Giai đoạn 4).
class SignaturePadDialog extends StatefulWidget {
  const SignaturePadDialog({super.key});

  @override
  State<SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<SignaturePadDialog> {
  final List<List<Offset>> _strokes = [];
  Color _penColor = const Color(0xFF0D47A1);

  void _startStroke(Offset pt) {
    setState(() {
      _strokes.add([pt]);
    });
  }

  void _appendPoint(Offset pt) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.add(pt);
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
    });
  }

  Future<Uint8List?> _exportPng(Size canvasSize) async {
    if (_strokes.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()
      ..color = _penColor
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.width.round().clamp(100, 1200),
      canvasSize.height.round().clamp(60, 600),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    const padSize = Size(340, 190);
    return AlertDialog(
      title: const Text('Ký tên lên tài liệu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Dùng ngón tay hoặc bút cảm ứng ký vào khung bên dưới:',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _colorChoice(const Color(0xFF0D47A1), 'Mực xanh'),
              const SizedBox(width: 12),
              _colorChoice(const Color(0xFF111111), 'Mực đen'),
              const SizedBox(width: 12),
              _colorChoice(const Color(0xFFB71C1C), 'Mực đỏ'),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: padSize.width,
            height: padSize.height,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onPanStart: (d) => _startStroke(d.localPosition),
                onPanUpdate: (d) => _appendPoint(d.localPosition),
                child: CustomPaint(
                  size: padSize,
                  painter: _SignaturePainter(
                    strokes: _strokes,
                    penColor: _penColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _clear,
          child: const Text('Xóa ký lại'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _strokes.isEmpty
              ? null
              : () async {
                  final bytes = await _exportPng(padSize);
                  if (context.mounted) {
                    Navigator.of(context).pop(bytes);
                  }
                },
          icon: const Icon(Icons.check),
          label: const Text('Chèn chữ ký'),
        ),
      ],
    );
  }

  Widget _colorChoice(Color color, String tooltip) {
    final selected = _penColor.value == color.value;
    return InkWell(
      onTap: () => setState(() => _penColor = color),
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.amberAccent : Colors.white,
              width: selected ? 3 : 1.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color penColor;

  _SignaturePainter({
    required this.strokes,
    required this.penColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final baselineY = size.height * 0.78;
    canvas.drawLine(
      Offset(20, baselineY),
      Offset(size.width - 20, baselineY),
      Paint()
        ..color = Colors.grey.shade300
        ..strokeWidth = 1.0,
    );

    final paint = Paint()
      ..color = penColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

