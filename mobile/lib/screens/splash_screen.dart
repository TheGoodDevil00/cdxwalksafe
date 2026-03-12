import 'package:flutter/material.dart';

import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goToHome();
  }

  Future<void> _goToHome() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[Color(0xFF00695C), Color(0xFF26A69A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.shield_outlined, color: Colors.white, size: 76),
              SizedBox(height: 14),
              Text(
                'WalkSafe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Safer routes for safer walks',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
