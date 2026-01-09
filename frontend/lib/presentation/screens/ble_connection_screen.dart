import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/providers/ble_provider.dart';

/// BLE Connection Screen
/// Scans and connects to the ESP32 wristlet
class BleConnectionScreen extends ConsumerWidget {
  const BleConnectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    developer.log('BleConnectionScreen build()', name: 'BLE');
    // print() Flutter tool loglarına en garanti düşen yol
    // (developer.log bazı filtrelerde görünmeyebiliyor)
    // ignore: avoid_print
    print('🔍 BLE: BleConnectionScreen build()');

    final bleService = ref.watch(bleServiceProvider);
    final connectionState = ref.watch(bleConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Connection'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection Status Icon
              Icon(
                connectionState.when(
                  data: (isConnected) =>
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                  loading: () => Icons.bluetooth_searching,
                  error: (_, __) => Icons.bluetooth_disabled,
                ),
                size: 100,
                color: connectionState.when(
                  data: (isConnected) =>
                      isConnected ? Colors.green : Colors.grey,
                  loading: () => Colors.blue,
                  error: (_, __) => Colors.red,
                ),
              ),
              const SizedBox(height: 32),

              // Connection Status Text
              Text(
                connectionState.when(
                  data: (isConnected) => isConnected
                      ? 'Connected to HealthCareWristlet'
                      : 'Not Connected',
                  loading: () => 'Connecting...',
                  error: (_, __) => 'Connection Error',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Scan/Disconnect Button
              connectionState.when(
                data: (isConnected) => isConnected
                    ? ElevatedButton.icon(
                        onPressed: () => bleService.disconnect(),
                        icon: const Icon(Icons.bluetooth_disabled),
                        label: const Text('Disconnect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () {
                          developer.log('Scan button pressed', name: 'BLE');
                          // ignore: avoid_print
                          print('🔍 BLE: Scan button pressed!');

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('BLE scan başlatıldı (debug)'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          bleService.startScanning();
                        },
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Scan for Device'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                        ),
                      ),
                loading: () => const CircularProgressIndicator(),
                error: (_, __) => ElevatedButton.icon(
                  onPressed: () {
                    developer.log('Retry button pressed', name: 'BLE');
                    // ignore: avoid_print
                    print('🔍 BLE: Retry button pressed!');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('BLE scan başlatıldı (debug/retry)'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    bleService.startScanning();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
              const SizedBox(height: 24),

              // Info Text
              Text(
                'Make sure HealthCareWristlet is powered on\nand in Bluetooth range',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // Navigate to Sensor Data Screen when connected
              connectionState.when(
                data: (isConnected) => isConnected
                    ? ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/sensor-data');
                        },
                        child: const Text('View Sensor Data'),
                      )
                    : const SizedBox.shrink(),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
