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
/// - Chỉnh 4 góc phối cảnh trực tiếp trên ảnh gốc (`originalImagePath`) theo đúng tỷ lệ ảnh thật kèm kính lúp phóng đại 2.5x.
/// - Ký tên tay & Đóng dấu đỏ kéo thả trực tiếp trên trang; khi kéo thả sẽ hiện vùng Thùng Rác (Drag-to-Delete Trash Zone) ở dưới để xóa dễ dàng thay vì nút (x) nhỏ.
/// - Hỗ trợ song ngữ Tiếng Việt & Tiếng Anh.
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
  double _imageAspectRatio = 0.72;

  // Trạng thái kéo thả Chữ ký / Con dấu vào thùng rác để xóa
  int? _draggingAnnotationIndex;
  bool _isHoveringTrash = false;

  String _tr(String vi, String en) => widget.appState.tr(vi, en);

  String _filterLabel(ScanFilterType filter) {
    if (widget.appState.isVi) return filter.label;
    switch (filter) {
      case ScanFilterType.original:
        return 'Original';
      case ScanFilterType.magicColor:
        return 'Magic Color';
      case ScanFilterType.grayscale:
        return 'Grayscale';
      case ScanFilterType.blackAndWhite:
        return 'B&W Clean';
      case ScanFilterType.highContrast:
        return 'High Contrast';
    }
  }

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    _editingQuad = _page.cropQuad;
    _rotationDegrees = _page.rotationDegrees;
    _selectedFilter = _page.filter;
    _annotations = List<PageAnnotation>.from(_page.annotations);
    _loadOriginalImageAspectRatio();
  }

  Future<void> _loadOriginalImageAspectRatio() async {
    final dims = await widget.appState.visionService
        .getOrientedImageDimensions(_page.originalImagePath);
    if (dims != null && dims.height > 0 && mounted) {
      setState(() {
        _imageAspectRatio = (dims.width / dims.height).clamp(0.45, 1.85);
      });
    }
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
        SnackBar(
          content: Text(
            _tr(
              'Vùng chọn 4 góc bị tự cắt hoặc quá nhỏ. Vui lòng chỉnh lại 4 góc.',
              'The 4-corner selection is self-intersecting or too small. Please adjust the 4 corners.',
            ),
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
          SnackBar(
            content: Text(
              _tr(
                'Đã cập nhật trang & nhận dạng lại AI OCR (Ảnh gốc được giữ nguyên).',
                'Page updated & AI OCR re-evaluated (Original image preserved).',
              ),
            ),
            duration: const Duration(seconds: 2),
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
      x: 0.52,
      y: 0.66,
      width: 0.34,
      height: 0.13,
      imagePath: savedSigPath,
    );

    setState(() {
      _isCropMode = false;
      _annotations.add(newAnnotation);
    });
  }

  Future<void> _openNoteDialog() async {
    final defaultStamp =
        _tr('★ ĐÃ ĐỐI CHIẾU AI ★', '★ AI VERIFIED COPY ★');
    final controller = TextEditingController(text: defaultStamp);
    final presets = widget.appState.isVi
        ? [
            '★ ĐÃ ĐỐI CHIẾU AI ★',
            'SAO Y BẢN CHÍNH',
            'ĐÃ KÝ DUYỆT',
            'BẢO MẬT NỘI BỘ',
          ]
        : [
            '★ AI VERIFIED COPY ★',
            'CERTIFIED TRUE COPY',
            'APPROVED & SIGNED',
            'CONFIDENTIAL',
          ];

    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Đóng dấu / Thêm ghi chú', 'Add Stamp / Annotation')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _tr('Nội dung con dấu đỏ', 'Red stamp text'),
                hintText: defaultStamp,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: presets
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
            child: Text(_tr('Hủy', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(_tr('Đóng dấu', 'Apply Stamp')),
          ),
        ],
      ),
    );

    if (text == null || text.isEmpty || !mounted) return;
    setState(() {
      _isCropMode = false;
      _annotations.add(
        PageAnnotation(
          id: _uuid.v4(),
          kind: AnnotationKind.note,
          x: 0.12,
          y: 0.68,
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
                              _tr(
                                'AI OCR Trang ${_page.pageIndex + 1}',
                                'AI OCR Page ${_page.pageIndex + 1}',
                              ),
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
                            tooltip: _tr(
                              'Quét lại bằng AI OCR',
                              'Re-run AI OCR',
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                          IconButton(
                            onPressed: () {
                              setSheetState(() => isEditing = !isEditing);
                            },
                            tooltip: isEditing
                                ? _tr('Xem văn bản', 'View text')
                                : _tr('Sửa văn bản', 'Edit text'),
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
                                      SnackBar(
                                        content: Text(
                                          _tr(
                                            'Đã sao chép văn bản OCR vào bộ nhớ tạm.',
                                            'Copied OCR text to clipboard.',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                            tooltip: _tr('Sao chép', 'Copy'),
                            icon: const Icon(Icons.copy_rounded, size: 19),
                          ),
                          IconButton(
                            onPressed: currentText.isEmpty
                                ? null
                                : () => widget.appState.shareOcrText(
                                      currentText,
                                      subject: _tr(
                                        'OCR Trang ${_page.pageIndex + 1}',
                                        'OCR Page ${_page.pageIndex + 1}',
                                      ),
                                    ),
                            tooltip: _tr('Chia sẻ văn bản', 'Share text'),
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
                                  hintText: _tr(
                                    'Chỉnh sửa văn bản Tiếng Việt / chữ viết tay...',
                                    'Edit recognized text...',
                                  ),
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
                                        ? _tr(
                                            '(Chưa phát hiện văn bản trên trang này — bấm nút làm mới ↻ để quét lại bằng AI OCR)',
                                            '(No text detected on this page yet — tap ↻ to re-run AI OCR)',
                                          )
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
                            label: Text(
                              _tr('Lưu văn bản đã chỉnh sửa', 'Save edited text'),
                            ),
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
                  ? _tr('Chỉnh 4 góc & Phối cảnh', '4-Corner Perspective Crop')
                  : _tr('Chỉnh 4 góc & Ký tên', 'Crop, Sign & Stamp'),
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
                Flexible(
                  child: Text(
                    _tr(
                      'Chế độ không phá hủy ảnh gốc • Trang ${_page.pageIndex + 1}',
                      'Non-destructive mode • Page ${_page.pageIndex + 1}',
                    ),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: StitchTheme.textDarkMuted,
                    ),
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
            tooltip: _tr('Văn bản AI OCR', 'AI OCR Text'),
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
              label: Text(
                _tr('Lưu', 'Save'),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
              label: _tr('AI Bắt Mép Tự Động', 'AI Auto-Edge'),
              isHighlighted: true,
              onTap: _autoDetectCorners,
            ),
            const SizedBox(width: 8),
            _buildAssistChip(
              icon: Icons.crop_free_rounded,
              label: _tr('Toàn Trang', 'Full Page'),
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
              label: _tr('Khử Bóng & Nếp Gấp', 'Remove Shadows'),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: Color(0xFF34D399),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _tr('Không phá hủy ảnh gốc', 'Non-destructive'),
                    style: const TextStyle(
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

  /// Chế độ cắt 4 góc hiển thị đúng tỷ lệ ảnh gốc (`_imageAspectRatio`) kèm đệm viền 16px
  /// để 4 nút kéo góc luôn thông thoáng, dễ chạm.
  Widget _buildCropCanvas() {
    final origFile = File(_page.originalImagePath);
    if (!origFile.existsSync()) {
      return Text(
        _tr('Không tìm thấy ảnh gốc.', 'Original image not found.'),
        style: const TextStyle(color: Colors.white),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Center(
              child: AspectRatio(
                aspectRatio: _imageAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
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
                      isVi: widget.appState.isVi,
                      onChanged: (newQuad) {
                        setState(() => _editingQuad = newQuad);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
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
              label: Text(_tr('Hủy cắt', 'Cancel')),
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
              label: Text(_tr('Áp dụng 4 góc', 'Apply 4 Corners')),
            ),
          ],
        ),
      ],
    );
  }

  /// Chế độ xem ảnh đã xử lý kèm kéo thả vị trí chữ ký và con dấu đỏ.
  /// Khi kéo thả bất kỳ chữ ký hoặc con dấu nào, hiện vùng Thùng Rác (Drag-to-Delete Trash Bin)
  /// ở cạnh dưới để xóa cực nhạy và trực quan thay vì dấu (x) nhỏ.
  Widget _buildProcessedPreviewWithAnnotations() {
    final displayFile = File(_page.displayImagePath);
    if (!displayFile.existsSync()) {
      return Text(
        _tr('Không tìm thấy tệp ảnh hiển thị.', 'Processed image not found.'),
        style: const TextStyle(color: Colors.white),
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

            // Các lớp Chữ ký & Con dấu có thể kéo thả
            ...List.generate(_annotations.length, (idx) {
              final ann = _annotations[idx];
              final left = (ann.x * w).clamp(0.0, w - 80);
              final top = (ann.y * h).clamp(0.0, h - 50);
              final isBeingDragged = _draggingAnnotationIndex == idx;

              return Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanStart: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _draggingAnnotationIndex = idx;
                      _isHoveringTrash = false;
                    });
                  },
                  onPanUpdate: (d) {
                    final nx = ((left + d.delta.dx) / w).clamp(0.02, 0.85);
                    final ny = ((top + d.delta.dy) / h).clamp(0.02, 0.90);
                    // Kiểm tra nếu kéo xuống vùng Thùng Rác ở đáy canvas (ny >= 0.78 và nằm gần giữa)
                    final nowHoveringTrash =
                        ny >= 0.76 && nx >= 0.15 && nx <= 0.75;
                    if (nowHoveringTrash != _isHoveringTrash) {
                      HapticFeedback.lightImpact();
                    }
                    setState(() {
                      _annotations[idx] = ann.copyWith(x: nx, y: ny);
                      _isHoveringTrash = nowHoveringTrash;
                    });
                  },
                  onPanEnd: (_) {
                    if (_isHoveringTrash &&
                        _draggingAnnotationIndex != null &&
                        _draggingAnnotationIndex! < _annotations.length) {
                      final removedKind =
                          _annotations[_draggingAnnotationIndex!].kind;
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _annotations.removeAt(_draggingAnnotationIndex!);
                        _draggingAnnotationIndex = null;
                        _isHoveringTrash = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            removedKind == AnnotationKind.signature
                                ? _tr('Đã xóa chữ ký.', 'Signature deleted.')
                                : _tr('Đã xóa con dấu.', 'Stamp deleted.'),
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    } else {
                      setState(() {
                        _draggingAnnotationIndex = null;
                        _isHoveringTrash = false;
                      });
                    }
                  },
                  onPanCancel: () {
                    setState(() {
                      _draggingAnnotationIndex = null;
                      _isHoveringTrash = false;
                    });
                  },
                  child: AnimatedScale(
                    scale: isBeingDragged
                        ? (_isHoveringTrash ? 0.82 : 1.06)
                        : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: AnimatedOpacity(
                      opacity: isBeingDragged && _isHoveringTrash ? 0.65 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: _buildAnnotationWidget(ann, w, isBeingDragged),
                    ),
                  ),
                ),
              );
            }),

            // Vùng Thùng Rác Xóa (chỉ hiện lên khi đang kéo Chữ ký hoặc Con dấu)
            if (_draggingAnnotationIndex != null)
              Positioned(
                bottom: 8,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: EdgeInsets.symmetric(
                    horizontal: _isHoveringTrash ? 24 : 18,
                    vertical: _isHoveringTrash ? 13 : 10,
                  ),
                  decoration: BoxDecoration(
                    color: _isHoveringTrash
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF1C2126).withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _isHoveringTrash
                          ? Colors.white
                          : const Color(0xFFEF4444).withValues(alpha: 0.75),
                      width: _isHoveringTrash ? 2.2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isHoveringTrash
                                ? const Color(0xFFEF4444)
                                : Colors.black)
                            .withValues(alpha: 0.45),
                        blurRadius: _isHoveringTrash ? 20 : 12,
                        spreadRadius: _isHoveringTrash ? 2 : 0,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isHoveringTrash
                            ? Icons.delete_forever_rounded
                            : Icons.delete_outline_rounded,
                        color: Colors.white,
                        size: _isHoveringTrash ? 24 : 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isHoveringTrash
                            ? _tr('Thả tay để xóa ngay', 'Release to delete')
                            : _tr(
                                'Kéo vào thùng rác để xóa',
                                'Drag here to delete',
                              ),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isHoveringTrash ? 13 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildAnnotationWidget(
    PageAnnotation ann,
    double containerWidth,
    bool isBeingDragged,
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
                  color: isBeingDragged
                      ? const Color(0xFF5FFBD6)
                      : const Color(0xFF00DAF3),
                  width: isBeingDragged ? 2.0 : 1.5,
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
                child: Text(
                  _tr('Chữ ký tay • Kéo để di chuyển', 'Signature • Drag to move'),
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

    // Con dấu đỏ chứng thực 2 lớp viền chuẩn Stitch Screen 5 (không có nút x nhỏ)
    return Transform.rotate(
      angle: -0.14,
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(
            color: Color(ann.colorArgb),
            width: isBeingDragged ? 2.6 : 2.2,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                ann.text ?? _tr('★ ĐÃ ĐỐI CHIẾU AI ★', '★ AI VERIFIED ★'),
                style: TextStyle(
                  color: Color(ann.colorArgb),
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                _tr('SAO Y BẢN CHÍNH', 'CERTIFIED COPY'),
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
              Text(
                _tr('BỘ LỌC MÀU TÀI LIỆU', 'DOCUMENT COLOR FILTERS'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: StitchTheme.textDarkMuted,
                ),
              ),
              Text(
                '${_tr('Đang dùng', 'Active')}: ${_filterLabel(_selectedFilter)}',
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
                          _filterLabel(filter),
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
                label: _isCropMode
                    ? _tr('Xem trang', 'Preview')
                    : _tr('Cắt 4 góc', 'Crop 4-Pt'),
                active: _isCropMode,
                onTap: () => setState(() => _isCropMode = !_isCropMode),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.rotate_90_degrees_cw_outlined,
                label: _tr('Xoay 90°', 'Rotate 90°'),
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
                label: _tr('Ký tên', 'Sign'),
                hasBadgeDot: true,
                onTap: _openSignaturePad,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _toolbarButton(
                icon: Icons.approval_rounded,
                label: _tr('Đóng dấu', 'Stamp'),
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
