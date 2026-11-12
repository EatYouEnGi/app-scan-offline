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
              Color(0xFF003B33),
              Color(0xFF004F45),
              Color(0xFF101316),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Animated AI Document Scanner Emblem
              SizedBox(
                width: 124,
                height: 124,
                child: AnimatedBuilder(
                  animation: _laserCtrl,
                  builder: (context, _) {
                    final t = _laserCtrl.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer glowing halo
                        Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF00DAF3)
                                .withValues(alpha: 0.08 + 0.06 * t),
                            border: Border.all(
                              color: const Color(0xFF9CF0FF)
                                  .withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Core rounded scanner badge
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00695C), Color(0xFF004F45)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: const Color(0xFF5FFBD6),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00DAF3)
                                    .withValues(alpha: 0.35),
                                blurRadius: 22,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.document_scanner_rounded,
                            size: 46,
                            color: Colors.white,
                          ),
                        ),
                        // Sweeping AI Laser Bar
                        Positioned(
                          top: 22 + t * 76,
                          child: Container(
                            width: 78,
                            height: 3,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5FFBD6),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0xFF00DAF3),
                                  blurRadius: 8,
                                  spreadRadius: 1,
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
              const SizedBox(height: 24),

              // Brand Title & Verified Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isVi ? 'Scan Tài Liệu AI' : 'AI Document Scanner',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.verified_rounded,
                    color: Color(0xFF5FFBD6),
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  isVi
                      ? 'Nhận diện 4 góc mép giấy & AI OCR Tiếng Việt / Chữ viết tay 100% trên thiết bị'
                      : 'Precision 4-Corner Edge Detection & On-Device Vietnamese / Handwriting AI OCR',
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
                  color: Color(0xFF5FFBD6),
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
                      color: Color(0xFF5FFBD6),
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
