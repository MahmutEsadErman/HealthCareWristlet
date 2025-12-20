import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../domain/providers/auth_provider.dart';
import '../../../routes/app_router.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

enum UserType { patient, caregiver }

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  UserType _selectedUserType = UserType.patient;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    // Form validasyonu
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Klavyeyi kapat
    FocusScope.of(context).unfocus();

    // Register işlemi
    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.register(
      _usernameController.text.trim(),
      _passwordController.text,
      _selectedUserType == UserType.patient ? 'patient' : 'caregiver',
    );

    if (!mounted) return;

    if (success) {
      // Başarı mesajı göster
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kayıt başarılı! Şimdi giriş yapabilirsiniz.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // Login sayfasına yönlendir
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        context.go(AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);

    // Error mesajını göster
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: theme.colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
        // Error'u temizle
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayıt Ol'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Icon
                  Icon(
                    Icons.person_add_outlined,
                    size: 80,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    'Yeni Hesap Oluştur',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Healthcare Wristlet\'e hoş geldiniz',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // User Type Selection
                  Text(
                    'Kullanıcı Tipi',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<UserType>(
                    segments: const [
                      ButtonSegment(
                        value: UserType.patient,
                        label: Text('Patient'),
                        icon: Icon(Icons.person),
                      ),
                      ButtonSegment(
                        value: UserType.caregiver,
                        label: Text('Caregiver'),
                        icon: Icon(Icons.medical_services),
                      ),
                    ],
                    selected: {_selectedUserType},
                    onSelectionChanged: (Set<UserType> newSelection) {
                      setState(() {
                        _selectedUserType = newSelection.first;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Username Field
                  CustomTextField(
                    label: 'Kullanıcı Adı',
                    hint: 'Kullanıcı adınızı girin',
                    controller: _usernameController,
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Kullanıcı adı gerekli';
                      }
                      if (value.trim().length < 3) {
                        return 'Kullanıcı adı en az 3 karakter olmalı';
                      }
                      if (value.contains(' ')) {
                        return 'Kullanıcı adı boşluk içeremez';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password Field
                  CustomTextField(
                    label: 'Şifre',
                    hint: 'Şifrenizi girin',
                    controller: _passwordController,
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Şifre gerekli';
                      }
                      if (value.length < 4) {
                        return 'Şifre en az 4 karakter olmalı';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm Password Field
                  CustomTextField(
                    label: 'Şifre Tekrar',
                    hint: 'Şifrenizi tekrar girin',
                    controller: _confirmPasswordController,
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleRegister(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Şifre tekrarı gerekli';
                      }
                      if (value != _passwordController.text) {
                        return 'Şifreler eşleşmiyor';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Register Button
                  CustomButton(
                    text: 'Kayıt Ol',
                    onPressed: _handleRegister,
                    isLoading: authState.isLoading,
                    icon: Icons.person_add,
                  ),
                  const SizedBox(height: 16),

                  // Login Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Zaten hesabınız var mı? ',
                        style: theme.textTheme.bodyMedium,
                      ),
                      TextButton(
                        onPressed: authState.isLoading
                            ? null
                            : () => context.go(AppRoutes.login),
                        child: const Text('Giriş Yap'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
