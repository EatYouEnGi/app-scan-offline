import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scan_models.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'page_editor_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chi tiết tài liệu nhiều trang (Stitch Screens 3, 4 & 6):
/// - Tab 1 (Các trang): quản lý trang, kéo thả đổi thứ tự, xem trước OCR, nhãn A4/ĐÃ KÝ, Sửa/Lọc, AI OCR, Quét lại, Xóa.
/// - Tab 2 (Văn bản AI OCR): tìm kiếm nội dung OCR, banner Offline On-Device AI 99.8%, thẻ văn bản từng trang kèm đếm từ & tùy chọn xuất TXT / sao chép / chia sẻ.
/// - Bảng Xuất File & Chia Sẻ Tối Giản (Stitch Screen 6): chọn định dạng (PDF / Ảnh JPG / Văn bản OCR), dãy biểu tượng 1 chạm (Zalo, Gmail, Tin nhắn, Drive, AirDrop), Lưu máy, In ấn, Sao chép.
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
  int _activeTabIndex = 0;
  String _inDocOcrQuery = '';

  String _tr(String vi, String en) => widget.appState.tr(vi, en);

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
    List<String>? captured =
        await widget.appState.launchNativeAiScanner(maxPages: 20);
    bool usedBuiltInFallback = false;
    if (captured == null && mounted) {
      usedBuiltInFallback = true;
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
      alreadyCroppedByAi: !usedBuiltInFallback,
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
    List<String>? captured =
        await widget.appState.launchNativeAiScanner(maxPages: 1);
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

  Future<void> _exportTxtFile() async {
    final text = _doc.combinedOcrText.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có văn bản OCR để xuất file TXT.')),
      );
      return;
    }
    final tempDir = await getTemporaryDirectory();
    final safeName = _doc.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(' ', '_');
    final txtFile = File('${tempDir.path}/$safeName.txt');
    await txtFile.writeAsString(text, flush: true);
    await Share.shareXFiles(
      [XFile(txtFile.path, mimeType: 'text/plain')],
      subject: '${_doc.title} - Văn bản AI OCR',
    );
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
                        hintText: 'Ví dụ: Hợp đồng, Thuế 2026, Quan trọng',
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

  /// Bảng Xuất File & Chia Sẻ Tối Giản (Stitch Screen 6).
  Future<void> _showExportModal() async {
    int selectedFormatIdx = 0; // 0: PDF, 1: Ảnh JPG, 2: Văn bản OCR
    PaperSizePreset selectedPaper = PaperSizePreset.a4;
    PdfQualityPreset selectedQuality = PdfQualityPreset.high;

    Future<void> executePrimaryShare(BuildContext sheetCtx) async {
      Navigator.of(sheetCtx).pop();
      if (selectedFormatIdx == 0) {
        await widget.appState.exportSearchablePdf(
          document: _doc,
          paperSize: selectedPaper,
          quality: selectedQuality,
          openShareSheet: true,
        );
        await _reloadDoc();
      } else if (selectedFormatIdx == 1) {
        await widget.appState.shareDocumentImages(_doc);
      } else {
        final text = _doc.combinedOcrText.trim();
        if (text.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tài liệu chưa có văn bản OCR để chia sẻ.'),
              ),
            );
          }
          return;
        }
        await widget.appState.shareOcrText(text, subject: _doc.title);
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final safeFileName =
                '${_doc.title.replaceAll(' ', '_')}.${selectedFormatIdx == 0 ? 'pdf' : selectedFormatIdx == 1 ? 'jpg' : 'txt'}';
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 1. Header & File Info
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: StitchTheme.primaryContainerLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            selectedFormatIdx == 0
                                ? Icons.picture_as_pdf_rounded
                                : selectedFormatIdx == 1
                                    ? Icons.collections_rounded
                                    : Icons.description_rounded,
                            color: StitchTheme.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                safeFileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: StitchTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_doc.pageCount} trang • ${selectedPaper.label.split(' ').first} • OCR Tiếng Việt',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: StitchTheme.textSubtle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: StitchTheme.textSubtle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                      // 2. Segmented Format Control (PDF | Ảnh JPG | Văn bản OCR)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildFormatSegmentItem(
                            title: 'PDF',
                            subtitle: _tr('A4 • Chuẩn', 'A4 • Standard'),
                            selected: selectedFormatIdx == 0,
                            onTap: () =>
                                setSheetState(() => selectedFormatIdx = 0),
                          ),
                          _buildFormatSegmentItem(
                            title: _tr('Ảnh JPG', 'JPG Images'),
                            subtitle:
                                '${_doc.pageCount} ${_tr('ảnh', 'images')}',
                            selected: selectedFormatIdx == 1,
                            onTap: () =>
                                setSheetState(() => selectedFormatIdx = 1),
                          ),
                          _buildFormatSegmentItem(
                            title: _tr('Văn bản OCR', 'OCR Text'),
                            subtitle: 'File .TXT',
                            selected: selectedFormatIdx == 2,
                            onTap: () =>
                                setSheetState(() => selectedFormatIdx = 2),
                          ),
                        ],
                      ),
                    ),

                    // Tùy chọn Khổ giấy & Chất lượng khi chọn PDF
                    if (selectedFormatIdx == 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<PaperSizePreset>(
                              value: selectedPaper,
                              isDense: true,
                              decoration: InputDecoration(
                                labelText: 'Khổ giấy PDF',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: PaperSizePreset.values
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p,
                                      child: Text(
                                        p.label,
                                        style: const TextStyle(fontSize: 12.5),
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
                              decoration: InputDecoration(
                                labelText: 'Chất lượng PDF',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: PdfQualityPreset.values
                                  .map(
                                    (q) => DropdownMenuItem(
                                      value: q,
                                      child: Text(
                                        q.label,
                                        style: const TextStyle(fontSize: 12.5),
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
                    ],
                    const SizedBox(height: 16),

                    // 3. Dãy biểu tượng Chia sẻ nhanh 1 chạm (Zalo, Gmail, Tin nhắn, Drive, AirDrop)
                    Text(
                      _tr('CHIA SẺ NHANH 1 CHẠM', '1-TAP QUICK SHARE'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildQuickShareAppIcon(
                          label: 'Zalo',
                          bgColor: const Color(0xFF0068FF),
                          customChild: const Text(
                            'Zalo',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => executePrimaryShare(ctx),
                        ),
                        _buildQuickShareAppIcon(
                          label: 'Gmail',
                          bgColor: const Color(0xFFFEF2F2),
                          borderColor: const Color(0xFFFEE2E2),
                          customChild: const Icon(
                            Icons.mail_rounded,
                            color: Color(0xFFEA4335),
                            size: 24,
                          ),
                          onTap: () => executePrimaryShare(ctx),
                        ),
                        _buildQuickShareAppIcon(
                          label: 'Tin nhắn',
                          bgColor: const Color(0xFF0EA5E9),
                          customChild: const Icon(
                            Icons.chat_bubble_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onTap: () => executePrimaryShare(ctx),
                        ),
                        _buildQuickShareAppIcon(
                          label: 'Drive',
                          bgColor: const Color(0xFFFFFBEB),
                          borderColor: const Color(0xFFFEF3C7),
                          customChild: const Icon(
                            Icons.add_to_drive_rounded,
                            color: Color(0xFFF59E0B),
                            size: 24,
                          ),
                          onTap: () => executePrimaryShare(ctx),
                        ),
                        _buildQuickShareAppIcon(
                          label: 'AirDrop',
                          bgColor: const Color(0xFFEFF6FF),
                          borderColor: const Color(0xFFDBEAFE),
                          customChild: const Icon(
                            Icons.wifi_tethering_rounded,
                            color: Color(0xFF007AFF),
                            size: 24,
                          ),
                          onTap: () => executePrimaryShare(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 4. Primary Share Button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => executePrimaryShare(ctx),
                        style: FilledButton.styleFrom(
                          backgroundColor: StitchTheme.primaryContainer,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 20),
                        label: Text(
                          _tr('Chia sẻ tệp ngay', 'Share File Now'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 5. Secondary Quick Actions Row (Lưu máy, In ấn, Sao chép, Đặt mã khóa)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSecondaryCircleAction(
                          icon: Icons.download_rounded,
                          label: 'Lưu máy',
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            final savedPath =
                                await widget.appState.savePdfToDeviceFolder(
                              document: _doc,
                              paperSize: selectedPaper,
                              quality: selectedQuality,
                            );
                            await _reloadDoc();
                            if (savedPath != null && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Đã lưu PDF vào máy: $savedPath'),
                                ),
                              );
                            }
                          },
                        ),
                        _buildSecondaryCircleAction(
                          icon: Icons.print_rounded,
                          label: 'In ấn',
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            await widget.appState.previewAndPrintPdf(
                              document: _doc,
                              paperSize: selectedPaper,
                              quality: selectedQuality,
                            );
                          },
                        ),
                        _buildSecondaryCircleAction(
                          icon: Icons.content_copy_rounded,
                          label: 'Sao chép',
                          onTap: () {
                            Navigator.of(ctx).pop();
                            final txt = _doc.combinedOcrText.trim();
                            if (txt.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Chưa có văn bản OCR để sao chép.',
                                  ),
                                ),
                              );
                              return;
                            }
                            Clipboard.setData(ClipboardData(text: txt));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã sao chép toàn bộ văn bản OCR vào bộ nhớ tạm.',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildSecondaryCircleAction(
                          icon: widget.appState.biometricLockEnabled
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          label: 'Khóa bảo mật',
                          onTap: () async {
                            final nextState =
                                !widget.appState.biometricLockEnabled;
                            await widget.appState
                                .setBiometricLockEnabled(nextState);
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    nextState
                                        ? 'Đã bật khóa sinh trắc học cho kho tài liệu.'
                                        : 'Đã tắt khóa sinh trắc học.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 10),

                    // 6. Footer Note
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          size: 14,
                          color: StitchTheme.primaryContainer,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Xử lý ngoại tuyến on-device • Bảo mật 100%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: StitchTheme.textSubtle,
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

  Widget _buildFormatSegmentItem({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? StitchTheme.primary
                      : StitchTheme.textSubtle,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? StitchTheme.primaryContainer
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickShareAppIcon({
    required String label,
    required Color bgColor,
    Color? borderColor,
    required Widget customChild,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: borderColor != null
                  ? Border.all(color: borderColor)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: customChild,
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: StitchTheme.textMain,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryCircleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 19, color: StitchTheme.textMain),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: StitchTheme.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StitchTheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildStitchHeader(),
            _buildSegmentedTabBar(),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.appState,
                builder: (context, _) {
                  return Stack(
                    children: [
                      IndexedStack(
                        index: _activeTabIndex,
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
                                    widget.appState.busyMessage ??
                                        'Đang xử lý...',
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
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomWorkspaceBar(),
    );
  }

  /// Header chuẩn Stitch (nút Back tròn, Tiêu đề có icon bút sửa, phụ đề trạng thái có chấm xanh, nút Lưu nháp & Chia sẻ).
  Widget _buildStitchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
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
            child: InkWell(
              onTap: _editMetadataDialog,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _doc.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: StitchTheme.textMain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.edit_rounded,
                          size: 15,
                          color: StitchTheme.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _doc.isDraft
                                ? StitchTheme.statusWarning
                                : StitchTheme.statusSuccess,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${_doc.folder} • ${_doc.pageCount} trang • ${_doc.isDraft ? 'Bản nháp' : 'Đã lưu'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: StitchTheme.textSubtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_doc.isDraft) ...[
            IconButton(
              onPressed: () async {
                final saved = await widget.appState.finalizeDocument(_doc);
                if (mounted) {
                  setState(() => _doc = saved);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Đã lưu chính thức vào thư viện tài liệu.'),
                    ),
                  );
                }
              },
              style: IconButton.styleFrom(
                backgroundColor: StitchTheme.primaryContainerLight,
                minimumSize: const Size(38, 38),
              ),
              tooltip: 'Lưu chính thức',
              icon: const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: StitchTheme.primary,
              ),
            ),
            const SizedBox(width: 6),
          ],
          InkWell(
            onTap: _showExportModal,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: StitchTheme.primaryContainerLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.ios_share_rounded,
                size: 19,
                color: StitchTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Segmented Tab Control chuẩn Stitch (`Các trang (X)` | `Văn bản AI OCR` kèm chấm xanh).
  Widget _buildSegmentedTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: StitchTheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTabIndex = 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _activeTabIndex == 0
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: _activeTabIndex == 0
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 16,
                        color: _activeTabIndex == 0
                            ? StitchTheme.primary
                            : StitchTheme.textSubtle,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_tr('Các trang', 'Pages')} (${_doc.pageCount})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _activeTabIndex == 0
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _activeTabIndex == 0
                              ? StitchTheme.primary
                              : StitchTheme.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTabIndex = 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _activeTabIndex == 1
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: _activeTabIndex == 1
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: _activeTabIndex == 1
                            ? StitchTheme.primary
                            : StitchTheme.textSubtle,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _tr('Văn bản AI OCR', 'AI OCR Text'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _activeTabIndex == 1
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: _activeTabIndex == 1
                              ? StitchTheme.primary
                              : StitchTheme.textSubtle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: StitchTheme.statusSuccess,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 1: Quản lý các trang (Stitch Screen 3).
  Widget _buildPagesReorderTab() {
    final sortedPages = List<ScanPage>.from(_doc.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    if (sortedPages.isEmpty) {
      return const Center(
        child: Text(
          'Tài liệu chưa có trang nào. Hãy bấm Quét thêm hoặc Thêm ảnh.',
        ),
      );
    }

    return Column(
      children: [
        // Dải nhãn Tag & Bảo mật trên máy
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              ..._doc.tags.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: StitchTheme.primaryContainerLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#$t',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              if (_doc.tags.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: StitchTheme.primaryContainerLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '#${_doc.folder}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: StitchTheme.primary,
                      ),
                    ),
                  ),
                ),
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Color(0xFFD97706),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Quan trọng',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: StitchTheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 13,
                      color: StitchTheme.textSubtle,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Bảo mật trên máy',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _editMetadataDialog,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: StitchTheme.surfaceContainerLow,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 15,
                    color: StitchTheme.textSubtle,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Thanh hướng dẫn thao tác nhanh
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: StitchTheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  size: 15,
                  color: StitchTheme.primary,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Chạm để sửa/ký số • Kéo giữ ☰ để đổi thứ tự trang',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: StitchTheme.textSubtle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Danh sách thẻ trang có thể kéo thả + thẻ chứng thực cuối trang
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            itemCount: sortedPages.length,
            footer: _buildOnDeviceVerificationBanner(),
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
              final hasAnnotations = page.annotations.isNotEmpty;

              return Container(
                key: ValueKey(page.id),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: StitchTheme.borderLight.withValues(alpha: 0.7),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF191C1F).withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: () => _openPageEditor(page),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail 70x95 chuẩn A4 + Nhãn A4 + Con dấu ĐÃ KÝ
                        SizedBox(
                          width: 70,
                          height: 95,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imgFile.existsSync()
                                    ? Image.file(
                                        imgFile,
                                        key: ValueKey(page.displayImagePath),
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        color: StitchTheme.surfaceContainerLow,
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'A4',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (hasAnnotations)
                                Positioned(
                                  bottom: 5,
                                  right: 4,
                                  child: Transform.rotate(
                                    angle: -0.2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                        border: Border.all(
                                          color: StitchTheme.statusDangerStamp,
                                        ),
                                      ),
                                      child: const Text(
                                        'ĐÃ KÝ',
                                        style: TextStyle(
                                          fontSize: 7.5,
                                          fontWeight: FontWeight.w900,
                                          color: StitchTheme.statusDangerStamp,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Thông tin trang + 4 nút thao tác gọn
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: StitchTheme
                                                .primaryContainerLight,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Trang ${index + 1}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                              color: StitchTheme.primary,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                StitchTheme.surfaceContainerLow,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            page.filter.label,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: StitchTheme.textSubtle,
                                            ),
                                          ),
                                        ),
                                        if (hasAnnotations)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFECFDF5),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.draw_rounded,
                                                  size: 11,
                                                  color: Color(0xFF047857),
                                                ),
                                                SizedBox(width: 2),
                                                Text(
                                                  'Đã ký tên',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF047857),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(
                                        Icons.drag_indicator_rounded,
                                        size: 20,
                                        color: StitchTheme.textSubtle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                ocrPreview.isEmpty
                                    ? 'Chưa có văn bản OCR — bấm AI OCR ✨ để nhận diện Tiếng Việt & chữ viết tay'
                                    : ocrPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.38,
                                  color: ocrPreview.isEmpty
                                      ? StitchTheme.textSubtle
                                      : StitchTheme.textMain,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _compactPageActionBtn(
                                    icon: Icons.tune_rounded,
                                    label: 'Sửa/Lọc',
                                    onTap: () => _openPageEditor(page),
                                  ),
                                  const SizedBox(width: 5),
                                  _compactPageActionBtn(
                                    icon: Icons.auto_awesome_rounded,
                                    label: 'AI OCR',
                                    isPrimaryTint: true,
                                    onTap: () => _rerunPageAiOcr(page),
                                  ),
                                  const SizedBox(width: 5),
                                  _compactPageActionBtn(
                                    icon: Icons.replay_rounded,
                                    label: 'Quét lại',
                                    onTap: () => _retakeSinglePage(page),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: () async {
                                      final updatedDoc = await widget.appState
                                          .deletePage(_doc, page);
                                      if (!mounted) return;
                                      if (updatedDoc == null) {
                                        Navigator.of(context).pop();
                                      } else {
                                        setState(() => _doc = updatedDoc);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(7),
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFDAD6)
                                            .withValues(alpha: 0.65),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 15,
                                        color: Color(0xFFBA1A1A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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

  Widget _buildOnDeviceVerificationBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: StitchTheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: StitchTheme.borderLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: StitchTheme.primaryContainerLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: StitchTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đã đối chiếu OCR On-Device • Độ tin cậy cao',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.textMain,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Xử lý cục bộ bởi Tesseract 5 LSTM & Apple Vision. Không gửi dữ liệu qua máy chủ bên thứ 3.',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: StitchTheme.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Transform.rotate(
            angle: -0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: StitchTheme.statusDangerStamp.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'BẢO MẬT\nON-DEVICE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  color: StitchTheme.statusDangerStamp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactPageActionBtn({
    required IconData icon,
    required String label,
    bool isPrimaryTint = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
        decoration: BoxDecoration(
          color: isPrimaryTint
              ? StitchTheme.primaryContainerLight.withValues(alpha: 0.75)
              : StitchTheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: StitchTheme.primary),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: isPrimaryTint
                    ? StitchTheme.primary
                    : StitchTheme.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 2: Văn bản AI OCR (Stitch Screen 4).
  Widget _buildOcrFullTextTab() {
    final fullText = _doc.combinedOcrText;
    final sortedPages = List<ScanPage>.from(_doc.pages)
      ..sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    final query = _inDocOcrQuery.trim().toLowerCase();
    final filteredPages = query.isEmpty
        ? sortedPages
        : sortedPages
            .where(
              (p) =>
                  (p.ocrResult?.fullText ?? '').toLowerCase().contains(query),
            )
            .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // 1. Search Bar + 2 nút Copy All & Share
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StitchTheme.borderLight),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm từ khóa tiếng Việt trong văn bản OCR...',
                    hintStyle: const TextStyle(
                      fontSize: 12.5,
                      color: StitchTheme.textSubtle,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: StitchTheme.primary,
                    ),
                    suffixIcon: _inDocOcrQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () =>
                                setState(() => _inDocOcrQuery = ''),
                            icon: const Icon(Icons.cancel_rounded, size: 18),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                  ),
                  onChanged: (val) => setState(() => _inDocOcrQuery = val),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildTopOcrSquareBtn(
              icon: Icons.copy_all_rounded,
              tooltip: 'Sao chép toàn bộ',
              onTap: fullText.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: fullText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã sao chép toàn bộ nội dung OCR.'),
                        ),
                      );
                    },
            ),
            const SizedBox(width: 6),
            _buildTopOcrSquareBtn(
              icon: Icons.ios_share_rounded,
              tooltip: 'Chia sẻ văn bản OCR',
              onTap: fullText.isEmpty
                  ? null
                  : () => widget.appState.shareOcrText(
                        fullText,
                        subject: _doc.title,
                      ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. Offline On-Device AI Status Banner (#E0F2F1)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: StitchTheme.primaryContainerLight.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: StitchTheme.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: StitchTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Offline On-Device AI',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: StitchTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Tiếng Việt & Viết tay',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Nhận diện cục bộ Tesseract 5 & Apple Vision • Bảo toàn dấu tiếng Việt 100% an toàn trên máy',
                      style: TextStyle(
                        fontSize: 11,
                        color: StitchTheme.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Thẻ văn bản OCR từng trang
        if (filteredPages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text('Không tìm thấy đoạn văn bản OCR nào khớp từ khóa.'),
            ),
          )
        else
          ...filteredPages.map((page) {
            final text = page.ocrResult?.fullText.trim() ?? '';
            final wordCount = text.isEmpty
                ? 0
                : text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                  // Header xám nhạt #F8FAFB
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFB),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFF1F5F9)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: StitchTheme.primaryContainerLight,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            'Trang ${page.pageIndex + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                              color: StitchTheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$wordCount từ',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: StitchTheme.textSubtle,
                          ),
                        ),
                        if (page.annotations.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.draw_rounded,
                                  size: 11,
                                  color: Color(0xFFB45309),
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Chữ viết tay',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFB45309),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(),
                        _buildCardMiniBtn(
                          icon: Icons.refresh_rounded,
                          tooltip: 'Quét lại AI OCR',
                          onTap: () => _rerunPageAiOcr(page),
                        ),
                        const SizedBox(width: 4),
                        _buildCardMiniBtn(
                          icon: Icons.edit_note_rounded,
                          tooltip: 'Chỉnh sửa văn bản',
                          onTap: () => _editPageOcrDialog(page),
                        ),
                        const SizedBox(width: 4),
                        _buildCardMiniBtn(
                          icon: Icons.content_copy_rounded,
                          tooltip: 'Sao chép trang này',
                          onTap: text.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Đã sao chép OCR Trang ${page.pageIndex + 1}',
                                      ),
                                    ),
                                  );
                                },
                        ),
                        const SizedBox(width: 4),
                        _buildCardMiniBtn(
                          icon: Icons.share_rounded,
                          tooltip: 'Chia sẻ văn bản trang này',
                          onTap: text.isEmpty
                              ? null
                              : () => widget.appState.shareOcrText(
                                    text,
                                    subject:
                                        '${_doc.title} - Trang ${page.pageIndex + 1}',
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: SelectableText(
                      text.isEmpty
                          ? '(Chưa có chữ trên trang này — bấm biểu tượng ↻ để quét lại bằng AI OCR)'
                          : text,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.58,
                        color: text.isEmpty
                            ? StitchTheme.textSubtle
                            : StitchTheme.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

        // 4. Bảng Tùy chọn trích xuất OCR ở cuối Tab 2
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: StitchTheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: StitchTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: StitchTheme.primary,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'TÙY CHỌN TRÍCH XUẤT OCR',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: StitchTheme.textSubtle,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Tổng ${_doc.pageCount} trang',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: StitchTheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportTxtFile,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: StitchTheme.textMain,
                        side: const BorderSide(color: StitchTheme.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      icon: const Icon(
                        Icons.description_outlined,
                        size: 17,
                        color: StitchTheme.primary,
                      ),
                      label: const Text(
                        'Xuất TXT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: fullText.isEmpty
                          ? null
                          : () => widget.appState.shareOcrText(
                                fullText,
                                subject: _doc.title,
                              ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: StitchTheme.textMain,
                        side: const BorderSide(color: StitchTheme.borderLight),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      icon: const Icon(
                        Icons.send_rounded,
                        size: 17,
                        color: StitchTheme.primary,
                      ),
                      label: const Text(
                        'Chia sẻ văn bản',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: fullText.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: fullText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã sao chép toàn bộ văn bản OCR vào bộ nhớ tạm.',
                              ),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: StitchTheme.primaryContainerLight,
                    foregroundColor: StitchTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: Text(
                    'Sao chép toàn bộ văn bản (${_doc.pageCount} trang)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopOcrSquareBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StitchTheme.borderLight),
          ),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null ? Colors.grey.shade400 : StitchTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildCardMiniBtn({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StitchTheme.borderLight),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null
                ? Colors.grey.shade300
                : StitchTheme.textSubtle,
          ),
        ),
      ),
    );
  }

  /// Thanh công cụ Workspace cố định dưới đáy (Thêm ảnh | Quét thêm | Xuất / Chia sẻ).
  Widget _buildBottomWorkspaceBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          border: const Border(
            top: BorderSide(color: StitchTheme.borderLight),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              flex: 10,
              child: FilledButton.tonalIcon(
                onPressed: _importMoreImagesFromGallery,
                style: FilledButton.styleFrom(
                  backgroundColor: StitchTheme.surfaceContainerLow,
                  foregroundColor: StitchTheme.textMain,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: StitchTheme.primary,
                ),
                label: Text(
                  _tr('Thêm ảnh', 'Add Photo'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: FilledButton.tonalIcon(
                onPressed: _scanMorePages,
                style: FilledButton.styleFrom(
                  backgroundColor: StitchTheme.surfaceContainerLow,
                  foregroundColor: StitchTheme.textMain,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(
                  Icons.document_scanner_outlined,
                  size: 18,
                  color: StitchTheme.primary,
                ),
                label: Text(
                  _tr('Quét thêm', 'Scan More'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 15,
              child: FilledButton.icon(
                onPressed: _showExportModal,
                style: FilledButton.styleFrom(
                  backgroundColor: StitchTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(
                  _tr('Xuất / Chia sẻ', 'Export / Share'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
