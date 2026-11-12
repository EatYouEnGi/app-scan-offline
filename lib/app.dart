import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/library_screen.dart';
import 'state/app_state.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'BeVietnamPro',
        colorSchemeSeed: const Color(0xFF00695C),
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'BeVietnamPro',
        colorSchemeSeed: const Color(0xFF00897B),
        brightness: Brightness.dark,
        visualDensity: VisualDensity.standard,
      ),
      home: LibraryScreen(appState: appState),
    );
  }
}
