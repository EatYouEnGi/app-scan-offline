import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/scan_models.dart';
import '../services/database_service.dart';
import '../state/app_state.dart';
import 'document_detail_screen.dart';
import 'pdf_tools_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chính Thư viện Tài liệu:
/// - Giao diện gọn gàng, trực quan, biểu tượng nút bấm tinh gọn.
/// - Quét AI tự động bắt mép giấy (Google ML Kit Document Scanner / Apple VisionKit + Camera AI).
/// - Chia sẻ PDF/Ảnh trực tiếp sang ứng dụng khác chỉ với 1 chạm.
class LibraryScreen extends StatefulWidget {
  final AppState appState;

  const LibraryScreen({
    super.key,
    required this.appState,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Ưu tiên mở trình quét AI trên thiết bị (tự động nhận diện giấy không cần khung);
  /// nếu người dùng muốn dùng camera tích hợp hoặc thiết bị thiếu dịch vụ hệ thống thì mở `ScannerScreen`.
  Future<void> _startAiScan({bool forceBuiltInCamera = false}) async {
    List<String>? capturedPaths;
    bool alreadyCroppedByAi = false;

    if (!forceBuiltInCamera) {
      capturedPaths = await widget.appState.launchNativeAiScanner();
      if (capturedPaths != null && capturedPaths.isNotEmpty) {
        alreadyCroppedByAi = true;
      }
    }

    if ((capturedPaths == null || capturedPaths.isEmpty) &&
        forceBuiltInCamera &&
        mounted) {
      capturedPaths = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => const ScannerScreen(),
        ),
      );
      alreadyCroppedByAi = false;
    }

    if (capturedPaths == null || capturedPaths.isEmpty || !mounted) return;

    final draft = await widget.appState.startNewDraft();
    final populated = await widget.appState.addImagesToDocument(
      document: draft,
      sourceImagePaths: capturedPaths,
      alreadyCroppedByAi: alreadyCroppedByAi,
    );
    final finalized = await widget.appState.finalizeDocument(populated);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: finalized,
        ),
      ),
    );
  }

  Future<void> _importImagesFromGallery() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    final draft = await widget.appState.startNewDraft();
    final populated = await widget.appState.addImagesToDocument(
      document: draft,
      sourceImagePaths: picked.map((x) => x.path).toList(),
    );
    final finalized = await widget.appState.finalizeDocument(populated);

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: finalized,
        ),
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bảo mật & Công nghệ AI Nội bộ',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.fingerprint_rounded, size: 26),
                    title: const Text(
                      'Khóa ứng dụng bằng Sinh trắc học',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Bảo vệ tài liệu bằng Face ID, Touch ID hoặc vân tay',
                    ),
                    value: widget.appState.biometricLockEnabled,
                    onChanged: (val) {
                      widget.appState.toggleBiometricLock(val);
                    },
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.auto_awesome_rounded, color: Colors.teal),
                    title: Text(
                      'OCR Kết hợp: Offline + AI Trên Thiết Bị',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Tự động kết hợp mạng nơ-ron LSTM Tiếng Việt (Tesseract 5 / Apple Vision) và ML Kit ngay trên máy — không gửi dữ liệu qua bên thứ 3.',
                    ),
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
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        if (widget.appState.isLocked) {
          return _buildBiometricLockScreen();
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.document_scanner_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Tài Liệu AI',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        'Quét tự động • OCR Tiếng Việt • PDF',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () => _startAiScan(forceBuiltInCamera: true),
                tooltip: 'Camera AI tích hợp',
                icon: const Icon(Icons.camera_enhance_outlined, size: 22),
              ),
              IconButton(
                onPressed: _openSettingsSheet,
                tooltip: 'Bảo mật & Cài đặt',
                icon: const Icon(Icons.shield_outlined, size: 22),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _buildSearchAndFilters(),
                  if (widget.appState.recoverableDrafts.isNotEmpty)
                    _buildDraftRecoveryBanner(),
                  Expanded(
                    child: _buildDocumentList(),
                  ),
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
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(
                            widget.appState.busyMessage ?? 'Đang xử lý...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _buildCleanBottomActionBar(),
        );
      },
    );
  }

  /// Thanh tác vụ dưới cùng gọn gàng với 3 nút bấm trực quan.
  Widget _buildCleanBottomActionBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importImagesFromGallery,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 19),
                label: const Text(
                  'Nhập ảnh',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => _startAiScan(forceBuiltInCamera: false),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: const Text(
                  'Quét AI Tự Động',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfToolsScreen(appState: widget.appState),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                label: const Text(
                  'Công cụ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricLockScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_person_rounded,
                size: 68,
                color: Colors.teal,
              ),
              const SizedBox(height: 18),
              Text(
                'Kho Tài Liệu Đang Khóa',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Xác thực sinh trắc học để mở kho tài liệu scan cá nhân của bạn.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => widget.appState.unlockWithBiometrics(),
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Mở khóa ngay'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final folders = widget.appState.availableFolders;
    final tags = widget.appState.availableTags;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm tên tài liệu, thẻ hoặc chữ OCR bên trong...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        widget.appState.setSearchQuery('');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => widget.appState.setSearchQuery(val),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final folder = folders[index];
                final selected = widget.appState.selectedFolder == folder;
                return ChoiceChip(
                  label: Text(folder, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => widget.appState.setFolderFilter(folder),
                );
              },
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  final selected = widget.appState.selectedTag == tag;
                  return FilterChip(
                    label: Text('#$tag', style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      widget.appState.setTagFilter(v ? tag : null);
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDraftRecoveryBanner() {
    final draft = widget.appState.recoverableDrafts.first;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.restore_page_rounded,
            color: Colors.deepOrange,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bản nháp: ${draft.title} (${draft.pageCount} trang)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => widget.appState.deleteDocument(draft),
            child: const Text('Xóa'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final resumed = await widget.appState.resumeDraft(draft);
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentDetailScreen(
                    appState: widget.appState,
                    initialDocument: resumed,
                  ),
                ),
              );
            },
            child: const Text('Mở lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentList() {
    final docs = widget.appState.documents;
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 48,
                  color: Colors.teal,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.appState.searchQuery.isNotEmpty
                    ? 'Không tìm thấy tài liệu hoặc nội dung OCR khớp từ khóa.'
                    : 'Chưa có tài liệu nào',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bấm "Quét AI Tự Động" ở bên dưới — AI sẽ tự nhận diện mép giấy mọi góc độ (không cần căn khung), làm phẳng và đọc OCR Tiếng Việt.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final query = widget.appState.searchQuery;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final firstPage = doc.pages.isNotEmpty ? doc.pages.first : null;
        final thumbFile =
            firstPage != null ? File(firstPage.displayImagePath) : null;
        final matchedSnippet = query.trim().isNotEmpty
            ? DatabaseService.extractMatchingOcrSnippet(doc, query)
            : null;

        return Card(
          elevation: 0.8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.withOpacity(0.18)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentDetailScreen(
                    appState: widget.appState,
                    initialDocument: doc,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 60,
                      height: 80,
                      child: thumbFile != null && thumbFile.existsSync()
                          ? Image.file(
                              thumbFile,
                              key: ValueKey(firstPage!.displayImagePath),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.description_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${doc.pageCount} trang',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.teal,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dateFmt.format(doc.updatedAt),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (matchedSnippet != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              matchedSnippet,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Nút chia sẻ nhanh sang ứng dụng khác (Zalo, Gmail, Drive...)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Chia sẻ PDF qua ứng dụng khác',
                    icon: const Icon(Icons.share_outlined, size: 20),
                    onPressed: () {
                      widget.appState.exportSearchablePdf(
                        document: doc,
                        openShareSheet: true,
                      );
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Xóa tài liệu',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => widget.appState.deleteDocument(doc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
