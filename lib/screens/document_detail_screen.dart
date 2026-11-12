import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/scan_models.dart';
import '../state/app_state.dart';
import 'page_editor_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chi tiết tài liệu nhiều trang:
/// - Quản lý trang: thêm, xóa, kéo thả đổi thứ tự, chụp lại, chỉnh 4 góc/bộ lọc/chữ ký.
/// - Xem và tìm kiếm nội dung OCR tiếng Việt/Anh trên toàn bộ các trang.
/// - Đổi tên, chọn thư mục, gắn thẻ (tags).
/// - Xuất PDF có lớp chữ tìm kiếm được (chọn khổ giấy & mức nén) hoặc chia sẻ bộ ảnh.
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
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(),
      ),
    );
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
    final captured = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(singleShotMode: true),
      ),
    );
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
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xuất & Chia sẻ tài liệu (${_doc.pageCount} trang)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'PDF xuất ra có nhúng sẵn lớp văn bản OCR ẩn giúp tìm kiếm và sao chép chữ.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<PaperSizePreset>(
                    value: selectedPaper,
                    decoration: const InputDecoration(
                      labelText: 'Khổ giấy PDF',
                      border: OutlineInputBorder(),
                    ),
                    items: PaperSizePreset.values
                        .map(
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(p.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedPaper = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<PdfQualityPreset>(
                    value: selectedQuality,
                    decoration: const InputDecoration(
                      labelText: 'Mức nén & Chất lượng',
                      border: OutlineInputBorder(),
                    ),
                    items: PdfQualityPreset.values
                        .map(
                          (q) => DropdownMenuItem(
                            value: q,
                            child: Text(q.label),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedQuality = v);
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await widget.appState.shareDocumentImages(_doc);
                          },
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('Xuất bộ ảnh JPG'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            final pdfPath =
                                await widget.appState.exportSearchablePdf(
                              document: _doc,
                              paperSize: selectedPaper,
                              quality: selectedQuality,
                              openShareSheet: true,
                            );
                            await _reloadDoc();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Đã tạo tệp PDF: $pdfPath'),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Xuất PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: _editMetadataDialog,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _doc.title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 16),
                  ],
                ),
                Text(
                  '${_doc.folder} • ${_doc.pageCount} trang${_doc.isDraft ? ' (Bản nháp)' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            if (_doc.isDraft)
              TextButton.icon(
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
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu'),
              ),
            IconButton(
              onPressed: _showExportModal,
              tooltip: 'Xuất PDF hoặc chia sẻ ảnh',
              icon: const Icon(Icons.ios_share),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.burst_mode_outlined),
                text: 'Các trang & Sắp xếp',
              ),
              Tab(
                icon: Icon(Icons.manage_search),
                text: 'Văn bản OCR (Việt/Anh)',
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importMoreImagesFromGallery,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Thêm ảnh'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanMorePages,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Chụp thêm trang'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _showExportModal,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Xuất PDF'),
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
        child: Text('Tài liệu chưa có trang nào. Hãy bấm Chụp thêm trang hoặc Thêm ảnh.'),
      );
    }

    return Column(
      children: [
        if (_doc.tags.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _doc.tags
                  .map(
                    (t) => Chip(
                      label: Text('#$t', style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Nhấn vào trang để cắt góc/lọc/ký tên. Nhấn giữ biểu tượng kéo bên phải để đổi thứ tự trang.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
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

              return Card(
                key: ValueKey(page.id),
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: InkWell(
                  onTap: () => _openPageEditor(page),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 68,
                            height: 92,
                            child: imgFile.existsSync()
                                ? Image.file(
                                    imgFile,
                                    key: ValueKey(page.displayImagePath),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.broken_image),
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Trang ${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    page.filter.label,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  if (page.annotations.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.draw,
                                      size: 14,
                                      color: Colors.indigo,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ocrPreview.isEmpty
                                    ? 'Chưa có văn bản OCR trên trang này'
                                    : ocrPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: ocrPreview.isEmpty
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _openPageEditor(page),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.crop_rotate, size: 16),
                                    label: const Text('Sửa & Lọc'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _retakeSinglePage(page),
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.camera_alt_outlined,
                                        size: 16),
                                    label: const Text('Chụp lại'),
                                  ),
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
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Colors.redAccent,
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
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(Icons.drag_handle),
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
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm từ khóa trong văn bản OCR của tài liệu này...',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (val) => setState(() => _inDocOcrQuery = val),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.tonalIcon(
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
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Chép hết'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Trang ${page.pageIndex + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
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
                                ],
                              ),
                              const Divider(),
                              SelectableText(
                                text.isEmpty
                                    ? '(Trang này không có chữ in)'
                                    : text,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.45,
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
