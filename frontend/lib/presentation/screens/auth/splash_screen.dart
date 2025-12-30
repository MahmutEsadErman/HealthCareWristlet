import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Icon/Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.favorite_border,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),

            // App Name
            Text(
              'Healthcare',
              style: theme.textTheme.headlineLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Wristlet',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 48),

            // Loading Indicator
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 16),

            // Loading Text
            Text(
              'Yükleniyor...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
