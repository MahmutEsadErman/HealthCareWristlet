import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/providers/auth_provider.dart';
import '../presentation/screens/auth/splash_screen.dart';
import '../presentation/screens/auth/login_screen.dart';
import '../presentation/screens/auth/register_screen.dart';
import '../presentation/screens/patient/patient_dashboard_screen.dart';
import '../presentation/screens/patient/sensor_test_screen.dart';
import '../presentation/screens/patient/patient_alerts_screen.dart';
import '../presentation/screens/caregiver/caregiver_dashboard_screen.dart';
import '../presentation/screens/caregiver/patient_list_screen.dart';
import '../presentation/screens/caregiver/patient_detail_screen.dart';
import '../presentation/screens/caregiver/caregiver_alerts_screen.dart';
import '../presentation/screens/ble_connection_screen.dart';
import '../presentation/screens/sensor_data_screen.dart';

// Route paths
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';

  // Patient routes
  static const String patientDashboard = '/patient';
  static const String patientSensorTest = '/patient/sensor-test';
  static const String patientAlerts = '/patient/alerts';

  // BLE routes
  static const String bleConnection = '/ble-connection';
  static const String sensorData = '/sensor-data';

  // Caregiver routes
  static const String caregiverDashboard = '/caregiver';
  static const String caregiverPatients = '/caregiver/patients';
  static const String caregiverPatientDetail = '/caregiver/patients/:id';
  static const String caregiverAlerts = '/caregiver/alerts';
}

// GoRouter provider
final goRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,

    // Auth-based redirect logic
    redirect: (context, state) {
      final isAuthenticated = authState.isAuthenticated;
      final isLoading = authState.isLoading;
      final currentPath = state.matchedLocation;

      // Splash sayfasındayken loading bitene kadar bekle
      if (currentPath == AppRoutes.splash) {
        if (isLoading) {
          return null; // Loading sırasında splash'ta kal
        }

        // Loading bittikten sonra
        if (isAuthenticated) {
          // Kullanıcı tipine göre yönlendir
          final userType = authState.user?.userType;
          if (userType == 'patient') {
            return AppRoutes.patientDashboard;
          } else if (userType == 'caregiver') {
            return AppRoutes.caregiverDashboard;
          }
        } else {
          return AppRoutes.login;
        }
      }

      // Auth ekranlarındayken (login/register)
      final isOnAuthPage = currentPath == AppRoutes.login ||
                          currentPath == AppRoutes.register;

      if (isOnAuthPage) {
        // Zaten authenticated ise dashboard'a yönlendir
        if (isAuthenticated) {
          final userType = authState.user?.userType;
          if (userType == 'patient') {
            return AppRoutes.patientDashboard;
          } else if (userType == 'caregiver') {
            return AppRoutes.caregiverDashboard;
          }
        }
        return null; // Auth sayfasında kal
      }

      // Protected sayfalardayken
      if (!isAuthenticated && !isLoading) {
        return AppRoutes.login; // Login'e yönlendir
      }

      // Role-based access control
      final userType = authState.user?.userType;

      // Patient sayfalarına caregiver erişemez
      if (currentPath.startsWith('/patient') && userType != 'patient') {
        return AppRoutes.caregiverDashboard;
      }

      // Caregiver sayfalarına patient erişemez
      if (currentPath.startsWith('/caregiver') && userType != 'caregiver') {
        return AppRoutes.patientDashboard;
      }

      return null; // Redirect yok
    },

    routes: [
      // Splash / Initial Route
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Auth Routes
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),

      // Patient Routes
      GoRoute(
        path: AppRoutes.patientDashboard,
        builder: (context, state) => const PatientDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.patientSensorTest,
        builder: (context, state) => const SensorTestScreen(),
      ),
      GoRoute(
        path: AppRoutes.patientAlerts,
        builder: (context, state) => const PatientAlertsScreen(),
      ),

      // Caregiver Routes
      GoRoute(
        path: AppRoutes.caregiverDashboard,
        builder: (context, state) => const CaregiverDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.caregiverPatients,
        builder: (context, state) => const PatientListScreen(),
      ),
      GoRoute(
        path: AppRoutes.caregiverPatientDetail,
        builder: (context, state) {
          final patientId = state.pathParameters['id']!;
          return PatientDetailScreen(patientId: int.parse(patientId));
        },
      ),
      GoRoute(
        path: AppRoutes.caregiverAlerts,
        builder: (context, state) => const CaregiverAlertsScreen(),
      ),

      // BLE Routes
      GoRoute(
        path: AppRoutes.bleConnection,
        builder: (context, state) => const BleConnectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.sensorData,
        builder: (context, state) => const SensorDataScreen(),
      ),
    ],

    // Error page
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Sayfa bulunamadı: ${state.matchedLocation}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Ana Sayfaya Dön'),
            ),
          ],
        ),
      ),
    ),
  );
});