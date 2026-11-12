import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/scan_models.dart';
import '../services/database_service.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'document_detail_screen.dart';
import 'pdf_tools_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chính (Thư viện tài liệu) được tối ưu theo bản thiết kế Google Stitch
/// (`1._th_vi_n_t_i_li_u_home/code.html`):
/// - Thẻ Header Truy cập nhanh kèm huy hiệu Verified & 2 nút tròn (Camera AI, Bảo mật).
/// - Thanh tìm kiếm OCR Tiếng Việt / Chữ viết tay + dải Chip danh mục có biểu tượng riêng.
/// - Thẻ tài liệu có ảnh thu nhỏ 60x80 kèm huy hiệu số trang, dòng xem trước OCR nổi bật (`#FFFBEB`),
///   và 2 nút tròn Chia sẻ nhanh / Xóa.
/// - Thanh điều hướng dưới cùng (Bottom Dock) với nút trung tâm nổi `Quét AI Tự Động`.
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

  /// Quét tài liệu bằng AI:
  /// - Mặc định gọi trình quét AI gốc trên thiết bị (`CunningDocumentScanner`) tự bắt mép giấy và làm phẳng.
  /// - Nếu người dùng muốn dùng Camera AI không khung tích hợp hoặc thiết bị không hỗ trợ, chuyển sang `ScannerScreen`.
  Future<void> _startAiScan({bool forceBuiltInCamera = false}) async {
    List<String>? capturedPaths;

    if (!forceBuiltInCamera) {
      capturedPaths = await widget.appState.launchNativeAiScanner(maxPages: 24);
    }

    if (capturedPaths == null && mounted) {
      capturedPaths = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => const ScannerScreen(),
        ),
      );
    }

    if (capturedPaths == null || capturedPaths.isEmpty || !mounted) return;

    final doc = await widget.appState.createDocumentFromImages(
      sourceImagePaths: capturedPaths,
      alreadyCroppedByAi: !forceBuiltInCamera,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: doc,
        ),
      ),
    );
  }

  Future<void> _importImagesFromGallery() async {
    final picked = await _picker.pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    final paths = picked.map((x) => x.path).toList();
    final doc = await widget.appState.createDocumentFromImages(
      sourceImagePaths: paths,
      alreadyCroppedByAi: false,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(
          appState: widget.appState,
          initialDocument: doc,
        ),
      ),
    );
  }

  void _openPdfTools() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfToolsScreen(appState: widget.appState),
      ),
    );
  }

  void _openCreateFolderDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StitchTheme.surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Tạo thư mục mới',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Nhập tên thư mục (VD: Thuế 2026)',
            filled: true,
            fillColor: StitchTheme.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: StitchTheme.borderLight),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StitchTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              widget.appState.addCustomFolder(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Tạo thư mục'),
          ),
        ],
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: StitchTheme.surfaceWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      builder: (ctx) {
        return ListenableBuilder(
          listenable: widget.appState,
          builder: (ctx, _) {
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
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: StitchTheme.primaryContainerLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: StitchTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bảo mật & Chế độ Quét AI',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: StitchTheme.onSurface,
                                ),
                              ),
                              Text(
                                'Xử lý ngoại tuyến 100% On-Device',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: StitchTheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: BoxDecoration(
                        color: StitchTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: StitchTheme.borderLight),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(
                              Icons.fingerprint_rounded,
                              color: StitchTheme.primary,
                            ),
                            title: const Text(
                              'Khóa ứng dụng bằng Sinh trắc học',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: const Text(
                              'Yêu cầu Face ID / Vân tay khi mở kho tài liệu',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: widget.appState.biometricEnabled,
                            onChanged: (val) =>
                                widget.appState.toggleBiometricLock(val),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.center_focus_strong_rounded,
                              color: StitchTheme.primary,
                            ),
                            title: const Text(
                              'Mở Camera AI Không Khung (Built-in)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: const Text(
                              'Tự vẽ đa giác bám mép giấy thời gian thực không cần căn khung',
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              _startAiScan(forceBuiltInCamera: true);
                            },
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        if (widget.appState.isLocked) {
          return _buildLockedScreen();
        }

        return Scaffold(
          backgroundColor: StitchTheme.surface,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _buildStitchQuickAccessHeader(),
                    ),
                    const SizedBox(height: 12),
                    _buildSearchAndFilters(),
                    if (widget.appState.recoverableDrafts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildDraftRecoveryBanner(),
                      ),
                    Expanded(
                      child: _buildDocumentListSection(),
                    ),
                  ],
                ),
              ),
              if (widget.appState.isLoading)
                Container(
                  color: StitchTheme.surfaceProBase.withValues(alpha: 0.55),
                  alignment: Alignment.center,
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: StitchTheme.primary,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.appState.busyMessage ?? 'Đang xử lý...',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: StitchTheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _buildStitchBottomDockBar(),
        );
      },
    );
  }

  /// Header truy cập nhanh chuẩn Stitch (`bg-surface-white rounded-xl shadow-sm p-3`).
  Widget _buildStitchQuickAccessHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StitchTheme.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchTheme.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: StitchTheme.primaryContainerLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.document_scanner_rounded,
              color: StitchTheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Scan Tài Liệu AI',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: StitchTheme.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: StitchTheme.primary,
                    ),
                  ],
                ),
                SizedBox(height: 2),
                Text(
                  'Quét tự động • OCR Tiếng Việt • PDF',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: StitchTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _circleHeaderIconButton(
            icon: Icons.photo_camera_outlined,
            color: StitchTheme.primary,
            tooltip: 'Camera AI Không Khung',
            onTap: () => _startAiScan(forceBuiltInCamera: true),
          ),
          const SizedBox(width: 6),
          _circleHeaderIconButton(
            icon: Icons.verified_user_outlined,
            color: StitchTheme.onSurfaceVariant,
            tooltip: 'Bảo mật & Cài đặt',
            onTap: _openSettingsSheet,
          ),
        ],
      ),
    );
  }

  Widget _circleHeaderIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: StitchTheme.surfaceNeutralPill,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }

  /// Thanh điều hướng dưới cùng chuẩn Stitch với nút trung tâm nổi `Quét AI Tự Động`.
  Widget _buildStitchBottomDockBar() {
    return Container(
      decoration: BoxDecoration(
        color: StitchTheme.surfaceWhite.withValues(alpha: 0.96),
        border: const Border(
          top: BorderSide(color: StitchTheme.borderLight, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Nút trái: Nhập ảnh
              Expanded(
                child: InkWell(
                  onTap: _importImagesFromGallery,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 24,
                        color: StitchTheme.onSurfaceVariant,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Nhập ảnh',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: StitchTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Nút giữa nổi: Quét AI Tự Động
              Expanded(
                child: GestureDetector(
                  onTap: () => _startAiScan(forceBuiltInCamera: false),
                  onLongPress: () => _startAiScan(forceBuiltInCamera: true),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: StitchTheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: StitchTheme.primary.withValues(alpha: 0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.document_scanner_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Quét AI Tự Động',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: StitchTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Nút phải: Công cụ PDF & Bảo mật
              Expanded(
                child: InkWell(
                  onTap: _openPdfTools,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.handyman_outlined,
                        size: 24,
                        color: StitchTheme.onSurfaceVariant,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Công cụ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: StitchTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedScreen() {
    return Scaffold(
      backgroundColor: StitchTheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  StitchTheme.primaryContainerLight,
                  StitchTheme.surfaceWhite,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: StitchTheme.borderLight),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: StitchTheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: StitchTheme.statusSuccess,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Kho Tài Liệu Đang Khóa An Toàn',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Xác thực bằng Vân tay / Face ID hoặc mã thiết bị để mở thư viện tài liệu scan cá nhân.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: StitchTheme.onSurfaceVariant,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: StitchTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => widget.appState.unlockWithBiometrics(),
                    icon: const Icon(Icons.lock_open_rounded, size: 19),
                    label: const Text(
                      'Mở khóa ngay',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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

  IconData _iconForFolder(String folder) {
    final lower = folder.toLowerCase();
    if (lower.contains('tất cả')) return Icons.folder_open_rounded;
    if (lower.contains('hóa đơn') || lower.contains('biên lai')) {
      return Icons.receipt_long_rounded;
    }
    if (lower.contains('hợp đồng')) return Icons.history_edu_rounded;
    if (lower.contains('giấy tờ') || lower.contains('cccd')) {
      return Icons.badge_outlined;
    }
    if (lower.contains('công việc') || lower.contains('học tập')) {
      return Icons.menu_book_rounded;
    }
    return Icons.folder_outlined;
  }

  Widget _buildSearchAndFilters() {
    final folders = widget.appState.availableFolders;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: StitchTheme.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: StitchTheme.borderLight),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14, color: StitchTheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Tìm tên tài liệu, nội dung OCR, chữ viết tay...',
                hintStyle: const TextStyle(
                  fontSize: 13.5,
                  color: StitchTheme.outline,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: StitchTheme.outline,
                ),
                suffixIcon: widget.appState.searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          widget.appState.setSearchQuery('');
                        },
                      )
                    : const Icon(
                        Icons.auto_awesome_outlined,
                        size: 17,
                        color: StitchTheme.primaryDarkAccent,
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onChanged: widget.appState.setSearchQuery,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: folders.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, idx) {
                if (idx == folders.length) {
                  return InkWell(
                    onTap: _openCreateFolderDialog,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: StitchTheme.primaryContainerLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.create_new_folder_outlined,
                            size: 15,
                            color: StitchTheme.primary,
                          ),
                          SizedBox(width: 5),
                          Text(
                            '+ Thư mục',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: StitchTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final folder = folders[idx];
                final isSelected = widget.appState.selectedFolder == folder;
                return InkWell(
                  onTap: () => widget.appState.setSelectedFolder(folder),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? StitchTheme.primaryContainer
                          : StitchTheme.surfaceWhite,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected
                            ? StitchTheme.primaryContainer
                            : StitchTheme.borderLight,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconForFolder(folder),
                          size: 15,
                          color: isSelected
                              ? Colors.white
                              : StitchTheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          folder,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : StitchTheme.onSurfaceVariant,
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

  Widget _buildDraftRecoveryBanner() {
    final draft = widget.appState.recoverableDrafts.first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StitchTheme.surfaceWarningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: StitchTheme.statusWarning.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: StitchTheme.statusWarning.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.pending_actions_rounded,
              color: StitchTheme.statusWarning,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phiên quét chưa hoàn tất',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: StitchTheme.onSurface,
                  ),
                ),
                Text(
                  'Có 1 phiên chụp đang dở (${draft.pageCount} trang)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: StitchTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => widget.appState.deleteDocument(draft),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: StitchTheme.onSurfaceVariant,
            ),
            child: const Text('Bỏ', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () async {
              final resumed = await widget.appState.finalizeDocument(draft);
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DocumentDetailScreen(
                    appState: widget.appState,
                    initialDocument: resumed,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: StitchTheme.primaryContainer,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Mở lại',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentListSection() {
    final docs = widget.appState.documents;
    if (docs.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: StitchTheme.primaryContainerLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 34,
                  color: StitchTheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.appState.searchQuery.isNotEmpty
                    ? 'Không tìm thấy tài liệu hoặc nội dung OCR khớp từ khóa'
                    : 'Chưa có tài liệu nào trong thư viện',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: StitchTheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Bấm nút tròn "Quét AI Tự Động" ở thanh dưới — AI sẽ tự nhận diện 4 góc tờ giấy mọi góc độ (không cần căn khung), làm phẳng và đọc OCR Tiếng Việt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: StitchTheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              _buildProTipsDelightCard(),
            ],
          ),
        ),
      );
    }

    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final query = widget.appState.searchQuery;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: docs.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        // Dòng tiêu đề danh sách ("Tài liệu gần đây • X tệp")
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tài liệu gần đây',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: StitchTheme.surfaceNeutralPill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${docs.length} tệp',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: StitchTheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const Row(
                  children: [
                    Icon(
                      Icons.sort_rounded,
                      size: 16,
                      color: StitchTheme.primary,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Mới nhất',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // Thẻ Pro Tips ở cuối danh sách
        if (index == docs.length + 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _buildProTipsDelightCard(),
          );
        }

        final doc = docs[index - 1];
        final firstPage = doc.pages.isNotEmpty ? doc.pages.first : null;
        final thumbFile =
            firstPage != null ? File(firstPage.displayImagePath) : null;
        final matchedSnippet = query.trim().isNotEmpty
            ? DatabaseService.extractMatchingOcrSnippet(doc, query)
            : null;
        final firstOcrPreview = matchedSnippet ??
            (doc.combinedOcrText.trim().isNotEmpty
                ? doc.combinedOcrText
                    .trim()
                    .replaceAll(RegExp(r'\s+'), ' ')
                : null);

        return Container(
          decoration: BoxDecoration(
            color: StitchTheme.surfaceWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: StitchTheme.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 60x80 Thumbnail chuẩn Stitch với nhãn số trang ở đáy
                  SizedBox(
                    width: 60,
                    height: 80,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: thumbFile != null && thumbFile.existsSync()
                              ? Image.file(
                                  thumbFile,
                                  key: ValueKey(firstPage!.displayImagePath),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: StitchTheme.surfaceContainerLow,
                                  child: const Icon(
                                    Icons.description_outlined,
                                    color: StitchTheme.primary,
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: StitchTheme.statusSuccess,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 4,
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: StitchTheme.primaryContainerLight
                                  .withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${doc.pageCount} trang',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: StitchTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Cột thông tin giữa
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
                            color: StitchTheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: StitchTheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dateFmt.format(doc.updatedAt),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: StitchTheme.outline,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              '•',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: StitchTheme.outline,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                doc.combinedOcrText.trim().isNotEmpty
                                    ? 'Đã số hóa AI'
                                    : doc.folder,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: StitchTheme.statusSuccess,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        // Hộp trích đoạn OCR nổi bật chuẩn Stitch (`bg-surface-warning-light`)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: firstOcrPreview != null
                                ? StitchTheme.surfaceWarningLight
                                : StitchTheme.surfaceNeutralPill,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(
                                fontFamily: 'BeVietnamPro',
                                fontSize: 12,
                                color: StitchTheme.onSurface,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'OCR: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: StitchTheme.outline,
                                  ),
                                ),
                                TextSpan(
                                  text: firstOcrPreview ??
                                      'Chạm để xem hoặc quét AI OCR Tiếng Việt...',
                                  style: TextStyle(
                                    fontWeight: firstOcrPreview != null
                                        ? FontWeight.w500
                                        : FontWeight.w400,
                                    decoration: matchedSnippet != null
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                    decorationColor: StitchTheme.statusWarning,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Cột 2 nút tròn bên phải (Chia sẻ & Xóa)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _cardActionCircleButton(
                        icon: Icons.ios_share_rounded,
                        iconColor: StitchTheme.onSurfaceVariant,
                        bgColor: StitchTheme.surfaceNeutralPill,
                        tooltip: 'Chia sẻ PDF qua ứng dụng khác',
                        onTap: () {
                          widget.appState.exportSearchablePdf(
                            document: doc,
                            openShareSheet: true,
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      _cardActionCircleButton(
                        icon: Icons.delete_outline_rounded,
                        iconColor: StitchTheme.statusDangerStamp,
                        bgColor: StitchTheme.surfaceNeutralPill,
                        tooltip: 'Xóa tài liệu',
                        onTap: () => widget.appState.deleteDocument(doc),
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

  Widget _cardActionCircleButton({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 17, color: iconColor),
          ),
        ),
      ),
    );
  }

  Widget _buildProTipsDelightCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StitchTheme.primaryContainerLight.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: StitchTheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: StitchTheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tự động nhận diện góc 4 điểm',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.primary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Đưa camera vào tài liệu bất kỳ — thuật toán AI tự bắt mép giấy và lọc phẳng nếp gấp tự động.',
                  style: TextStyle(
                    fontSize: 12,
                    color: StitchTheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
