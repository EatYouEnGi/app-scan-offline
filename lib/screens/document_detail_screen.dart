import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan_models.dart';
import '../state/app_state.dart';
import 'page_editor_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chi tiết tài liệu nhiều trang:
/// - Quản lý trang: thêm, xóa, kéo thả đổi thứ tự, chụp lại AI, chỉnh 4 góc/bộ lọc/chữ ký.
/// - Xem, chỉnh sửa, quét lại AI OCR tiếng Việt/chữ viết tay và tìm kiếm nội dung OCR.
/// - Xuất & chia sẻ đầy đủ qua các ứng dụng khác (PDF có lớp chữ tiếng Việt, bộ ảnh JPG, lưu thư mục máy, xem trước/in, chia sẻ văn bản OCR).
class DocumentDetailScreen extends StatefulWidget {
  final AppState appState;
  final ScanDocument initialDocument;

  const DocumentDetailScreen({
    super.key,
    required this.appState,
    required this.initialDocument,
  });

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final ImagePicker _picker = ImagePicker();
  late ScanDocument _doc;
  String _inDocOcrQuery = '';

  @override
  void initState() {
    super.initState();
    _doc = widget.initialDocument;
  }

  Future<void> _reloadDoc() async {
    final fresh = await widget.appState.databaseService.getDocumentById(_doc.id);
    if (fresh != null && mounted) {
      setState(() => _doc = fresh);
    }
  }

