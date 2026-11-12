import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/library_screen.dart';
import 'state/app_state.dart';
import 'theme/stitch_theme.dart';

class AppScanApp extends StatelessWidget {
  final AppState appState;

  const AppScanApp({
    super.key,
    required this.appState,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scan Tài Liệu AI',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi', 'VN'),
      supportedLocales: const [
        Locale('vi', 'VN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: StitchTheme.buildLightTheme(),
      darkTheme: StitchTheme.buildDarkTheme(),
      themeMode: ThemeMode.light,
      home: LibraryScreen(appState: appState),
    );
  }
}
