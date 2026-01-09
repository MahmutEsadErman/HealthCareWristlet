import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer' as developer;
import '../../../domain/providers/auth_provider.dart';
import '../../../domain/providers/sensor_provider.dart';
import '../../../domain/providers/ble_provider.dart';
import '../../../routes/app_router.dart';

class PatientDashboardScreen extends ConsumerWidget {
  const PatientDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final sensorState = ref.watch(sensorProvider);
    final connectionState = ref.watch(bleConnectionStateProvider);
    final heartRateData = ref.watch(heartRateStreamProvider);
    final inactivityData = ref.watch(inactivityStreamProvider);
    final buttonData = ref.watch(buttonStreamProvider);

    // Sensor state değişikliklerini dinle (başarı/hata mesajları için)
    ref.listen<SensorState>(sensorProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: theme.colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(sensorProvider.notifier).clearError();
      } else if (next.lastResponse != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.lastResponse!),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        ref.read(sensorProvider.notifier).clearSuccess();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
        actions: [
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: () async {
              // Confirm dialog
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Çıkış Yap'),
                  content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('İptal'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Çıkış Yap'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await ref.read(authProvider.notifier).logout();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.person,
                          size: 32,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hoş Geldiniz,',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              authState.user?.username ?? 'Patient',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.favorite,
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Real-time Sensor Data Section
              Text(
                'Canlı Sensör Verileri',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Connection Status Card
              connectionState.when(
                data: (isConnected) => Card(
                  color: isConnected
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: isConnected ? Colors.green : Colors.orange,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isConnected
                                    ? 'Bağlantı Aktif'
                                    : 'Bağlantı Yok',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isConnected
                                      ? Colors.green.shade800
                                      : Colors.orange.shade800,
                                ),
                              ),
                              Text(
                                isConnected
                                    ? 'Bileklik bağlı ve veri iletiyor'
                                    : 'Bilekliğe bağlanmak için Bluetooth\'a gidin',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isConnected
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isConnected)
                          IconButton(
                            icon: const Icon(Icons.settings_bluetooth),
                            onPressed: () =>
                                context.push(AppRoutes.bleConnection),
                            color: Colors.orange.shade700,
                          ),
                      ],
                    ),
                  ),
                ),
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              // Heart Rate Card
              heartRateData.when(
                data: (data) => Card(
                  color: theme.colorScheme.errorContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.favorite,
                              color: Colors.red.shade700,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Kalp Hızı',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${data.value.toInt()} BPM',
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (data.timestamp != null)
                          Text(
                            'Son güncelleme: ${_formatTime(data.timestamp!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                loading: () => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.favorite, color: Colors.grey.shade400),
                            const SizedBox(width: 12),
                            Text(
                              'Kalp Hızı',
                              style: theme.textTheme.titleLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Veri bekleniyor...'),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              // Inactivity Alert Card (Hareketsizlik Uyarısı)
              inactivityData.when(
                data: (data) => Card(
                  color: data.isInactive
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: data.isInactive
                                ? Colors.orange.shade100
                                : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            data.isInactive
                                ? Icons.accessibility_new_rounded
                                : Icons.directions_walk_rounded,
                            color: data.isInactive
                                ? Colors.orange.shade700
                                : Colors.green.shade700,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hareketsizlik Uyarısı',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: data.isInactive
                                      ? Colors.orange.shade200
                                      : Colors.green.shade200,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  data.isInactive
                                      ? '⚠️ HAREKETSİZLİK TESPİT EDİLDİ'
                                      : '✓ Normal Aktivite',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: data.isInactive
                                        ? Colors.orange.shade900
                                        : Colors.green.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (data.isInactive)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Bakıcınız bilgilendirildi',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              if (data.timestamp != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Güncelleme: ${_formatTime(data.timestamp!)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                loading: () => Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.accessibility_new_rounded,
                            color: Colors.grey.shade400,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hareketsizlik Uyarısı',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Durum bekleniyor...',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),

              // Button Status Card
              buttonData.when(
                data: (data) => Card(
                  color: data.panicButtonStatus
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(
                          data.panicButtonStatus
                              ? Icons.warning_rounded
                              : Icons.check_circle,
                          color: data.panicButtonStatus
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Panik Butonu',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data.panicButtonStatus
                                    ? 'BASILDI - ACİL DURUM!'
                                    : 'Normal',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: data.panicButtonStatus
                                      ? Colors.red.shade700
                                      : Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (data.timestamp != null)
                                Text(
                                  'Son durum: ${_formatTime(data.timestamp!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                loading: () => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded,
                            color: Colors.grey.shade400),
                        const SizedBox(width: 16),
                        const Text('Panik butonu durumu bekleniyor...'),
                      ],
                    ),
                  ),
                ),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 32),

              // Emergency Button (Center and Large)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.error,
                      theme.colorScheme.error.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.error.withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: sensorState.isLoading
                        ? null
                        : () async {
                            final result = await ref
                                .read(sensorProvider.notifier)
                                .sendPanicButton();
                            if (result && context.mounted) {
                              _showEmergencyDialog(context);
                            }
                          },
                    borderRadius: BorderRadius.circular(24),
                    child: Center(
                      child: sensorState.isLoading &&
                              sensorState.lastSentType == SensorType.button
                          ? CircularProgressIndicator(
                              color: theme.colorScheme.onError,
                              strokeWidth: 3,
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.warning_rounded,
                                  size: 90,
                                  color: theme.colorScheme.onError,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'ACİL DURUM',
                                  style: theme.textTheme.headlineLarge?.copyWith(
                                    color: theme.colorScheme.onError,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Butona basın',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onError
                                        .withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // BLE Connection Card - NEW
              _NavigationCard(
                icon: Icons.bluetooth,
                title: 'Bluetooth Bağlantısı',
                subtitle: 'ESP32 bilekliğe bağlan',
                color: Colors.blue,
                onTap: () {
                  developer.log('PatientDashboard: BLE card tapped', name: 'BLE');
                  context.push(AppRoutes.bleConnection);
                },
              ),
              const SizedBox(height: 16),

              // Section Title
              Text(
                'Acil durum simülasyonları (debug için eklendi kaldıracağız)',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Sensor Test Card
              _NavigationCard(
                icon: Icons.sensors,
                title: 'Sensör Testi',
                subtitle: 'Manuel veri gönderimi ve test',
                color: theme.colorScheme.primary,
                onTap: () => context.push(AppRoutes.patientSensorTest),
              ),
            ],
          ),
        ),
      ),
    );
  }



  // Helper method to format timestamp
  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return '${difference.inSeconds} saniye önce';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes} dakika önce';
      } else {
        return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }

  void _showEmergencyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.check_circle,
          color: Colors.green,
          size: 56,
        ),
        title: const Text('Acil Durum Bildirimi Gönderildi'),
        content: const Text(
          'Panik butonu sinyali başarıyla gönderildi. Bakıcınız bilgilendirilecektir.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              // Icon Container
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),

              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow Icon
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
