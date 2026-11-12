import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_models.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import '../widgets/crop_quad_overlay.dart';
import '../widgets/signature_pad_dialog.dart';

/// Màn hình chỉnh sửa không phá hủy (non-destructive) một trang tài liệu (Stitch Screen 5):
/// - Nền Studio Dark (`#14171A`) kèm lưới chấm bi kỹ thuật (`#101316`).
/// - Thanh công cụ trợ giúp AI phía trên (`✨ AI Bắt Mép Tự Động`, `Toàn Trang`, `Khử Bóng & Nếp Gấp`, `🔒 Không phá hủy ảnh gốc`).
/// - Chỉnh 4 góc phối cảnh trực tiếp trên ảnh gốc (`originalImagePath`) kèm kính lúp phóng đại 2.5x.
/// - Xoay 90°, chọn bộ lọc màu (Gốc, Màu sắc nét, Thang xám, Trắng đen, Tương phản cao).
/// - Ký tên tay (Mực xanh) & Đóng dấu đỏ (`★ ĐÃ ĐỐI CHIẾU AI ★`) kéo thả trực tiếp trên trang.
class PageEditorScreen extends StatefulWidget {
  final AppState appState;
  final ScanPage initialPage;

  const PageEditorScreen({
    super.key,
    required this.appState,
    required this.initialPage,
  });

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  final Uuid _uuid = const Uuid();

  late ScanPage _page;
  late CropQuad _editingQuad;
  late int _rotationDegrees;
  late ScanFilterType _selectedFilter;
  late List<PageAnnotation> _annotations;

