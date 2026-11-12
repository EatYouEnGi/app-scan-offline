import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/scan_models.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'document_detail_screen.dart';

/// Màn hình Công Cụ PDF & Khóa Sinh Trắc Học (Stitch Screen 7):
/// - Thẻ Bảo Mật Sinh Trắc Học (Face ID / Vân tay, Lưu trữ cục bộ On-Device).
/// - Card 1: Nhập tệp PDF có sẵn từ thiết bị.
/// - Card 2: Gộp nhiều tài liệu (Merge PDF) trực quan ngay trên thẻ.
/// - Card 3: Tách trang tài liệu (Split PDF) theo khoảng trang (VD: 1-2, 4).
/// - Card 4: Nén dung lượng & Chọn khổ giấy PDF (A4 / Letter / Hóa đơn).
/// - Hỗ trợ song ngữ Tiếng Việt & Tiếng Anh.
class PdfToolsScreen extends StatefulWidget {
  final AppState appState;

  const PdfToolsScreen({
    super.key,
    required this.appState,
  });

  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  final Set<String> _selectedMergeDocIds = <String>{};
  final TextEditingController _splitRangeCtrl =
      TextEditingController(text: '1-2');
  String? _selectedSplitDocId;

  String _tr(String vi, String en) => widget.appState.tr(vi, en);

  @override
  void initState() {
    super.initState();
    final docs = widget.appState.documents;
    if (docs.length >= 2) {
      _selectedMergeDocIds.add(docs[0].id);
      _selectedMergeDocIds.add(docs[1].id);
    } else if (docs.length == 1) {
      _selectedMergeDocIds.add(docs[0].id);
    }
    final multiDocs = docs.where((d) => d.pageCount >= 2).toList();
    if (multiDocs.isNotEmpty) {
      _selectedSplitDocId = multiDocs.first.id;
    } else if (docs.isNotEmpty) {
      _selectedSplitDocId = docs.first.id;
    }
  }

  @override
  void dispose() {
    _splitRangeCtrl.dispose();
    super.dispose();
  }

  Future<void> _importPdfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final filePath = result.files.single.path!;
      final baseTitle = p.basenameWithoutExtension(filePath);

