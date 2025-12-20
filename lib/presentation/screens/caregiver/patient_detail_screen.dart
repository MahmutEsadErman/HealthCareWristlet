import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/providers/patient_provider.dart';
import '../../../data/models/patient_model.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

class PatientDetailScreen extends ConsumerStatefulWidget {
  final int patientId;

  const PatientDetailScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _minHrController = TextEditingController();
  final _maxHrController = TextEditingController();
  final _inactivityController = TextEditingController();

  Patient? _patient;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPatientData();
    });
  }

  void _loadPatientData() {
    final patientState = ref.read(patientProvider);
    patientState.whenData((patients) {
      try {
        final patient = patients.firstWhere((p) => p.userId == widget.patientId);
        setState(() {
          _patient = patient;
          _minHrController.text = patient.minHr.toString();
          _maxHrController.text = patient.maxHr.toString();
          _inactivityController.text = patient.inactivityLimitMinutes.toString();
        });
      } catch (e) {
        // Patient not found
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Hasta bulunamadı'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
      }
    });
  }

  @override
  void dispose() {
    _minHrController.dispose();
    _maxHrController.dispose();
    _inactivityController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    // Form validasyonu
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Klavyeyi kapat
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    // Threshold update
    final thresholds = ThresholdUpdate(
      minHr: int.parse(_minHrController.text),
      maxHr: int.parse(_maxHrController.text),
      inactivityLimitMinutes: int.parse(_inactivityController.text),
    );

    final success = await ref.read(patientProvider.notifier).updateThresholds(
          patientUserId: widget.patientId,
          thresholds: thresholds,
        );

    setState(() {
      _isLoading = false;
    });

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eşikler başarıyla güncellendi!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      // Reload patient data
      _loadPatientData();
    } else {
      // Error mesajı PatientProvider'dan gelecek
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Eşikler güncellenirken hata oluştu'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_patient == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hasta Detayı'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasta Detayı'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Patient Info Card
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
                                _patient!.username,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'User ID: ${_patient!.userId}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Section Title
                Text(
                  'Eşik Ayarları',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hastanızın sağlık durumuna göre eşik değerlerini ayarlayın',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                // Min Heart Rate
                Row(
                  children: [
                    Icon(Icons.favorite, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Kalp Hızı Eşikleri',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  label: 'Minimum Kalp Hızı (bpm)',
                  hint: 'Örn: 40',
                  controller: _minHrController,
                  prefixIcon: Icons.arrow_downward,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Minimum kalp hızı gerekli';
                    }
                    final intValue = int.tryParse(value);
                    if (intValue == null) {
                      return 'Geçerli bir sayı girin';
                    }
                    if (intValue < 20 || intValue > 200) {
                      return 'Değer 20-200 arasında olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Maximum Kalp Hızı (bpm)',
                  hint: 'Örn: 120',
                  controller: _maxHrController,
                  prefixIcon: Icons.arrow_upward,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Maximum kalp hızı gerekli';
                    }
                    final intValue = int.tryParse(value);
                    if (intValue == null) {
                      return 'Geçerli bir sayı girin';
                    }
                    if (intValue < 20 || intValue > 200) {
                      return 'Değer 20-200 arasında olmalı';
                    }
                    final minValue = int.tryParse(_minHrController.text);
                    if (minValue != null && intValue <= minValue) {
                      return 'Maximum değer minimum değerden büyük olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Inactivity Limit
                Row(
                  children: [
                    Icon(Icons.timer, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Hareketsizlik Eşiği',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                CustomTextField(
                  label: 'Hareketsizlik Limiti (dakika)',
                  hint: 'Örn: 30',
                  controller: _inactivityController,
                  prefixIcon: Icons.access_time,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleUpdate(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Hareketsizlik limiti gerekli';
                    }
                    final intValue = int.tryParse(value);
                    if (intValue == null) {
                      return 'Geçerli bir sayı girin';
                    }
                    if (intValue < 1 || intValue > 120) {
                      return 'Değer 1-120 dakika arasında olmalı';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                // Update Button
                CustomButton(
                  text: 'Eşikleri Güncelle',
                  onPressed: _handleUpdate,
                  isLoading: _isLoading,
                  icon: Icons.save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
