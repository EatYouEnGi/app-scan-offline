import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'document_detail_screen.dart';
import 'onboarding_screen.dart';
import 'pdf_tools_screen.dart';
import 'scanner_screen.dart';

/// Màn hình chính (Thư viện tài liệu) được tối ưu theo bản thiết kế Google Stitch
/// (`1._th_vi_n_t_i_li_u_home/code.html`):
/// - Thẻ Header Truy cập nhanh kèm huy hiệu Verified, nút chuyển đổi ngôn ngữ (`VI` / `EN`) & 2 nút tròn (Camera AI, Bảo mật).
/// - Thanh tìm kiếm OCR Tiếng Việt / Chữ viết tay + dải Chip danh mục có biểu tượng riêng.
/// - Thẻ tài liệu có ảnh thu nhỏ 60x80 kèm huy hiệu số trang, dòng xem trước OCR nổi bật (`#FFFBEB`),
///   và 2 nút tròn Chia sẻ nhanh / Xóa.
/// - Thanh điều hướng dưới cùng (Bottom Dock) với nút trung tâm nổi `Quét AI Tự Động`.
/// - Hỗ trợ song ngữ Tiếng Việt & Tiếng Anh.
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

  String _tr(String vi, String en) => widget.appState.tr(vi, en);

  String _displayFolderName(String folder) {
    if (widget.appState.isVi) return folder;
    switch (folder) {
      case 'Tất cả tài liệu':
        return 'All Documents';
      case 'Hóa đơn & Biên lai':
        return 'Receipts & Bills';
      case 'Hợp đồng & Pháp lý':
        return 'Contracts & Legal';
      case 'CCCD & Giấy tờ tùy thân':
        return 'ID & Passports';
      case 'Tài liệu học tập':
        return 'Study & Notes';
      default:
        return folder;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startAiScan() async {
    List<String>? capturedPaths =
        await widget.appState.launchNativeAiScanner(maxPages: 24);
    bool usedBuiltInFallback = false;

    if (capturedPaths == null && mounted) {
      usedBuiltInFallback = true;
      capturedPaths = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute(
          builder: (_) => ScannerScreen(isVi: widget.appState.isVi),
        ),
      );
    }

    if (capturedPaths == null || capturedPaths.isEmpty || !mounted) return;

    final doc = await widget.appState.createDocumentFromImages(
      sourceImagePaths: capturedPaths,
      alreadyCroppedByAi: !usedBuiltInFallback,
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
        title: Text(
          _tr('Tạo thư mục mới', 'Create New Folder'),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: _tr(
              'Nhập tên thư mục (VD: Thuế 2026)',
              'Enter folder name (e.g. Tax 2026)',
            ),
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
            child: Text(_tr('Hủy', 'Cancel')),
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
            child: Text(_tr('Tạo thư mục', 'Create')),
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _tr(
                                  'Cài đặt, Ngôn ngữ & Bảo mật',
                                  'Settings, Language & Security',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: StitchTheme.onSurface,
                                ),
                              ),
                              Text(
                                _tr(
                                  'Xử lý ngoại tuyến 100% On-Device',
                                  '100% On-Device Offline Processing',
                                ),
                                style: const TextStyle(
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
                          ListTile(
                            leading: const Icon(
                              Icons.language_rounded,
                              color: StitchTheme.primary,
                            ),
                            title: Text(
                              _tr('Ngôn ngữ hiển thị', 'App Language'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              widget.appState.isVi
                                  ? 'Đang dùng: Tiếng Việt (VI)'
                                  : 'Current: English (EN)',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'vi', label: Text('VI')),
                                ButtonSegment(value: 'en', label: Text('EN')),
                              ],
                              selected: {widget.appState.languageCode},
                              onSelectionChanged: (s) {
                                widget.appState.setLanguageCode(s.first);
                              },
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            secondary: const Icon(
                              Icons.fingerprint_rounded,
                              color: StitchTheme.primary,
                            ),
                            title: Text(
                              _tr(
                                'Khóa ứng dụng bằng Sinh trắc học',
                                'Biometric App Lock',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              _tr(
                                'Yêu cầu Face ID / Vân tay khi mở kho tài liệu',
                                'Require Face ID / Fingerprint when opening library',
                              ),
                              style: const TextStyle(fontSize: 12),
                            ),
                            value: widget.appState.biometricEnabled,
                            onChanged: (val) =>
                                widget.appState.toggleBiometricLock(val),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.auto_stories_outlined,
                              color: StitchTheme.primary,
                            ),
                            title: Text(
                              _tr(
                                'Xem lại giới thiệu ứng dụng (Onboarding)',
                                'View App Onboarding Guide',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => OnboardingScreen(
                                    appState: widget.appState,
                                    fromSettings: true,
                                  ),
                                ),
                              );
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
          extendBody: true,
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
                            widget.appState.busyMessage ??
                                _tr('Đang xử lý...', 'Processing...'),
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
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: StitchTheme.primary.withValues(alpha: 0.16),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                'assets/branding/scand_icon_rounded.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'ScanD',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: StitchTheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.verified_rounded,
                      size: 16,
                      color: StitchTheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _tr(
                    'Quét AI tự động • OCR Tiếng Việt • PDF',
                    'AI Auto Scan • Vietnamese OCR • PDF',
                  ),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: StitchTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Nút chuyển nhanh Ngôn ngữ VI / EN
          InkWell(
            onTap: () => widget.appState.toggleLanguage(),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
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

  Widget _buildStitchBottomDockBar() {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const double barHeight = 68;
    const double fabSize = 62;
    const double fabProtrude = 26;

    return SizedBox(
      height: barHeight + fabProtrude + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Thanh nền trắng với đường cong lõm mượt (Curved Notch) ở giữa giống hình mẫu
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: barHeight + bottomInset,
            child: CustomPaint(
              painter: _CurvedNotchBarPainter(
                backgroundColor: StitchTheme.surfaceWhite,
                borderColor: StitchTheme.borderLight,
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDockTabItem(
                        icon: Icons.folder_copy_rounded,
                        label: _tr('Thư viện', 'Library'),
                        active: true,
                        onTap: () => widget.appState.setFolderFilter('Tất cả tài liệu'),
                      ),
                    ),
                    Expanded(
                      child: _buildDockTabItem(
                        icon: Icons.photo_library_outlined,
                        label: _tr('Nhập ảnh', 'Import'),
                        active: false,
                        onTap: _importImagesFromGallery,
                      ),
                    ),
                    const SizedBox(width: 82),
                    Expanded(
                      child: _buildDockTabItem(
                        icon: Icons.handyman_outlined,
                        label: _tr('Công cụ', 'Tools'),
                        active: false,
                        onTap: _openPdfTools,
                      ),
                    ),
                    Expanded(
                      child: _buildDockTabItem(
                        icon: Icons.tune_rounded,
                        label: _tr('Cài đặt', 'Settings'),
                        active: false,
                        onTap: _openSettingsSheet,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Nút tròn Quét AI nổi hẳn lên trong phần lõm cong ở giữa
          Positioned(
            bottom: barHeight + bottomInset - fabSize + fabProtrude,
            child: GestureDetector(
              onTap: _startAiScan,
              child: Container(
                width: fabSize,
                height: fabSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00897B), StitchTheme.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: StitchTheme.primary.withValues(alpha: 0.36),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockTabItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? StitchTheme.primary : StitchTheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 23, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
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
                Text(
                  _tr('Kho Tài Liệu Đang Khóa An Toàn', 'Document Vault Locked'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _tr(
                    'Xác thực bằng Vân tay / Face ID hoặc mã thiết bị để mở thư viện tài liệu scan cá nhân.',
                    'Authenticate with Face ID / Fingerprint or device passcode to unlock your personal vault.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                    label: Text(
                      _tr('Mở khóa ngay', 'Unlock Now'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
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
                hintText: _tr(
                  'Tìm tên tài liệu, nội dung OCR, chữ viết tay...',
                  'Search document title, OCR text, handwriting...',
                ),
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.create_new_folder_outlined,
                            size: 15,
                            color: StitchTheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _tr('+ Thư mục', '+ Folder'),
                            style: const TextStyle(
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
                          _displayFolderName(folder),
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
                Text(
                  _tr('Phiên quét chưa hoàn tất', 'Unfinished Scan Session'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: StitchTheme.onSurface,
                  ),
                ),
                Text(
                  _tr(
                    'Có 1 phiên chụp đang dở (${draft.pageCount} trang)',
                    '1 draft session found (${draft.pageCount} pages)',
                  ),
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
            child: Text(
              _tr('Bỏ', 'Discard'),
              style: const TextStyle(fontSize: 12),
            ),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _tr('Mở lại', 'Resume'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 13),
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
                    ? _tr(
                        'Không tìm thấy tài liệu hoặc nội dung OCR khớp từ khóa',
                        'No documents or OCR text matched your search',
                      )
                    : _tr(
                        'Chưa có tài liệu nào trong thư viện',
                        'No documents in your library yet',
                      ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: StitchTheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  'Bấm nút tròn "Quét AI Tự Động" ở thanh dưới — AI sẽ tự nhận diện 4 góc tờ giấy mọi góc độ (không cần căn khung), làm phẳng và đọc OCR Tiếng Việt.',
                  'Tap the center "AI Auto Scan" button below — AI automatically detects 4 paper corners at any angle, flattens perspective, and runs on-device OCR.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 115),
      itemCount: docs.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      _tr('Tài liệu gần đây', 'Recent Documents'),
                      style: const TextStyle(
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
                        '${docs.length} ${_tr('tệp', 'files')}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: StitchTheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 16,
                      color: StitchTheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _tr('Mới nhất', 'Newest'),
                      style: const TextStyle(
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
                              '${doc.pageCount} ${_tr('trang', 'p')}',
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
                                    ? _tr('Đã số hóa AI', 'AI Digitized')
                                    : _displayFolderName(doc.folder),
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
                                      _tr(
                                        'Chạm để xem hoặc quét AI OCR Tiếng Việt...',
                                        'Tap to view or run on-device AI OCR...',
                                      ),
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
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _cardActionCircleButton(
                        icon: Icons.ios_share_rounded,
                        iconColor: StitchTheme.onSurfaceVariant,
                        bgColor: StitchTheme.surfaceNeutralPill,
                        tooltip: _tr(
                          'Chia sẻ PDF qua ứng dụng khác',
                          'Share PDF via other apps',
                        ),
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
                        tooltip: _tr('Xóa tài liệu', 'Delete document'),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    'Tự động nhận diện góc 4 điểm',
                    'Precision 4-Corner Auto Detection',
                  ),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: StitchTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _tr(
                    'Đưa camera vào tài liệu bất kỳ — thuật toán AI tự bắt mép giấy và lọc phẳng nếp gấp tự động.',
                    'Point the camera at any document — AI automatically detects paper boundaries and flattens perspective.',
                  ),
                  style: const TextStyle(
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

/// Vẽ thanh điều hướng dưới cùng có đường cong lõm mượt (Curved Notch) ở chính giữa
/// để ôm lấy nút tròn Quét AI nổi bật theo đúng mẫu thiết kế.
class _CurvedNotchBarPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;

  const _CurvedNotchBarPainter({
    required this.backgroundColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    const double notchRadius = 38.0;
    const double notchDepth = 30.0;
    const double curveSpread = 56.0;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(cx - curveSpread, 0)
      ..cubicTo(
        cx - notchRadius,
        0,
        cx - notchRadius + 6,
        notchDepth,
        cx,
        notchDepth,
      )
      ..cubicTo(
        cx + notchRadius - 6,
        notchDepth,
        cx + notchRadius,
        0,
        cx + curveSpread,
        0,
      )
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.14), 10, true);
    canvas.drawPath(path, Paint()..color = backgroundColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvedNotchBarPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor;
  }
}
