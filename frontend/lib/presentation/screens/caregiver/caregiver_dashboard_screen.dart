import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/providers/auth_provider.dart';
import '../../../domain/providers/alert_provider.dart';
import '../../../domain/providers/patient_provider.dart';
import '../../../routes/app_router.dart';

class CaregiverDashboardScreen extends ConsumerWidget {
  const CaregiverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final unresolvedAlertCount = ref.watch(unresolvedAlertCountProvider);
    final patientState = ref.watch(patientProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver Dashboard'),
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          Icons.medical_services,
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
                              authState.user?.username ?? 'Caregiver',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.health_and_safety,
                        color: theme.colorScheme.primary,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Stats Row
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      icon: Icons.people,
                      label: 'Hastalar',
                      value: patientState.when(
                        data: (patients) => patients.length.toString(),
                        loading: () => '...',
                        error: (_, __) => '0',
                      ),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StatCard(
                      icon: Icons.notifications_active,
                      label: 'Aktif Alarmlar',
                      value: unresolvedAlertCount.toString(),
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Section Title
              Text(
                'Hızlı Erişim',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Navigation Cards
              _NavigationCard(
                icon: Icons.people_alt,
                title: 'Hastalarım',
                subtitle: 'Hasta listesi ve eşik ayarları',
                color: theme.colorScheme.primary,
                badge: patientState.when(
                  data: (patients) => patients.length > 0 ? patients.length : null,
                  loading: () => null,
                  error: (_, __) => null,
                ),
                onTap: () => context.push(AppRoutes.caregiverPatients),
              ),
              const SizedBox(height: 16),

              _NavigationCard(
                icon: Icons.warning_amber,
                title: 'Tüm Alarmlar',
                subtitle: 'Tüm hastaların alarmlarını görüntüle',
                color: theme.colorScheme.tertiary,
                badge: unresolvedAlertCount > 0 ? unresolvedAlertCount : null,
                onTap: () => context.push(AppRoutes.caregiverAlerts),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final int? badge;
  final VoidCallback onTap;

  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badge,
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 28,
                      color: color,
                    ),
                    // Badge
                    if (badge != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            badge! > 9 ? '9+' : badge.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onError,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
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
