import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_models.dart';
import '../state/app_state.dart';
import '../widgets/crop_quad_overlay.dart';
import '../widgets/signature_pad_dialog.dart';

/// Màn hình chỉnh sửa không phá hủy (non-destructive) một trang tài liệu:
/// - Chỉnh 4 góc phối cảnh trực tiếp trên ảnh gốc (`originalImagePath`).
/// - Xoay 90°, chọn bộ lọc (Gốc, Màu sắc nét, Thang xám, Trắng đen, Tương phản cao).
/// - Ký tên tay / chèn ghi chú lên trang.
/// - Xem, chỉnh sửa, quét lại AI OCR (Tiếng Việt & Chữ viết tay) và chia sẻ văn bản OCR.
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
      x: 0.58,
      y: 0.78,
      width: 0.30,
      height: 0.12,
      imagePath: savedSigPath,
    );

    setState(() {
      _annotations.add(newAnnotation);
    });
  }

  Future<void> _openNoteDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm ghi chú / con dấu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ví dụ: ĐÃ ĐỐI CHIẾU / SAO Y BẢN CHÍNH',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Thêm'),
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
          x: 0.15,
          y: 0.82,
          width: 0.45,
          height: 0.08,
          text: text,
          colorArgb: 0xFFB71C1C,
        ),
      );
    });
  }

  void _showOcrSheet() {
    final textCtrl = TextEditingController(text: _page.ocrResult?.fullText ?? '');
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
                              final updated =
                                  await widget.appState.rerunPageAiOcr(_page);
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
                            tooltip: isEditing ? 'Xem văn bản' : 'Sửa văn bản',
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
                                      subject: 'OCR Trang ${_page.pageIndex + 1}',
                                    ),
                            tooltip: 'Chia sẻ văn bản',
                            icon: const Icon(Icons.ios_share_rounded, size: 19),
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
      backgroundColor: const Color(0xFF14171A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C2126),
        foregroundColor: Colors.white,
        title: Text(
          _isCropMode
              ? 'Chỉnh 4 góc & Phối cảnh'
              : 'Trang ${_page.pageIndex + 1}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _showOcrSheet,
            tooltip: 'Văn bản AI OCR',
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              onPressed:
                  _isSaving ? null : () => _applyChanges(closeAfterSave: true),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: const Text('Lưu'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Center(
                child: _isCropMode
                    ? _buildCropCanvas()
                    : _buildProcessedPreviewWithAnnotations(),
              ),
            ),
          ),
          _buildFilterStrip(),
          _buildBottomActionToolbar(),
        ],
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
                  Image.file(
                    origFile,
                    fit: BoxFit.fill,
                  ),
                  CropQuadOverlay(
                    quad: _editingQuad,
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
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _autoDetectCorners,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
              label: const Text('AI bắt mép giấy'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _editingQuad = CropQuad.fullPage());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.crop_free_rounded, size: 17),
              label: const Text('Toàn trang'),
            ),
            FilledButton.tonal(
              onPressed: _isSaving ? null : () => _applyChanges(),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      ],
    );
  }

  /// Chế độ xem ảnh đã xử lý kèm kéo thả vị trí chữ ký và ghi chú.
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
              final left = (ann.x * w).clamp(0.0, w - 60);
              final top = (ann.y * h).clamp(0.0, h - 40);

              return Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    final nx = ((left + d.delta.dx) / w).clamp(0.02, 0.88);
                    final ny = ((top + d.delta.dy) / h).clamp(0.02, 0.90);
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
                        content: Text('Đã xóa chữ ký / ghi chú.'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: _buildAnnotationWidget(ann, w),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildAnnotationWidget(PageAnnotation ann, double containerWidth) {
    if (ann.kind == AnnotationKind.signature && ann.imagePath != null) {
      final sigFile = File(ann.imagePath!);
      if (sigFile.existsSync()) {
        return Container(
          width: containerWidth * ann.width,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.tealAccent.withOpacity(0.7)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Image.file(sigFile, fit: BoxFit.contain),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        border: Border.all(color: Color(ann.colorArgb), width: 1.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        ann.text ?? '',
        style: TextStyle(
          color: Color(ann.colorArgb),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildFilterStrip() {
    return Container(
      height: 56,
      color: const Color(0xFF1C2126),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: ScanFilterType.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = ScanFilterType.values[index];
          final selected = _selectedFilter == filter;
          return ChoiceChip(
            label: Text(filter.label, style: const TextStyle(fontSize: 12.5)),
            selected: selected,
            visualDensity: VisualDensity.compact,
            onSelected: _isSaving
                ? null
                : (val) {
                    if (!val) return;
                    setState(() => _selectedFilter = filter);
                    _applyChanges();
                  },
          );
        },
      ),
    );
  }

  Widget _buildBottomActionToolbar() {
    return Container(
      color: const Color(0xFF101316),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _toolbarButton(
              icon: _isCropMode ? Icons.image_outlined : Icons.crop_rounded,
              label: _isCropMode ? 'Xem trang' : 'Cắt 4 góc',
              active: _isCropMode,
              onTap: () => setState(() => _isCropMode = !_isCropMode),
            ),
            _toolbarButton(
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
            _toolbarButton(
              icon: Icons.draw_outlined,
              label: 'Ký tên',
              onTap: _openSignaturePad,
            ),
            _toolbarButton(
              icon: Icons.verified_outlined,
              label: 'Đóng dấu',
              onTap: _openNoteDialog,
            ),
            _toolbarButton(
              icon: Icons.auto_awesome_rounded,
              label: 'AI OCR',
              onTap: _showOcrSheet,
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
    VoidCallback? onTap,
  }) {
    final color = active ? Colors.tealAccent : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