  Future<void> _scanMorePages() async {
    List<String>? captured = await widget.appState.launchNativeAiScanner(maxPages: 20);
    if (captured == null && mounted) {
      captured = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => const ScannerScreen(),
        ),
      );
    }
    if (captured == null || captured.isEmpty || !mounted) return;
    final updated = await widget.appState.addImagesToDocument(
      document: _doc,
      sourceImagePaths: captured,
    );
    if (mounted) {
      setState(() => _doc = updated);
    }
  }

  Future<void> _importMoreImagesFromGallery() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;
    final updated = await widget.appState.addImagesToDocument(
      document: _doc,
      sourceImagePaths: picked.map((e) => e.path).toList(),
    );
    if (mounted) {
      setState(() => _doc = updated);
    }
  }

  Future<void> _retakeSinglePage(ScanPage page) async {
    List<String>? captured = await widget.appState.launchNativeAiScanner(maxPages: 1);
    if (captured == null && mounted) {
      captured = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => const ScannerScreen(singleShotMode: true),
        ),
      );
    }
    if (captured == null || captured.isEmpty || !mounted) return;
    await widget.appState.retakePage(
      oldPage: page,
      newSourceImagePath: captured.first,
    );
    await _reloadDoc();
  }

  Future<void> _openPageEditor(ScanPage page) async {
    await Navigator.of(context).push<ScanPage>(
      MaterialPageRoute(
        builder: (_) => PageEditorScreen(
          appState: widget.appState,
          initialPage: page,
        ),
      ),
    );
    await _reloadDoc();
  }

  Future<void> _rerunPageAiOcr(ScanPage page) async {
    await widget.appState.rerunPageAiOcr(page);
    await _reloadDoc();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã nhận diện lại AI OCR (Tiếng Việt & Chữ viết tay) cho Trang ${page.pageIndex + 1}.',
          ),
        ),
      );
    }
  }

  Future<void> _editPageOcrDialog(ScanPage page) async {
    final ctrl = TextEditingController(text: page.ocrResult?.fullText ?? '');
    final savedText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chỉnh sửa văn bản OCR (Trang ${page.pageIndex + 1})'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Nhập hoặc chỉnh sửa văn bản OCR...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Lưu văn bản'),
          ),
        ],
      ),
    );
    if (savedText == null || !mounted) return;
    await widget.appState.updatePageOcrText(page: page, editedText: savedText);
    await _reloadDoc();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật văn bản OCR cho trang.'),
        ),
      );
    }
  }

  Future<void> _editMetadataDialog() async {
    final titleCtrl = TextEditingController(text: _doc.title);
    final tagsCtrl = TextEditingController(text: _doc.tags.join(', '));
    String selectedFolder = _doc.folder;
    final folders = widget.appState.availableFolders;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Thông tin & Thẻ tài liệu'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên tài liệu',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: folders.contains(selectedFolder)
                          ? selectedFolder
                          : folders.first,
                      decoration: const InputDecoration(
                        labelText: 'Thư mục',
                        border: OutlineInputBorder(),
                      ),
                      items: folders
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedFolder = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: tagsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Thẻ (cách nhau bằng dấu phẩy)',
                        hintText: 'Ví dụ: Hóa đơn, Thuế 2026, Quan trọng',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Lưu thay đổi'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;
    final parsedTags = tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final updated = await widget.appState.updateDocumentMetadata(
      doc: _doc,
      title: titleCtrl.text,
      folder: selectedFolder,
      tags: parsedTags,
    );
    if (mounted) {
      setState(() => _doc = updated);
    }
  }

  Future<void> _showExportModal() async {
    PaperSizePreset selectedPaper = PaperSizePreset.a4;
    PdfQualityPreset selectedQuality = PdfQualityPreset.medium;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.ios_share_rounded,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Xuất & Chia sẻ tài liệu (${_doc.pageCount} trang)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Text(
                                'Hỗ trợ chia sẻ sang Zalo, Gmail, Messenger, Drive, AirDrop hoặc lưu vào máy',
                                style: TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<PaperSizePreset>(
                            value: selectedPaper,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Khổ giấy PDF',
                              border: OutlineInputBorder(),
                            ),
                            items: PaperSizePreset.values
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                      p.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setSheetState(() => selectedPaper = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<PdfQualityPreset>(
                            value: selectedQuality,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Chất lượng PDF',
                              border: OutlineInputBorder(),
                            ),
                            items: PdfQualityPreset.values
                                .map(
                                  (q) => DropdownMenuItem(
                                    value: q,
                                    child: Text(
                                      q.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setSheetState(() => selectedQuality = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await widget.appState.exportSearchablePdf(
                            document: _doc,
                            paperSize: selectedPaper,
                            quality: selectedQuality,
                            openShareSheet: true,
                          );
                          await _reloadDoc();
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(Icons.share_rounded, size: 20),
                        label: const Text(
                          'Chia sẻ file PDF qua ứng dụng khác (Zalo, Gmail...)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              final savedPath = await widget.appState
                                  .savePdfToDeviceFolder(
                                document: _doc,
                                paperSize: selectedPaper,
                                quality: selectedQuality,
                              );
                              await _reloadDoc();
                              if (savedPath != null && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Đã lưu PDF vào máy: $savedPath'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Lưu PDF vào máy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await widget.appState.previewAndPrintPdf(
                                document: _doc,
                                paperSize: selectedPaper,
                                quality: selectedQuality,
                              );
                            },
                            icon: const Icon(Icons.print_outlined, size: 18),
                            label: const Text('Xem & In PDF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await widget.appState.shareDocumentImages(_doc);
                            },
                            icon: const Icon(Icons.collections_outlined, size: 18),
                            label: const Text('Chia sẻ ảnh JPG'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _doc.combinedOcrText.trim().isEmpty
                                ? null
                                : () async {
                                    Navigator.of(ctx).pop();
                                    await widget.appState.shareOcrText(
                                      _doc.combinedOcrText,
                                      subject: _doc.title,
                                    );
                                  },
                            icon: const Icon(Icons.subject_rounded, size: 18),
                            label: const Text('Chia sẻ chữ OCR'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 4,
          title: InkWell(
            onTap: _editMetadataDialog,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _doc.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_outlined, size: 15),
                    ],
                  ),
                  Text(
                    '${_doc.folder} • ${_doc.pageCount} trang${_doc.isDraft ? ' (Bản nháp)' : ''}',
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (_doc.isDraft)
              IconButton(
                onPressed: () async {
                  final saved = await widget.appState.finalizeDocument(_doc);
                  if (mounted) {
                    setState(() => _doc = saved);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã lưu chính thức vào thư viện tài liệu.'),
                      ),
                    );
                  }
                },
                tooltip: 'Lưu chính thức',
                icon: const Icon(Icons.check_circle_outline_rounded),
              ),
            IconButton(
              onPressed: _showExportModal,
              tooltip: 'Xuất & Chia sẻ qua ứng dụng khác',
              icon: const Icon(Icons.ios_share_rounded),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                height: 42,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.grid_view_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Các trang'),
                  ],
                ),
              ),
              Tab(
                height: 42,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Văn bản AI OCR'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            return Stack(
              children: [
                TabBarView(
                  children: [
                    _buildPagesReorderTab(),
                    _buildOcrFullTextTab(),
                  ],
                ),
                if (widget.appState.isLoading)
                  Container(
                    color: Colors.black45,
                    alignment: Alignment.center,
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(
                              widget.appState.busyMessage ?? 'Đang xử lý...',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withOpacity(0.45)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importMoreImagesFromGallery,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Thêm ảnh', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanMorePages,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    label: const Text('Quét thêm', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showExportModal,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text(
                      'Xuất / Chia sẻ',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPagesReorderTab() {
    final sortedPages = List<ScanPage>.from(_doc.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    if (sortedPages.isEmpty) {
      return const Center(
        child: Text('Tài liệu chưa có trang nào. Hãy bấm Quét thêm hoặc Thêm ảnh.'),
      );
    }

    return Column(
      children: [
        if (_doc.tags.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _doc.tags
                  .map(
                    (t) => Chip(
                      label: Text('#$t', style: const TextStyle(fontSize: 11.5)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Chạm vào trang để sửa/lọc/ký tên • Giữ biểu tượng ☰ để đổi thứ tự trang',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: sortedPages.length,
            onReorder: (oldIndex, newIndex) async {
              final updated = await widget.appState.reorderPages(
                _doc,
                oldIndex,
                newIndex,
              );
              if (mounted) {
                setState(() => _doc = updated);
              }
            },
            itemBuilder: (context, index) {
              final page = sortedPages[index];
              final imgFile = File(page.displayImagePath);
              final ocrPreview = page.ocrResult?.fullText.trim() ?? '';
              final cs = Theme.of(context).colorScheme;

              return Card(
                key: ValueKey(page.id),
                margin: const EdgeInsets.symmetric(vertical: 5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
                ),
                child: InkWell(
                  onTap: () => _openPageEditor(page),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 66,
                            height: 88,
                            child: imgFile.existsSync()
                                ? Image.file(
                                    imgFile,
                                    key: ValueKey(page.displayImagePath),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: cs.surfaceContainerHighest,
                                    child: const Icon(Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Trang ${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    page.filter.label,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (page.annotations.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.draw_rounded,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                ocrPreview.isEmpty
                                    ? 'Chưa có văn bản OCR — bấm biểu tượng AI ✨ để nhận diện'
                                    : ocrPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: ocrPreview.isEmpty
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _compactPageActionBtn(
                                    icon: Icons.tune_rounded,
                                    label: 'Sửa/Lọc',
                                    onTap: () => _openPageEditor(page),
                                  ),
                                  const SizedBox(width: 6),
                                  _compactPageActionBtn(
                                    icon: Icons.auto_awesome_rounded,
                                    label: 'AI OCR',
                                    onTap: () => _rerunPageAiOcr(page),
                                  ),
                                  const SizedBox(width: 6),
                                  _compactPageActionBtn(
                                    icon: Icons.cameraswitch_outlined,
                                    label: 'Quét lại',
                                    onTap: () => _retakeSinglePage(page),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: () async {
                                      final updatedDoc = await widget.appState
                                          .deletePage(_doc, page);
                                      if (!mounted) return;
                                      if (updatedDoc == null) {
                                        Navigator.of(context).pop();
                                      } else {
                                        setState(() => _doc = updatedDoc);
                                      }
                                    },
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: cs.error,
                                    ),
                                    tooltip: 'Xóa trang',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, right: 2),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _compactPageActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOcrFullTextTab() {
    final fullText = _doc.combinedOcrText;
    final sortedPages = List<ScanPage>.from(_doc.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    final query = _inDocOcrQuery.trim().toLowerCase();
    final filteredPages = query.isEmpty
        ? sortedPages
        : sortedPages
            .where(
              (p) => (p.ocrResult?.fullText ?? '').toLowerCase().contains(query),
            )
            .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm trong văn bản OCR (Tiếng Việt / Viết tay)...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (val) => setState(() => _inDocOcrQuery = val),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: fullText.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: fullText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã sao chép toàn bộ nội dung OCR.'),
                          ),
                        );
                      },
                tooltip: 'Sao chép toàn bộ',
                icon: const Icon(Icons.copy_all_rounded, size: 19),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                onPressed: fullText.isEmpty
                    ? null
                    : () => widget.appState.shareOcrText(
                          fullText,
                          subject: _doc.title,
                        ),
                tooltip: 'Chia sẻ toàn bộ văn bản OCR',
                icon: const Icon(Icons.ios_share_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filteredPages.isEmpty
                ? const Center(
                    child: Text('Không tìm thấy đoạn văn bản OCR nào khớp từ khóa.'),
                  )
                : ListView.separated(
                    itemCount: filteredPages.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final page = filteredPages[idx];
                      final text = page.ocrResult?.fullText.trim() ?? '';
                      final cs = Theme.of(context).colorScheme;
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.55),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Trang ${page.pageIndex + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 18,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip:
                                        'Nhận diện lại AI OCR (Tiếng Việt & Chữ viết tay)',
                                    onPressed: () => _rerunPageAiOcr(page),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_note_rounded,
                                      size: 20,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Chỉnh sửa văn bản OCR',
                                    onPressed: () => _editPageOcrDialog(page),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, size: 17),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Sao chép trang này',
                                    onPressed: text.isEmpty
                                        ? null
                                        : () {
                                            Clipboard.setData(
                                              ClipboardData(text: text),
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Đã sao chép OCR Trang ${page.pageIndex + 1}',
                                                ),
                                              ),
                                            );
                                          },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.share_outlined,
                                      size: 17,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Chia sẻ văn bản trang này',
                                    onPressed: text.isEmpty
                                        ? null
                                        : () => widget.appState.shareOcrText(
                                              text,
                                              subject:
                                                  '${_doc.title} - Trang ${page.pageIndex + 1}',
                                            ),
                                  ),
                                ],
                              ),
                              const Divider(height: 14),
                              SelectableText(
                                text.isEmpty
                                    ? '(Chưa có chữ trên trang này — bấm biểu tượng ✨ để quét lại bằng AI OCR)'
                                    : text,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: text.isEmpty
                                      ? cs.onSurfaceVariant
                                      : cs.onSurface,
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
}
