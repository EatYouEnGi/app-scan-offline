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

/// Màn hình chính Thư viện Tài liệu (Giao diện mặc định tiếng Việt):
/// - Tìm kiếm toàn văn theo tên, thẻ và nội dung chữ OCR bên trong các trang.
/// - Lọc theo thư mục và thẻ.
/// - Khôi phục bản nháp tự động nếu ứng dụng bị đóng giữa lúc quét.
/// - Khóa ứng dụng bằng Face ID / Touch ID / Sinh trắc học Android.
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

  Future<void> _startCameraScan() async {
    final capturedPaths = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => const ScannerScreen(),
      ),
    );
    if (capturedPaths == null || capturedPaths.isEmpty || !mounted) return;

    final draft = await widget.appState.startNewDraft();
    final populated = await widget.appState.addImagesToDocument(
      document: draft,
      sourceImagePaths: capturedPaths,
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
                    'Bảo mật & Chế độ Ngoại tuyến',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.fingerprint, size: 28),
                    title: const Text(
                      'Khóa ứng dụng bằng Face ID / Touch ID / Sinh trắc học',
                    ),
                    subtitle: const Text(
                      'Yêu cầu xác thực sinh trắc học khi mở kho tài liệu cá nhân',
                    ),
                    value: widget.appState.biometricLockEnabled,
                    onChanged: (val) {
                      widget.appState.toggleBiometricLock(val);
                    },
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.airplanemode_active, color: Colors.teal),
                    title: Text('Cam kết 100% Ngoại tuyến (Offline-First)'),
                    subtitle: Text(
                      'Ảnh gốc, PDF và dữ liệu OCR Tiếng Việt/Anh được xử lý và lưu trữ hoàn toàn trên thiết bị, hoạt động trọn vẹn ở chế độ máy bay.',
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
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan Tài Liệu Cá Nhân',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                ),
                Text(
                  '100% Ngoại tuyến • OCR Việt/Anh • PDF Nhiều trang',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfToolsScreen(appState: widget.appState),
                    ),
                  );
                },
                tooltip: 'Công cụ PDF & Kiểm chuẩn',
                icon: const Icon(Icons.handyman_outlined),
              ),
              IconButton(
                onPressed: _openSettingsSheet,
                tooltip: 'Bảo mật & Cài đặt',
                icon: const Icon(Icons.shield_outlined),
              ),
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'fab_gallery',
                onPressed: _importImagesFromGallery,
                tooltip: 'Nhập nhiều ảnh từ thư viện',
                child: const Icon(Icons.photo_library_outlined),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'fab_camera',
                onPressed: _startCameraScan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Quét tài liệu'),
              ),
            ],
          ),
        );
      },
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
              const Icon(Icons.lock_person_outlined, size: 72, color: Colors.teal),
              const SizedBox(height: 18),
              Text(
                'Kho Tài Liệu Đang Khóa',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Xác thực Face ID, Touch ID hoặc sinh trắc học để truy cập tài liệu cá nhân của bạn.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => widget.appState.unlockWithBiometrics(),
                icon: const Icon(Icons.fingerprint),
                label: const Text('Mở khóa bằng sinh trắc học'),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Tìm theo tên, thẻ hoặc nội dung OCR tiếng Việt/Anh...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        widget.appState.setSearchQuery('');
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (val) => widget.appState.setSearchQuery(val),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final folder = folders[index];
                final selected = widget.appState.selectedFolder == folder;
                return ChoiceChip(
                  label: Text(folder, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => widget.appState.setFolderFilter(folder),
                );
              },
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        children: [
          const Icon(Icons.restore_page_outlined, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phát hiện bản nháp chưa hoàn tất',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '${draft.title} (${draft.pageCount} trang) được lưu tự động trước khi đóng ứng dụng.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => widget.appState.deleteDocument(draft),
            child: const Text('Bỏ'),
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
            child: const Text('Khôi phục'),
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
              Icon(
                Icons.document_scanner_outlined,
                size: 72,
                color: Colors.teal.withOpacity(0.45),
              ),
              const SizedBox(height: 16),
              Text(
                widget.appState.searchQuery.isNotEmpty
                    ? 'Không tìm thấy tài liệu hoặc nội dung OCR khớp từ khóa.'
                    : 'Chưa có tài liệu nào trong thư viện.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Bấm nút "Quét tài liệu" để chụp tự động nhận diện mép giấy, chỉnh 4 góc, lọc màu và OCR tiếng Việt/Anh ngoại tuyến.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final query = widget.appState.searchQuery;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 66,
                      height: 88,
                      child: thumbFile != null && thumbFile.existsSync()
                          ? Image.file(
                              thumbFile,
                              key: ValueKey(firstPage!.displayImagePath),
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${doc.pageCount} trang • ${doc.folder} • ${dateFmt.format(doc.updatedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                        if (doc.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: doc.tags
                                .map(
                                  (t) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '#$t',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.teal,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        if (matchedSnippet != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Text(
                              'Khớp OCR — $matchedSnippet',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'export_pdf') {
                        await widget.appState.exportSearchablePdf(
                          document: doc,
                          openShareSheet: true,
                        );
                      } else if (action == 'delete') {
                        await widget.appState.deleteDocument(doc);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'export_pdf',
                        child: ListTile(
                          leading: Icon(Icons.picture_as_pdf),
                          title: Text('Xuất & Chia sẻ PDF'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(
                            'Xóa tài liệu',
                            style: TextStyle(color: Colors.red),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
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

