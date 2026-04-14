import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  // Ensures plugins (maps, location, storage) are initialized before runApp.
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    AppConfig.apiBaseUrl.isNotEmpty,
    'API_BASE_URL must be set. Run flutter with: --dart-define=API_BASE_URL=http://...',
  );
  assert(
    AppConfig.maptilerApiKey.isNotEmpty,
    'MAPTILER_API_KEY must be set via --dart-define=MAPTILER_API_KEY=your-key',
  );
  assert(
    AppConfig.supabaseUrl.isNotEmpty,
    'SUPABASE_URL must be set via --dart-define',
  );
  assert(
    AppConfig.supabaseAnonKey.isNotEmpty,
    'SUPABASE_ANON_KEY must be set via --dart-define',
  );

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  await Hive.initFlutter();
  await Hive.openBox('walksafe_saved_places');

  runApp(const WalkSafeApp());
}

class WalkSafeApp extends StatelessWidget {
  const WalkSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2E7CF6),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'WalkSafe',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFF142032),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        textTheme: baseTheme.textTheme.apply(
          bodyColor: const Color(0xFF142032),
          displayColor: const Color(0xFF142032),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF142032),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
