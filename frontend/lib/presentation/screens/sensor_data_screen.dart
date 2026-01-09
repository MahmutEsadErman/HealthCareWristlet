import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/providers/ble_provider.dart';

/// Sensor Data Display Screen
/// Shows real-time heart rate, inactivity status, and panic button data from ESP32
class SensorDataScreen extends ConsumerWidget {
  const SensorDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heartRateData = ref.watch(heartRateStreamProvider);
    final inactivityData = ref.watch(inactivityStreamProvider);
    final buttonData = ref.watch(buttonStreamProvider);
    final connectionState = ref.watch(bleConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Data'),
        centerTitle: true,
        actions: [
          // Connection indicator
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: connectionState.when(
              data: (isConnected) => Icon(
                isConnected
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                color: isConnected ? Colors.green : Colors.red,
              ),
              loading: () => const CircularProgressIndicator(),
              error: (_, __) => const Icon(Icons.error, color: Colors.red),
            ),
          ),
        ],
      ),
      body: connectionState.when(
        data: (isConnected) {
          if (!isConnected) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Device not connected'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Heart Rate Card
                _buildHeartRateCard(heartRateData),
                const SizedBox(height: 16),

                // Inactivity Status Card (replaces IMU Card)
                _buildInactivityCard(inactivityData),
                const SizedBox(height: 16),

                // Panic Button Card
                _buildButtonCard(buttonData),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }

  Widget _buildHeartRateCard(AsyncValue heartRateData) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Colors.red[700]),
                const SizedBox(width: 8),
                const Text(
                  'Heart Rate',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            heartRateData.when(
              data: (data) => Column(
                children: [
                  Text(
                    '${data.value.toStringAsFixed(1)} BPM',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  if (data.timestamp != null)
                    Text(
                      'Last update: ${data.timestamp}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              loading: () => const Center(
                child: Text('Waiting for data...'),
              ),
              error: (_, __) => const Text('No data'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInactivityCard(AsyncValue inactivityData) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.accessibility_new, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Activity Status',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            inactivityData.when(
              data: (data) => Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: data.isInactive
                          ? Colors.orange[100]
                          : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          data.isInactive
                              ? Icons.warning_amber_rounded
                              : Icons.directions_walk,
                          size: 48,
                          color: data.isInactive
                              ? Colors.orange[700]
                              : Colors.green[700],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          data.isInactive ? 'INACTIVITY DETECTED' : 'Active',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: data.isInactive
                                ? Colors.orange[700]
                                : Colors.green[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data.isInactive
                              ? 'No movement detected for 1 minute'
                              : 'Normal activity detected',
                          style: TextStyle(
                            fontSize: 14,
                            color: data.isInactive
                                ? Colors.orange[600]
                                : Colors.green[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (data.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Last update: ${data.timestamp}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
              loading: () => Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Monitoring...',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Analyzing movement patterns (1 min window)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              error: (_, __) => const Text('No data'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonCard(AsyncValue buttonData) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emergency, color: Colors.orange[700]),
                const SizedBox(width: 8),
                const Text(
                  'Panic Button',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            buttonData.when(
              data: (data) => Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: data.panicButtonStatus
                          ? Colors.red[100]
                          : Colors.green[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          data.panicButtonStatus
                              ? Icons.warning_amber
                              : Icons.check_circle,
                          size: 40,
                          color: data.panicButtonStatus
                              ? Colors.red[700]
                              : Colors.green[700],
                        ),
                        const SizedBox(width: 16),
                        Text(
                          data.panicButtonStatus ? 'PRESSED' : 'Normal',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: data.panicButtonStatus
                                ? Colors.red[700]
                                : Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (data.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Last update: ${data.timestamp}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                ],
              ),
              loading: () => const Center(
                child: Text('Waiting for data...'),
              ),
              error: (_, __) => const Text('No data'),
            ),
          ],
        ),
      ),
    );
  }
}