  bool _isCropMode = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _editingQuad = _page.cropQuad;
    _rotationDegrees = _page.rotationDegrees;
    _selectedFilter = _page.filter;
    _annotations = List<PageAnnotation>.from(_page.annotations);
  }

  Future<void> _autoDetectCorners() async {
    setState(() => _isSaving = true);
    try {
      final detected = await widget.appState.visionService
          .detectDocumentCorners(_page.originalImagePath);
      if (!mounted) return;
      setState(() {
        _editingQuad = detected;
        _isCropMode = true;
      });
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _applyChanges({bool closeAfterSave = false}) async {
    if (!_editingQuad.isValidQuad) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vùng chọn 4 góc bị tự cắt hoặc quá nhỏ. Vui lòng chỉnh lại 4 góc.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await widget.appState.updatePageTransform(
        page: _page,
        cropQuad: _editingQuad,
        rotationDegrees: _rotationDegrees,
        filter: _selectedFilter,
        annotations: _annotations,
        rerunOcr: true,
      );
      if (!mounted) return;
      setState(() {
        _page = updated;
        _isCropMode = false;
      });
      if (closeAfterSave) {
        Navigator.of(context).pop(updated);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã cập nhật trang & nhận dạng lại AI OCR (Ảnh gốc được giữ nguyên).',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openSignaturePad() async {
    final pngBytes = await showDialog<Uint8List?>(
      context: context,
      builder: (_) => const SignaturePadDialog(),
    );
    if (pngBytes == null || !mounted) return;

    final savedSigPath =
        await widget.appState.storageService.saveSignatureBytes(pngBytes);
    final newAnnotation = PageAnnotation(
      id: _uuid.v4(),
      kind: AnnotationKind.signature,
      x: 0.56,
      y: 0.74,
      width: 0.34,
      height: 0.13,
      imagePath: savedSigPath,
    );

    setState(() {
      _annotations.add(newAnnotation);
    });
  }

  Future<void> _openNoteDialog() async {
    final controller =
        TextEditingController(text: '★ ĐÃ ĐỐI CHIẾU AI ★');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đóng dấu / Thêm ghi chú'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nội dung con dấu đỏ',
                hintText: 'Ví dụ: ★ ĐÃ ĐỐI CHIẾU AI ★ / SAO Y BẢN CHÍNH',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                '★ ĐÃ ĐỐI CHIẾU AI ★',
                'SAO Y BẢN CHÍNH',
                'ĐÃ KÝ DUYỆT',
                'BẢO MẬT NỘI BỘ',
              ]
                  .map(
                    (preset) => ActionChip(
                      label: Text(
                        preset,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onPressed: () => controller.text = preset,
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Đóng dấu'),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _annotations.add(
        PageAnnotation(
          id: _uuid.v4(),
          kind: AnnotationKind.note,
          x: 0.08,
          y: 0.76,
          width: 0.44,
          height: 0.09,
          text: text,
          colorArgb: 0xFFDC2626,
        ),
      );
    });
  }

  void _showOcrSheet() {
    final textCtrl =
        TextEditingController(text: _page.ocrResult?.fullText ?? '');
    bool isEditing = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final currentText = textCtrl.text.trim();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.62,
              maxChildSize: 0.92,
              builder: (_, scrollController) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    4,
                    18,
                    MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'AI OCR Trang ${_page.pageIndex + 1}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              final updated = await widget.appState
                                  .rerunPageAiOcr(_page);
                              if (!mounted) return;
                              setState(() => _page = updated);
                              setSheetState(() {
                                textCtrl.text =
                                    updated.ocrResult?.fullText ?? '';
                              });
                            },
                            tooltip:
                                'Quét lại bằng AI OCR (Tiếng Việt & Chữ viết tay)',
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                          IconButton(
                            onPressed: () {
                              setSheetState(() => isEditing = !isEditing);
                            },
                            tooltip:
                                isEditing ? 'Xem văn bản' : 'Sửa văn bản',
                            icon: Icon(
                              isEditing
                                  ? Icons.visibility_outlined
                                  : Icons.edit_note_rounded,
                              size: 21,
                            ),
                          ),
                          IconButton(
                            onPressed: currentText.isEmpty
                                ? null
                                : () {
                                    Clipboard.setData(
                                      ClipboardData(text: currentText),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Đã sao chép văn bản OCR vào bộ nhớ tạm.',
                                        ),
                                      ),
                                    );
                                  },
                            tooltip: 'Sao chép',
                            icon: const Icon(Icons.copy_rounded, size: 19),
                          ),
                          IconButton(
                            onPressed: currentText.isEmpty
                                ? null
                                : () => widget.appState.shareOcrText(
                                      currentText,
                                      subject:
                                          'OCR Trang ${_page.pageIndex + 1}',
                                    ),
                            tooltip: 'Chia sẻ văn bản',
                            icon:
                                const Icon(Icons.ios_share_rounded, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: isEditing
                            ? TextField(
                                controller: textCtrl,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: InputDecoration(
                                  hintText:
                                      'Chỉnh sửa văn bản Tiếng Việt / chữ viết tay...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              )
                            : Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: SingleChildScrollView(
                                  controller: scrollController,
                                  child: SelectableText(
                                    currentText.isEmpty
                                        ? '(Chưa phát hiện văn bản trên trang này — bấm nút làm mới ↻ để quét lại bằng AI OCR)'
                                        : currentText,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      if (isEditing) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final updated = await widget.appState
                                  .updatePageOcrText(
                                page: _page,
                                editedText: textCtrl.text,
                              );
                              if (!mounted) return;
                              setState(() => _page = updated);
                              setSheetState(() => isEditing = false);
                            },
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Lưu văn bản đã chỉnh sửa'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StitchTheme.surfaceProEditor,
      appBar: AppBar(
        backgroundColor: StitchTheme.surfaceProElevated,
        foregroundColor: Colors.white,
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isCropMode
                  ? 'Chỉnh 4 góc & Phối cảnh'
                  : 'Chỉnh 4 góc & Ký tên',
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00DAF3),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Chế độ không phá hủy ảnh gốc • Trang ${_page.pageIndex + 1}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: StitchTheme.textDarkMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showOcrSheet,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              minimumSize: const Size(36, 36),
            ),
            tooltip: 'Văn bản AI OCR',
            icon: const Icon(
              Icons.auto_awesome_rounded,
              size: 18,
              color: Color(0xFF00DAF3),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed:
                  _isSaving ? null : () => _applyChanges(closeAfterSave: true),
              style: FilledButton.styleFrom(
                backgroundColor: StitchTheme.primaryContainer,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 17),
              label: const Text(
                'Lưu',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Sub-header Quick Assist Chips Strip
          _buildQuickAssistStrip(),

          // 2. Central Studio Dark Workstation Canvas (#101316 + Dot Grid)
          Expanded(
            child: Container(
              width: double.infinity,
              color: StitchTheme.surfaceProBase,
              child: CustomPaint(
                painter: _StudioDotGridPainter(),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Center(
                    child: _isCropMode
                        ? _buildCropCanvas()
                        : _buildProcessedPreviewWithAnnotations(),
                  ),
                ),
              ),
            ),
          ),

          // 3. Document Filter Strip (#1C2126)
          _buildFilterStrip(),

          // 4. 5-Column Bottom Action Toolbar (#101316)
          _buildBottomActionToolbar(),
        ],
      ),
    );
  }

  Widget _buildQuickAssistStrip() {
    return Container(
      width: double.infinity,
      color: StitchTheme.surfaceProEditor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildAssistChip(
              icon: Icons.auto_fix_high_rounded,
              label: 'AI Bắt Mép Tự Động',
              isHighlighted: true,
              onTap: _autoDetectCorners,
            ),
            const SizedBox(width: 8),
            _buildAssistChip(
              icon: Icons.crop_free_rounded,
              label: 'Toàn Trang',
              onTap: () {
                setState(() {
                  _editingQuad = CropQuad.fullPage();
                  _isCropMode = true;
                });
              },
            ),
            const SizedBox(width: 8),
            _buildAssistChip(
              icon: Icons.wb_twilight_rounded,
              label: 'Khử Bóng & Nếp Gấp',
              onTap: () {
                setState(() => _selectedFilter = ScanFilterType.magicColor);
                _applyChanges();
              },
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: Color(0xFF34D399),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Không phá hủy ảnh gốc',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: StitchTheme.textDarkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistChip({
    required IconData icon,
    required String label,
    bool isHighlighted = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isHighlighted
              ? StitchTheme.primaryContainer.withValues(alpha: 0.32)
              : StitchTheme.surfaceProElevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isHighlighted
                ? const Color(0xFF00DAF3).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isHighlighted ? const Color(0xFF00DAF3) : Colors.white70,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight:
                    isHighlighted ? FontWeight.w700 : FontWeight.w500,
                color: isHighlighted
                    ? const Color(0xFF9CF0FF)
                    : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Chế độ cắt 4 góc hiển thị trên `originalImagePath` (không phá hủy ảnh gốc).
  Widget _buildCropCanvas() {
    final origFile = File(_page.originalImagePath);
    if (!origFile.existsSync()) {
      return const Text(
        'Không tìm thấy ảnh gốc.',
        style: TextStyle(color: Colors.white),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      origFile,
                      fit: BoxFit.fill,
                    ),
                  ),
                  CropQuadOverlay(
                    quad: _editingQuad,
                    imagePath: _page.originalImagePath,
                    onChanged: (newQuad) {
                      setState(() => _editingQuad = newQuad);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => _isCropMode = false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Hủy cắt'),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _applyChanges(),
              style: FilledButton.styleFrom(
                backgroundColor: StitchTheme.primaryDarkAccent,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('Áp dụng 4 góc'),
            ),
          ],
        ),
      ],
    );
  }

  /// Chế độ xem ảnh đã xử lý kèm kéo thả vị trí chữ ký và con dấu đỏ.
  Widget _buildProcessedPreviewWithAnnotations() {
    final displayFile = File(_page.displayImagePath);
    if (!displayFile.existsSync()) {
      return const Text(
        'Không tìm thấy tệp ảnh hiển thị.',
        style: TextStyle(color: Colors.white),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Image.file(
                displayFile,
                key: ValueKey(_page.displayImagePath),
                fit: BoxFit.contain,
              ),
            ),
            ...List.generate(_annotations.length, (idx) {
              final ann = _annotations[idx];
              final left = (ann.x * w).clamp(0.0, w - 80);
              final top = (ann.y * h).clamp(0.0, h - 50);

              return Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    final nx = ((left + d.delta.dx) / w).clamp(0.02, 0.85);
                    final ny = ((top + d.delta.dy) / h).clamp(0.02, 0.88);
                    setState(() {
                      _annotations[idx] = ann.copyWith(x: nx, y: ny);
                    });
                  },
                  onLongPress: () {
                    setState(() {
                      _annotations.removeAt(idx);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã xóa chữ ký / con dấu.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: _buildAnnotationWidget(ann, w, idx),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildAnnotationWidget(
    PageAnnotation ann,
    double containerWidth,
    int index,
  ) {
    if (ann.kind == AnnotationKind.signature && ann.imagePath != null) {
      final sigFile = File(ann.imagePath!);
      if (sigFile.existsSync()) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: (containerWidth * ann.width).clamp(110.0, 220.0),
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              decoration: BoxDecoration(
                color: const Color(0xFF00695C).withValues(alpha: 0.08),
                border: Border.all(
                  color: const Color(0xFF00DAF3),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.file(sigFile, fit: BoxFit.contain),
            ),
            Positioned(
              top: -9,
              left: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: StitchTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Chữ ký tay • Mực xanh',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: GestureDetector(
                onTap: () {
                  setState(() => _annotations.removeAt(index));
                },
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
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
      }
    }

    // Con dấu đỏ chứng thực 2 lớp viền chuẩn Stitch Screen 5
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Transform.rotate(
          angle: -0.14,
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              border: Border.all(color: Color(ann.colorArgb), width: 2.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Color(ann.colorArgb).withValues(alpha: 0.65),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ann.text ?? '★ ĐÃ ĐỐI CHIẾU AI ★',
                    style: TextStyle(
                      color: Color(ann.colorArgb),
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    'SAO Y BẢN CHÍNH',
                    style: TextStyle(
                      color: Color(ann.colorArgb).withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: GestureDetector(
            onTap: () {
              setState(() => _annotations.removeAt(index));
            },
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
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
  }

  Widget _buildFilterStrip() {
    return Container(
      color: StitchTheme.surfaceProElevated,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'BỘ LỌC MÀU TÀI LIỆU',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: StitchTheme.textDarkMuted,
                ),
              ),
              Text(
                'Đang dùng: ${_selectedFilter.label}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00DAF3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ScanFilterType.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = ScanFilterType.values[index];
                final selected = _selectedFilter == filter;
                return GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () {
                          if (selected) return;
                          setState(() => _selectedFilter = filter);
                          _applyChanges();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? StitchTheme.primaryDarkAccent
                          : StitchTheme.surfaceProEditor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF5FFBD6)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected) ...[
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: StitchTheme.surfaceProBase,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _toolbarButton(
                icon: _isCropMode ? Icons.image_outlined : Icons.crop_rounded,
                label: _isCropMode ? 'Xem trang' : 'Cắt 4 góc',
                active: _isCropMode,
                onTap: () => setState(() => _isCropMode = !_isCropMode),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.rotate_90_degrees_cw_outlined,
                label: 'Xoay 90°',
                onTap: _isSaving
                    ? null
                    : () {
                        setState(() {
                          _rotationDegrees = (_rotationDegrees + 90) % 360;
                        });
                        _applyChanges();
                      },
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.draw_rounded,
                label: 'Ký tên',
                hasBadgeDot: true,
                onTap: _openSignaturePad,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.approval_rounded,
                label: 'Đóng dấu',
                onTap: _openNoteDialog,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.document_scanner_rounded,
                label: 'AI OCR',
                onTap: _showOcrSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    bool active = false,
    bool hasBadgeDot = false,
    VoidCallback? onTap,
  }) {
    final fgColor = active ? const Color(0xFF00DAF3) : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? StitchTheme.primaryContainer.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: active
              ? Border.all(
                  color: const Color(0xFF00DAF3).withValues(alpha: 0.4),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: fgColor, size: 21),
                if (hasBadgeDot)
                  Positioned(
                    top: -2,
                    right: -3,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00DAF3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : fgColor,
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudioDotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    const step = 20.0;
    for (double x = 10; x < size.width; x += step) {
      for (double y = 10; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
