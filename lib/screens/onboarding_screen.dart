import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'library_screen.dart';

/// Màn hình giới thiệu (Onboarding Screen) chuẩn thiết kế Google Stitch:
/// - Hỗ trợ chuyển đổi ngôn ngữ tức thì (`🇻🇳 Tiếng Việt` / `🇬🇧 English`).
/// - 3 trang giới thiệu trực quan:
///   1) Quét AI Không Khung & Tự Bắt 4 Góc Mép Giấy (kèm Kính lúp 2.5x).
///   2) AI OCR Tiếng Việt Có Dấu & Chữ Viết Tay 100% Offline.
///   3) Ký Tên, Đóng Dấu, Công Cụ PDF & Bảo Mật Sinh Trắc Học.
class OnboardingScreen extends StatefulWidget {
  final AppState appState;
  final bool fromSettings;

  const OnboardingScreen({
    super.key,
    required this.appState,
    this.fromSettings = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  String _tr(String vi, String en) => widget.appState.tr(vi, en);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishOnboarding() async {
    await widget.appState.completeOnboarding();
    if (!mounted) return;
    if (widget.fromSettings) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LibraryScreen(appState: widget.appState),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.appState,
      builder: (context, _) {
        final slides = _buildSlidesData();
        final isLast = _currentPage == slides.length - 1;

        return Scaffold(
          backgroundColor: StitchTheme.surface,
          body: SafeArea(
            child: Column(
              children: [
                // 1. Top Header: Language Switcher & Skip Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      // Brand Emblem + Language Toggle Pill (VI / EN)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          'assets/branding/scand_icon_rounded.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'ScanD',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: StitchTheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: StitchTheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildLangChip(
                              code: 'vi',
                              label: '🇻🇳 Tiếng Việt',
                              selected: widget.appState.isVi,
                            ),
                            _buildLangChip(
                              code: 'en',
                              label: '🇬🇧 English',
                              selected: !widget.appState.isVi,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _finishOnboarding,
                        child: Text(
                          _tr('Bỏ qua', 'Skip'),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: StitchTheme.textSubtle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. PageView Slides
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: slides.length,
                    onPageChanged: (idx) =>
                        setState(() => _currentPage = idx),
                    itemBuilder: (context, index) {
                      return _buildSlidePage(slides[index], index);
                    },
                  ),
                ),

                // 3. Bottom Dots & Next / Get Started Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(slides.length, (idx) {
                          final active = idx == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: active ? 28 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? StitchTheme.primary
                                  : StitchTheme.outlineVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (isLast) {
                              _finishOnboarding();
                            } else {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: StitchTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            isLast
                                ? Icons.rocket_launch_rounded
                                : Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                          label: Text(
                            isLast
                                ? _tr(
                                    'Bắt đầu sử dụng ngay',
                                    'Get Started Now',
                                  )
                                : _tr('Tiếp tục', 'Next'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
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

  Widget _buildLangChip({
    required String code,
    required String label,
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () => widget.appState.setLanguageCode(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? StitchTheme.primary : StitchTheme.textSubtle,
          ),
        ),
      ),
    );
  }

  List<_OnboardingSlideData> _buildSlidesData() {
    return [
      _OnboardingSlideData(
        badge: _tr('CÔNG NGHỆ QUÉT AI KHÔNG KHUNG', 'FRAMELESS AI VISION'),
        title: _tr(
          'Tự Động Bắt Chuẩn 4 Góc Mép Giấy Trên Mọi Nền',
          'Precision 4-Corner Auto Detection on Any Surface',
        ),
        subtitle: _tr(
          'Không cần căn tài liệu vào khung cố định. AI tự động nhận diện mép giấy kể cả trên nền gạch sáng, làm phẳng phối cảnh A4 và hỗ trợ kính lúp 2.5x chính xác từng điểm ảnh.',
          'No rigid alignment frame needed. On-device AI detects paper edges even on bright tile floors, flattens perspective, and provides a 2.5x pixel-accurate magnifier loupe.',
        ),
        heroIcon: Icons.document_scanner_rounded,
        accentIcon: Icons.center_focus_strong_rounded,
        features: [
          _tr('✨ Tự chụp khi giữ yên tài liệu', '✨ Auto-shutter when steady'),
          _tr('🔍 Kính lúp 2.5x căn tâm chữ thập', '🔍 2.5x crosshair corner loupe'),
          _tr('📐 Tự làm phẳng & khử bóng đổ', '📐 Perspective warp & shadow removal'),
        ],
      ),
      _OnboardingSlideData(
        badge: _tr('HYBRID AI OCR TRÊN THIẾT BỊ', 'ON-DEVICE HYBRID AI OCR'),
        title: _tr(
          'Nhận Diện Tiếng Việt Có Dấu & Chữ Viết Tay',
          'Full Vietnamese Diacritics & Handwriting OCR',
        ),
        subtitle: _tr(
          'Kết hợp mô hình ngôn ngữ LSTM Tesseract 5 cùng Apple Vision Neural Engine ngay trên máy. Xuất PDF có lớp văn bản tìm kiếm, sao chép hoặc xuất file .TXT không cần Internet.',
          'Combines Tesseract 5 LSTM and Apple Vision Neural Engine directly on your device. Export searchable PDFs, copy or share .TXT files with zero cloud dependency.',
        ),
        heroIcon: Icons.translate_rounded,
        accentIcon: Icons.auto_awesome_rounded,
        features: [
          _tr('🇻🇳 Chính xác dấu Tiếng Việt & Tiếng Anh', '🇻🇳 Accurate Vietnamese & English OCR'),
          _tr('✍️ Nhận diện chữ in & chữ viết tay', '✍️ Printed & handwritten text support'),
          _tr('🛡️ 100% Offline • Không qua bên thứ 3', '🛡️ 100% Offline • Zero 3rd-party servers'),
        ],
      ),
      _OnboardingSlideData(
        badge: _tr('BỘ CÔNG CỤ STUDIO & BẢO MẬT', 'STUDIO TOOLS & BIOMETRIC VAULT'),
        title: _tr(
          'Ký Tên, Đóng Dấu Đỏ, Gộp/Tách PDF & Chia Sẻ 1 Chạm',
          'Sign, Red Stamp, Merge/Split PDF & 1-Tap Share',
        ),
        subtitle: _tr(
          'Ký tên mực xanh, đóng dấu chứng thực và kéo thả vào thùng rác để xóa nhanh. Chia sẻ tức thì qua Zalo, Gmail, AirDrop và bảo vệ kho hồ sơ bằng Face ID / Vân tay.',
          'Add signatures and official stamps with intuitive drag-to-trash deletion. Share in 1 tap to Zalo, Gmail, AirDrop, and lock your vault with Face ID / Fingerprint.',
        ),
        heroIcon: Icons.verified_user_rounded,
        accentIcon: Icons.draw_rounded,
        features: [
          _tr('🗑️ Kéo thả chữ ký/con dấu vào thùng rác để xóa', '🗑️ Drag signatures & stamps to trash to delete'),
          _tr('📄 Nhập, Gộp, Tách & Nén dung lượng PDF', '📄 Import, Merge, Split & Compress PDFs'),
          _tr('🔒 Khóa bảo mật sinh trắc học Face ID / Vân tay', '🔒 Biometric Face ID / Fingerprint lock'),
        ],
      ),
    ];
  }

  Widget _buildSlidePage(_OnboardingSlideData data, int index) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      child: Column(
        children: [
          // Visual Hero Card
          Container(
            width: double.infinity,
            height: 235,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF004F45), Color(0xFF00695C), Color(0xFF101316)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: StitchTheme.primary.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Subtle decorative grid circles
                Positioned(
                  right: -25,
                  top: -25,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9CF0FF).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -20,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5FFBD6).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                // Document frame illustration with 4 glowing nodes
                Container(
                  width: 145,
                  height: 175,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF9CF0FF),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF9CF0FF).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF5FFBD6),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          data.heroIcon,
                          size: 34,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 6,
                        width: 90,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5FFBD6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 5,
                        width: 65,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ],
                  ),
                ),
                // Floating Accent Badge
                Positioned(
                  bottom: 18,
                  right: 28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          data.accentIcon,
                          size: 15,
                          color: StitchTheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '0${index + 1} / 03',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StitchTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: StitchTheme.primaryContainerLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              data.badge,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: StitchTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: StitchTheme.textMain,
            ),
          ),
          const SizedBox(height: 10),

          // Subtitle
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.48,
              color: StitchTheme.textSubtle,
            ),
          ),
          const SizedBox(height: 18),

          // Feature Pills
          ...data.features.map(
            (f) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StitchTheme.borderLight),
              ),
              child: Text(
                f,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: StitchTheme.textMain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlideData {
  final String badge;
  final String title;
  final String subtitle;
  final IconData heroIcon;
  final IconData accentIcon;
  final List<String> features;

  const _OnboardingSlideData({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.heroIcon,
    required this.accentIcon,
    required this.features,
  });
}

