import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/stitch_theme.dart';
import 'library_screen.dart';
import 'onboarding_screen.dart';

/// Màn hình khởi động (Splash Screen) chuẩn thiết kế Google Stitch:
/// - Biểu tượng máy quét AI chuyển sắc kèm hiệu ứng tia laser quét dọc.
/// - Tự động kiểm tra trạng thái khởi tạo kho dữ liệu & chuyển tiếp mượt sang
///   Onboarding Screen (nếu mở lần đầu) hoặc Library Screen.
class SplashScreen extends StatefulWidget {
  final AppState appState;

  const SplashScreen({
    super.key,
    required this.appState,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _laserCtrl;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _laserCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _waitAndNavigate();
  }

  Future<void> _waitAndNavigate() async {
    final minDelay = Future<void>.delayed(const Duration(milliseconds: 1450));
    while (!widget.appState.isInitialized) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await minDelay;
    if (!mounted || _navigated) return;
    _navigated = true;

    final target = widget.appState.hasCompletedOnboarding
        ? LibraryScreen(appState: widget.appState)
        : OnboardingScreen(appState: widget.appState);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (_, __, ___) => target,
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(opacity: anim, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _laserCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVi = widget.appState.isVi;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0A1229),
              Color(0xFF0F1B3D),
              Color(0xFF0B2B3C),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Official ScanD-V2 Brand Icon with Animated AI Laser Sweep
              SizedBox(
                width: 148,
                height: 148,
                child: AnimatedBuilder(
                  animation: _laserCtrl,
                  builder: (context, _) {
                    final t = _laserCtrl.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glowing halo
                        Container(
                          width: 148,
                          height: 148,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF14B8A6)
                                .withValues(alpha: 0.10 + 0.08 * t),
                            border: Border.all(
                              color: const Color(0xFF5EEAD4)
                                  .withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Official ScanD-V2 Icon (`assets/branding/scand_icon_rounded.png`)
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF14B8A6)
                                    .withValues(alpha: 0.38),
                                blurRadius: 26,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/branding/scand_icon_rounded.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Sweeping AI Laser Bar
                        Positioned(
                          top: 24 + t * 92,
                          child: Container(
                            width: 96,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5EEAD4),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0xFF14B8A6),
                                  blurRadius: 10,
                                  spreadRadius: 1.5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),

              // Official ScanD Horizontal Logo + Verified Badge
              SizedBox(
                height: 44,
                child: Image.asset(
                  'assets/branding/scand_logo_on_dark.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isVi
                        ? 'ScanD • Quét Tài Liệu AI Thông Minh'
                        : 'ScanD • Smart AI Document Scanner',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF5EEAD4),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF5EEAD4),
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  isVi
                      ? 'Nhận diện 4 góc tài liệu chuẩn xác & AI OCR Tiếng Việt / Chữ viết tay 100% trên thiết bị'
                      : 'Precision 4-Corner Document Detection & On-Device Vietnamese / Handwriting AI OCR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // Loading indicator + Security Pill
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Color(0xFF5EEAD4),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_rounded,
                      size: 15,
                      color: Color(0xFF5EEAD4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isVi
                          ? '100% On-Device AI • Bảo mật ngoại tuyến'
                          : '100% On-Device AI • Offline Privacy',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: StitchTheme.primaryFixed,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

