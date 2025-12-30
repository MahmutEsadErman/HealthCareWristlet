import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/providers/ble_provider.dart';
import 'dart:math' as math;

/// Sensor Data Display Screen
/// Shows real-time heart rate, IMU, and button data from ESP32
class SensorDataScreen extends ConsumerWidget {
  const SensorDataScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heartRateData = ref.watch(heartRateStreamProvider);
    final imuData = ref.watch(imuStreamProvider);
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

                // IMU Data Card
                _buildIMUCard(imuData),
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

  Widget _buildIMUCard(AsyncValue imuData) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'IMU Data',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            imuData.when(
              data: (data) => Column(
                children: [
                  _buildIMURow('Accelerometer X', data.xAxis, 'm/s²'),
                  _buildIMURow('Accelerometer Y', data.yAxis, 'm/s²'),
                  _buildIMURow('Accelerometer Z', data.zAxis, 'm/s²'),
                  const Divider(height: 24),
                  if (data.gx != null)
                    _buildIMURow('Gyroscope X', data.gx!, 'rad/s'),
                  if (data.gy != null)
                    _buildIMURow('Gyroscope Y', data.gy!, 'rad/s'),
                  if (data.gz != null)
                    _buildIMURow('Gyroscope Z', data.gz!, 'rad/s'),
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

  Widget _buildIMURow(String label, double value, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Text(
            '${value.toStringAsFixed(3)} $unit',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
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
