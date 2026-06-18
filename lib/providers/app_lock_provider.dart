import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_lock_service.dart';
import '../services/biometric_auth_service.dart';

class AppLockState {
  const AppLockState({
    this.isLoading = true,
    this.isEnabled = false,
    this.isLocked = true,
    this.biometricsEnabled = false,
    this.biometricType = AppBiometricType.none,
    this.isAuthenticating = false,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isEnabled;
  final bool isLocked;
  final bool biometricsEnabled;
  final AppBiometricType biometricType;
  final bool isAuthenticating;
  final String? errorMessage;

  AppLockState copyWith({
    bool? isLoading,
    bool? isEnabled,
    bool? isLocked,
    bool? biometricsEnabled,
    AppBiometricType? biometricType,
    bool? isAuthenticating,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppLockState(
      isLoading: isLoading ?? this.isLoading,
      isEnabled: isEnabled ?? this.isEnabled,
      isLocked: isLocked ?? this.isLocked,
      biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
      biometricType: biometricType ?? this.biometricType,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier({
    required AppLockService appLockService,
    required BiometricAuthService biometricAuthService,
  }) : _appLockService = appLockService,
       _biometricAuthService = biometricAuthService,
       super(const AppLockState()) {
    initialize();
  }

  final AppLockService _appLockService;
  final BiometricAuthService _biometricAuthService;

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final enabled = await _appLockService.isEnabled();
      final biometricType = await _biometricAuthService.availableType();
      final biometricsEnabled =
          enabled &&
          biometricType != AppBiometricType.none &&
          await _appLockService.areBiometricsEnabled();
      if (!mounted) return;
      state = AppLockState(
        isLoading: false,
        isEnabled: enabled,
        isLocked: enabled,
        biometricsEnabled: biometricsEnabled,
        biometricType: biometricType,
      );
    } catch (_) {
      if (!mounted) return;
      state = const AppLockState(
        isLoading: false,
        isEnabled: true,
        isLocked: true,
        errorMessage: 'Unable to read secure app-lock settings.',
      );
    }
  }

  Future<void> enable(String pin) async {
    await _appLockService.savePin(pin);
    state = state.copyWith(
      isLoading: false,
      isEnabled: true,
      isLocked: false,
      biometricsEnabled: false,
      clearError: true,
    );
  }

  Future<void> disable() async {
    await _appLockService.removePin();
    state = state.copyWith(
      isEnabled: false,
      isLocked: false,
      biometricsEnabled: false,
      isAuthenticating: false,
      clearError: true,
    );
  }

  Future<bool> setBiometricsEnabled(bool enabled) async {
    if (!enabled) {
      await _appLockService.setBiometricsEnabled(false);
      state = state.copyWith(biometricsEnabled: false, clearError: true);
      return true;
    }
    if (state.biometricType == AppBiometricType.none) return false;

    state = state.copyWith(isAuthenticating: true, clearError: true);
    try {
      final authenticated = await _biometricAuthService.authenticate();
      if (!mounted) return false;
      if (!authenticated) {
        state = state.copyWith(
          isAuthenticating: false,
          errorMessage: 'Biometric verification failed. Your PIN still works.',
        );
        return false;
      }
      await _appLockService.setBiometricsEnabled(true);
      if (!mounted) return false;
      state = state.copyWith(
        biometricsEnabled: true,
        isAuthenticating: false,
        clearError: true,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: 'Unable to update biometric unlock.',
      );
      return false;
    }
  }

  void lock() {
    if (!state.isEnabled || state.isLocked) return;
    state = state.copyWith(isLocked: true, clearError: true);
  }

  Future<bool> unlockWithPin(String pin) async {
    try {
      final verified = await _appLockService.verifyPin(pin);
      if (!mounted) return false;
      state = state.copyWith(
        isLocked: !verified,
        errorMessage: verified ? null : 'Incorrect PIN. Try again.',
        clearError: verified,
      );
      return verified;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: 'Unable to verify the PIN securely.',
      );
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.isLocked ||
        !state.biometricsEnabled ||
        state.biometricType == AppBiometricType.none ||
        state.isAuthenticating) {
      return false;
    }
    state = state.copyWith(isAuthenticating: true, clearError: true);
    try {
      final authenticated = await _biometricAuthService.authenticate();
      if (!mounted) return false;
      state = state.copyWith(
        isLocked: !authenticated,
        isAuthenticating: false,
        errorMessage: authenticated
            ? null
            : 'Biometric unlock failed. Enter your PIN.',
        clearError: authenticated,
      );
      return authenticated;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: 'Biometric unlock failed. Enter your PIN.',
      );
      return false;
    }
  }
}

final appLockStorageProvider = Provider<AppLockStorage>(
  (ref) => const SecureAppLockStorage(),
);

final appLockServiceProvider = Provider<AppLockService>(
  (ref) => AppLockService(storage: ref.read(appLockStorageProvider)),
);

final biometricAuthServiceProvider = Provider<BiometricAuthService>(
  (ref) => LocalBiometricAuthService(),
);

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>(
  (ref) => AppLockNotifier(
    appLockService: ref.read(appLockServiceProvider),
    biometricAuthService: ref.read(biometricAuthServiceProvider),
  ),
);