      final importedDoc = await widget.appState.importExistingPdf(
        pdfPath: filePath,
        customTitle: baseTitle.isEmpty
            ? _tr('PDF Nhập', 'Imported PDF')
            : baseTitle,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DocumentDetailScreen(
            appState: widget.appState,
            initialDocument: importedDoc,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('${_tr('Không thể nhập PDF', 'Cannot import PDF')}: $e'),
        ),
      );
    }
  }

  Future<void> _executeInlineMerge() async {
    final allDocs = widget.appState.documents;
    final chosenDocs =
        allDocs.where((d) => _selectedMergeDocIds.contains(d.id)).toList();

    if (chosenDocs.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Vui lòng tích chọn ít nhất 2 tài liệu để Gộp PDF.',
              'Please select at least 2 documents to Merge PDF.',
            ),
          ),
        ),
      );
      return;
    }

    final merged = await widget.appState.mergeDocuments(
      sourceDocuments: chosenDocs,
      mergedTitle: _tr(
        'Hồ sơ gộp (${DateTime.now().day}/${DateTime.now().month})',
        'Merged Document (${DateTime.now().day}/${DateTime.now().month})',
      ),
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: merged,
        ),
      ),
    );
  }

  List<int> _parsePageRange(String input, int maxPages) {
    final result = <int>{};
    final parts = input.split(',');
    for (final raw in parts) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length == 2) {
          final start = int.tryParse(bounds[0].trim());
          final end = int.tryParse(bounds[1].trim());
          if (start != null && end != null) {
            final s = start.clamp(1, maxPages);
            final e = end.clamp(1, maxPages);
            for (int p = s; p <= e; p++) {
              result.add(p - 1);
            }
          }
        }
      } else {
        final single = int.tryParse(token);
        if (single != null && single >= 1 && single <= maxPages) {
          result.add(single - 1);
        }
      }
    }
    if (result.isEmpty && maxPages > 0) {
      result.add(0);
    }
    final sorted = result.toList()..sort();
    return sorted;
  }

  Future<void> _executeInlineSplit(ScanDocument sourceDoc) async {
    if (sourceDoc.pageCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Tài liệu cần có từ 2 trang trở lên để thực hiện Tách trang.',
              'Document must have at least 2 pages to Split PDF.',
            ),
          ),
        ),
      );
      return;
    }

    final indexes =
        _parsePageRange(_splitRangeCtrl.text, sourceDoc.pageCount);
    final splitDoc = await widget.appState.splitDocument(
      sourceDocument: sourceDoc,
      selectedPageIndexes: indexes,
      newTitle:
          '${sourceDoc.title} (${_tr('Bản tách', 'Split')})',
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: splitDoc,
        ),
      ),
    );
  }

  Future<void> _showCompressExportDialog() async {
    final docs = widget.appState.documents;
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'Chưa có tài liệu nào trong thư viện.',
              'No documents in the library yet.',
            ),
          ),
        ),
      );
      return;
    }

    ScanDocument selectedDoc = docs.first;
    PaperSizePreset paper = PaperSizePreset.a4;
    PdfQualityPreset quality = PdfQualityPreset.compressed;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                _tr('Nén PDF & Chọn khổ giấy', 'Compress PDF & Paper Size'),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<ScanDocument>(
                    value: selectedDoc,
                    decoration: InputDecoration(
                      labelText: _tr('Tài liệu', 'Document'),
                      border: const OutlineInputBorder(),
                    ),
                    items: docs
                        .map(
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(d.title),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedDoc = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaperSizePreset>(
                    value: paper,
                    decoration: InputDecoration(
                      labelText: _tr('Khổ giấy', 'Paper Size'),
                      border: const OutlineInputBorder(),
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
                      if (v != null) setDialogState(() => paper = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PdfQualityPreset>(
                    value: quality,
                    decoration: InputDecoration(
                      labelText: _tr('Mức nén dung lượng', 'Compression Level'),
                      border: const OutlineInputBorder(),
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
                      if (v != null) setDialogState(() => quality = v);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(_tr('Hủy', 'Cancel')),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  icon: const Icon(Icons.compress),
                  label: Text(
                    _tr('Tạo & Chia sẻ PDF nén', 'Export & Share Compressed PDF'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await widget.appState.exportSearchablePdf(
      document: selectedDoc,
      paperSize: paper,
      quality: quality,
      openShareSheet: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final allDocs = widget.appState.documents;
        final selectedMergeDocs =
            allDocs.where((d) => _selectedMergeDocIds.contains(d.id)).toList();
        final totalMergePages =
            selectedMergeDocs.fold<int>(0, (sum, d) => sum + d.pageCount);

        ScanDocument? splitSourceDoc;
        if (allDocs.isNotEmpty) {
          splitSourceDoc = allDocs.firstWhere(
            (d) => d.id == _selectedSplitDocId,
            orElse: () => allDocs.first,
          );
        }

        return Scaffold(
          backgroundColor: StitchTheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                _buildTopAppBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      // 1. Biometric Security Hero Banner (Stitch Screen 7)
                      _buildBiometricHeroBanner(),
                      const SizedBox(height: 18),

                      // 2. Section Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _tr('TIỆN ÍCH XỬ LÝ TỆP PDF', 'OFFLINE PDF UTILITIES'),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: StitchTheme.textSubtle,
                            ),
                          ),
                          Text(
                            _tr('4 công cụ sẵn sàng', '4 tools ready'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: StitchTheme.primary.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // 3. Card 1: Nhập tệp PDF có sẵn từ thiết bị
                      _buildImportPdfCard(),
                      const SizedBox(height: 14),

                      // 4. Card 2: Gộp nhiều tài liệu (Merge PDF)
                      _buildMergePdfCard(
                        allDocs: allDocs,
                        selectedCount: selectedMergeDocs.length,
                        totalMergePages: totalMergePages,
                      ),
                      const SizedBox(height: 14),

                      // 5. Card 3: Tách trang tài liệu (Split PDF)
                      _buildSplitPdfCard(
                        allDocs: allDocs,
                        splitSourceDoc: splitSourceDoc,
                      ),
                      const SizedBox(height: 14),

                      // 6. Card 4: Nén dung lượng & Khổ giấy PDF
                      _buildCompressPdfCard(),

                      const SizedBox(height: 18),
                      // 7. Bottom Trust Badge
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: StitchTheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: StitchTheme.borderLight),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.offline_bolt_rounded,
                                size: 15,
                                color: StitchTheme.primaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _tr(
                                  '100% Offline Engine • Không tải tài liệu lên đám mây',
                                  '100% Offline Engine • Zero Cloud Uploads',
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: StitchTheme.textSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: const BoxDecoration(
        color: StitchTheme.surface,
        border: Border(
          bottom: BorderSide(color: StitchTheme.borderLight),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: StitchTheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: StitchTheme.textMain,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr('Công Cụ PDF & Bảo Mật', 'PDF Tools & Security'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.textMain,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: StitchTheme.primaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _tr(
                        'Xử lý ngoại tuyến 100% on-device',
                        '100% On-Device Offline Processing',
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.primaryContainer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => widget.appState.toggleLanguage(),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: StitchTheme.primaryContainerLight,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.appState.isVi ? '🇻🇳 VI' : '🇬🇧 EN',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: StitchTheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricHeroBanner() {
    final enabled = widget.appState.biometricLockEnabled;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE0F2F1), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: StitchTheme.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF191C1F).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: StitchTheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: enabled
                            ? StitchTheme.statusSuccess
                            : StitchTheme.statusWarning,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _tr('Kho Tài Liệu An Toàn', 'Biometric Document Vault'),
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: StitchTheme.textMain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: enabled
                                ? const Color(0xFFD1FAE5)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            enabled
                                ? _tr('Đang bật', 'Active')
                                : _tr('Đang tắt', 'Off'),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tr(
                        'Yêu cầu xác thực sinh trắc học khi mở ứng dụng hoặc chia sẻ hồ sơ quan trọng.',
                        'Require Face ID / Fingerprint authentication when opening the app.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                activeColor: StitchTheme.primary,
                onChanged: (val) async {
                  await widget.appState.setBiometricLockEnabled(val);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFD1E7E5)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.face_retouching_natural_rounded,
                    size: 15,
                    color: StitchTheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_tr('Face ID / Vân tay', 'Face ID / Touch ID')}: ${enabled ? _tr('BẬT', 'ON') : _tr('TẮT', 'OFF')}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: StitchTheme.primary,
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.enhanced_encryption_rounded,
                      size: 13,
                      color: StitchTheme.textSubtle,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _tr('Lưu trữ cục bộ On-Device', 'On-Device Storage'),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportPdfCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF191C1F).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: StitchTheme.primaryContainerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.upload_file_rounded,
                  color: StitchTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'Nhập tệp PDF có sẵn từ thiết bị',
                        'Import Existing PDF from Device',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Chuyển đổi tệp PDF trong máy thành các trang để ký tên, đóng dấu hoặc chạy AI OCR tiếng Việt.',
                        'Convert existing PDF files into editable pages for signing, stamping, or AI OCR.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _importPdfFile,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: StitchTheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: StitchTheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_open_rounded,
                    color: StitchTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tr(
                        'Chạm để chọn file .PDF trên thiết bị',
                        'Tap to choose a .PDF file on device',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: StitchTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _tr('Duyệt tệp trên máy', 'Browse Files'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMergePdfCard({
    required List<ScanDocument> allDocs,
    required int selectedCount,
    required int totalMergePages,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF191C1F).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: StitchTheme.primaryContainerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.call_merge_rounded,
                  color: StitchTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'Gộp nhiều tài liệu (Merge PDF)',
                        'Merge Multiple Documents (Merge PDF)',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Chọn các tài liệu trong thư viện để nối thành một tệp PDF duy nhất.',
                        'Select documents in your library to combine into a single PDF.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              if (allDocs.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedMergeDocIds.length == allDocs.length) {
                        _selectedMergeDocIds.clear();
                      } else {
                        _selectedMergeDocIds
                            .addAll(allDocs.map((e) => e.id));
                      }
                    });
                  },
                  child: Text(
                    _selectedMergeDocIds.length == allDocs.length
                        ? _tr('Bỏ chọn', 'Deselect')
                        : _tr('Chọn tất cả', 'Select all'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (allDocs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _tr(
                  'Chưa có tài liệu nào trong thư viện.',
                  'No documents in library yet.',
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: StitchTheme.textSubtle,
                ),
              ),
            )
          else
            ...allDocs.take(4).map((doc) {
              final checked = _selectedMergeDocIds.contains(doc.id);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (checked) {
                      _selectedMergeDocIds.remove(doc.id);
                    } else {
                      _selectedMergeDocIds.add(doc.id);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: checked
                        ? StitchTheme.primaryContainerLight
                            .withValues(alpha: 0.35)
                        : StitchTheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: checked
                          ? StitchTheme.primary.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        checked
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: checked
                            ? StitchTheme.primary
                            : StitchTheme.textSubtle,
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 18,
                        color: StitchTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              doc.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: StitchTheme.textMain,
                              ),
                            ),
                            Text(
                              '${doc.pageCount} ${_tr('trang', 'pages')} • ${doc.folder}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: StitchTheme.textSubtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: selectedCount < 2 ? null : _executeInlineMerge,
              style: FilledButton.styleFrom(
                backgroundColor: StitchTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.merge_type_rounded, size: 18),
              label: Text(
                _tr(
                  'Gộp $selectedCount tệp đã chọn ($totalMergePages trang)',
                  'Merge $selectedCount selected ($totalMergePages pages)',
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitPdfCard({
    required List<ScanDocument> allDocs,
    required ScanDocument? splitSourceDoc,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF191C1F).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: StitchTheme.primaryContainerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.content_cut_rounded,
                  color: StitchTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'Tách trang tài liệu (Split PDF)',
                        'Split Document Pages (Split PDF)',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Trích xuất trang lẻ hoặc khoảng trang từ tệp PDF nhiều trang.',
                        'Extract specific pages or page ranges into a new document.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (splitSourceDoc != null) ...[
            DropdownButtonFormField<String>(
              value: splitSourceDoc.id,
              isDense: true,
              decoration: InputDecoration(
                labelText: _tr('Tài liệu gốc', 'Source Document'),
                filled: true,
                fillColor: StitchTheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide.none,
                ),
              ),
              items: allDocs
                  .map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        '${d.title} (${d.pageCount} ${_tr('trang', 'pages')})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedSplitDocId = val);
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: StitchTheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: StitchTheme.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr(
                            'KHOẢNG TRANG CẦN TÁCH (VD: 1-2, 4)',
                            'PAGE RANGE TO EXTRACT (E.G. 1-2, 4)',
                          ),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: StitchTheme.textSubtle,
                          ),
                        ),
                        TextField(
                          controller: _splitRangeCtrl,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: StitchTheme.textMain,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _executeInlineSplit(splitSourceDoc),
                  style: FilledButton.styleFrom(
                    backgroundColor: StitchTheme.primaryContainerLight,
                    foregroundColor: StitchTheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: Text(
                    _tr('Tách ngay', 'Split Now'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              _tr(
                'Chưa có tài liệu nào để tách trang.',
                'No documents available to split.',
              ),
              style: const TextStyle(
                fontSize: 12,
                color: StitchTheme.textSubtle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompressPdfCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF191C1F).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: StitchTheme.primaryContainerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.compress_rounded,
                  color: StitchTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(
                        'Nén PDF & Định dạng Khổ giấy',
                        'Compress PDF & Paper Size Preset',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tr(
                        'Giảm dung lượng tệp PDF (A4, Letter, Hóa đơn) để gửi nhanh qua Zalo, Email.',
                        'Optimize PDF size and paper format (A4, Letter, Receipt) for fast sharing.',
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showCompressExportDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: StitchTheme.primary,
                side: const BorderSide(color: StitchTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: const Icon(Icons.compress_rounded, size: 18),
              label: Text(
                _tr('Nén PDF & Chọn khổ giấy', 'Compress PDF & Select Paper Size'),
                style: const TextStyle(
                  fontSize: 12.5,
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
