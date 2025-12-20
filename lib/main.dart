import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'routes/app_router.dart';
import 'presentation/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'data/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Notification service'i başlat
  await NotificationService().initialize();

  runApp(
    // ProviderScope - Riverpod için gerekli
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // GoRouter provider'ı al
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Healthcare Wristlet',
      debugShowCheckedModeBanner: false,

      // Theme
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      // Router configuration
      routerConfig: router,
    );
  }
}
