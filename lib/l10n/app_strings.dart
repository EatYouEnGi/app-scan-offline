import 'package:flutter/widgets.dart';

/// Hệ thống đa ngôn ngữ (Tiếng Việt & Tiếng Anh) toàn cục cho ứng dụng.
class AppStrings {
  final String lang;

  const AppStrings(this.lang);

  bool get isVi => lang != 'en';

  /// Trả về chuỗi theo ngôn ngữ hiện tại (`vi` hoặc `en`).
  String tr(String vi, String en) => isVi ? vi : en;

  static AppStrings of(BuildContext context, String langCode) =>
      AppStrings(langCode);
}

