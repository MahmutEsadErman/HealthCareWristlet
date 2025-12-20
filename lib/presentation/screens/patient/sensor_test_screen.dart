import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/providers/sensor_provider.dart';

class SensorTestScreen extends ConsumerWidget {
  const SensorTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sensorState = ref.watch(sensorProvider);

    // Success/Error mesajlarını göster
    ref.listen<SensorState>(sensorProvider, (previous, next) {
      if (next.lastResponse != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.lastResponse!),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: theme.colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acil durum simülasyonları (debug için eklendi kaldıracağız)'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Acil durum '
                                '(debug için eklendi kaldıracağız)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Heart Rate Tests
              _SectionHeader(
                icon: Icons.favorite,
                title: 'Kalp Hızı Testleri',
                color: Colors.red,
              ),
              const SizedBox(height: 12),

              _TestButton(
                icon: Icons.arrow_upward,
                label: 'Yüksek Kalp Hızı (150 bpm)',
                subtitle: ' ',
                color: Colors.red,
                hasWarning: true,
                isLoading: sensorState.isLoading &&
                    sensorState.lastSentType == SensorType.heartRate,
                onPressed: () =>
                    ref.read(sensorProvider.notifier).sendHighHeartRate(),
              ),
              const SizedBox(height: 12),

              _TestButton(
                icon: Icons.arrow_downward,
                label: 'Düşük Kalp Hızı (30 bpm)',
                subtitle: ' ',
                color: Colors.orange,
                hasWarning: true,
                isLoading: sensorState.isLoading &&
                    sensorState.lastSentType == SensorType.heartRate,
                onPressed: () =>
                    ref.read(sensorProvider.notifier).sendLowHeartRate(),
              ),
              const SizedBox(height: 12),

              _TestButton(
                icon: Icons.check_circle,
                label: 'Normal Kalp Hızı (75 bpm)',
                subtitle: ' ',
                color: Colors.green,
                isLoading: sensorState.isLoading &&
                    sensorState.lastSentType == SensorType.heartRate,
                onPressed: () =>
                    ref.read(sensorProvider.notifier).sendNormalHeartRate(),
              ),
              const SizedBox(height: 32),

              // Panic Button Test
              _SectionHeader(
                icon: Icons.emergency,
                title: 'Panik Butonu',
                color: Colors.red.shade900,
              ),
              const SizedBox(height: 12),

              _TestButton(
                icon: Icons.warning,
                label: 'Panik Butonu Tetikle',
                subtitle: 'Acil durum alarmı oluşturur',
                color: Colors.red.shade900,
                hasWarning: true,
                isLoading: sensorState.isLoading &&
                    sensorState.lastSentType == SensorType.button,
                onPressed: () =>
                    ref.read(sensorProvider.notifier).sendPanicButton(),
              ),
              const SizedBox(height: 24),

              // Status Card
              if (sensorState.lastResponse != null || sensorState.error != null)
                Card(
                  color: sensorState.error != null
                      ? theme.colorScheme.errorContainer
                      : theme.colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              sensorState.error != null
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              size: 20,
                              color: sensorState.error != null
                                  ? theme.colorScheme.onErrorContainer
                                  : theme.colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Son Durum',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: sensorState.error != null
                                    ? theme.colorScheme.onErrorContainer
                                    : theme.colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sensorState.lastResponse ?? sensorState.error ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: sensorState.error != null
                                ? theme.colorScheme.onErrorContainer
                                : theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _TestButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool hasWarning;
  final bool isLoading;
  final VoidCallback onPressed;

  const _TestButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.hasWarning = false,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (hasWarning) ...[
                      const Icon(
                        Icons.warning_amber,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),

          // Arrow
          Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: Colors.white.withOpacity(0.8),
          ),
        ],
      ),
    );
  }
}
