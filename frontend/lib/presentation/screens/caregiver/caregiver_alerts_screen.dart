import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../domain/providers/alert_provider.dart';
import '../../../domain/providers/patient_provider.dart';
import '../../../data/models/alert_model.dart';

class CaregiverAlertsScreen extends ConsumerStatefulWidget {
  const CaregiverAlertsScreen({super.key});

  @override
  ConsumerState<CaregiverAlertsScreen> createState() =>
      _CaregiverAlertsScreenState();
}

class _CaregiverAlertsScreenState extends ConsumerState<CaregiverAlertsScreen> {
  Future<void> _refreshAlerts() async {
    await ref.read(alertProvider.notifier).refresh();
  }

  Future<void> _resolveAlert(int alertId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alarm Çöz'),
        content: const Text('Bu alarmı çözüldü olarak işaretlemek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çöz'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final success = await ref.read(alertProvider.notifier).resolveAlert(alertId);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alarm çözüldü'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alertState = ref.watch(alertProvider);
    final patientState = ref.watch(patientProvider);

    // Hasta ID'den hasta adı bulan helper fonksiyon
    String getPatientName(int patientId) {
      return patientState.when(
        data: (patients) {
          try {
            final patient = patients.firstWhere((p) => p.userId == patientId);
            return patient.username;
          } catch (e) {
            return 'Hasta #$patientId';
          }
        },
        loading: () => 'Hasta #$patientId',
        error: (_, __) => 'Hasta #$patientId',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tüm Alarmlar'),
        actions: [
          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _refreshAlerts,
          ),
        ],
      ),
      body: alertState.when(
        // Loading state
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),

        // Error state
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Hata',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  error.toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _refreshAlerts,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),

        // Data loaded
        data: (alerts) {
          if (alerts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Alarm Yok',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Henüz alarm bulunmuyor',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshAlerts,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length + 1,
              itemBuilder: (context, index) {
                // Info Card at the top
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tüm hastaların alarmları gösterilmektedir. 30 saniyede bir otomatik güncellenir.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final alert = alerts[index - 1];
                return _AlertCard(
                  alert: alert,
                  patientName: getPatientName(alert.patientId),
                  onTap: () => _showAlertDetails(context, alert, getPatientName(alert.patientId)),
                  onResolve: alert.isResolved
                      ? null
                      : () => _resolveAlert(alert.id),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showAlertDetails(BuildContext context, Alert alert, String patientName) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  alert.getIcon(),
                  color: alert.getColor(),
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    alert.getTypeTitle(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _DetailRow(
              icon: Icons.person,
              label: 'Hasta',
              value: patientName,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.calendar_today,
              label: 'Tarih',
              value: DateFormat('dd.MM.yyyy HH:mm').format(alert.timestamp),
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.info_outline,
              label: 'Durum',
              value: alert.isResolved ? 'Çözüldü' : 'Aktif',
            ),
            if (alert.resolvedAt != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.check_circle,
                label: 'Çözülme Tarihi',
                value:
                    DateFormat('dd.MM.yyyy HH:mm').format(alert.resolvedAt!),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (!alert.isResolved)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _resolveAlert(alert.id);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Çöz'),
                    ),
                  ),
                if (!alert.isResolved) const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Alert alert;
  final String patientName;
  final VoidCallback onTap;
  final VoidCallback? onResolve;

  const _AlertCard({
    required this.alert,
    required this.patientName,
    required this.onTap,
    this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alertColor = alert.getColor();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // Alert Icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: alertColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      alert.getIcon(),
                      color: alertColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Alert Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.getTypeTitle(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hasta: $patientName',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          DateFormat('dd.MM.yyyy HH:mm').format(alert.timestamp),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: alert.isResolved
                          ? theme.colorScheme.tertiaryContainer
                          : alertColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      alert.isResolved ? 'Çözüldü' : 'Aktif',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: alert.isResolved
                            ? theme.colorScheme.onTertiaryContainer
                            : alertColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // Resolve Button
              if (onResolve != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Çöz'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
