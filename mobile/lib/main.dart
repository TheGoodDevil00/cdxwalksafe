import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/splash_screen.dart';

Future<void> main() async {
  // Ensures plugins (maps, location, storage) are initialized before runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase only when environment values are provided.
  const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  runApp(const WalkSafeApp());
}

class WalkSafeApp extends StatelessWidget {
  const WalkSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WalkSafe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
