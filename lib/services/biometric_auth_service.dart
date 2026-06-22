import 'package:local_auth/local_auth.dart';

enum AppBiometricType { none, faceId, fingerprint, biometric }

extension AppBiometricTypeLabel on AppBiometricType {
  String get label => switch (this) {
    AppBiometricType.none => 'Biometrics',
    AppBiometricType.faceId => 'Face ID',
    AppBiometricType.fingerprint => 'Fingerprint',
    AppBiometricType.biometric => 'Biometric unlock',
  };
}

abstract class BiometricAuthService {
  Future<AppBiometricType> availableType();

  Future<bool> authenticate();
}

class LocalBiometricAuthService implements BiometricAuthService {
  LocalBiometricAuthService({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;

  @override
  Future<AppBiometricType> availableType() async {
    try {
      if (!await _authentication.canCheckBiometrics) {
        return AppBiometricType.none;
      }
      final types = await _authentication.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        return AppBiometricType.faceId;
      }
      if (types.contains(BiometricType.fingerprint)) {
        return AppBiometricType.fingerprint;
      }
      return types.isEmpty ? AppBiometricType.none : AppBiometricType.biometric;
    } on LocalAuthException {
      return AppBiometricType.none;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _authentication.authenticate(
        localizedReason: 'Unlock MONIZ to view your financial information.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    }
  }
}
