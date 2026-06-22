import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/app_lock_gate.dart';
import 'package:moniz/widgets/security_settings_card.dart';

void main() {
  testWidgets('PIN fallback unlocks and lifecycle backgrounding locks again', (
    tester,
  ) async {
    final storage = _InMemoryAppLockStorage();
    await AppLockService(storage: storage).savePin('2468');

    await tester.pumpWidget(
      _testScope(
        storage: storage,
        biometrics: _FakeBiometricAuthService(type: AppBiometricType.none),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const AppLockGate(child: Text('PRIVATE CONTENT')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Moniz locked'), findsOneWidget);
    expect(find.text('PRIVATE CONTENT'), findsNothing);

    await tester.enterText(find.byKey(const Key('app_unlock_pin')), '1111');
    await tester.tap(find.byKey(const Key('app_unlock_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect PIN. Try again.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('app_unlock_pin')), '2468');
    await tester.tap(find.byKey(const Key('app_unlock_submit')));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE CONTENT'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Moniz locked'), findsOneWidget);
  });

  testWidgets('enables PIN, biometrics, and then disables app lock', (
    tester,
  ) async {
    final storage = _InMemoryAppLockStorage();
    final biometrics = _FakeBiometricAuthService(
      type: AppBiometricType.fingerprint,
      authenticates: true,
    );

    await tester.pumpWidget(
      _testScope(
        storage: storage,
        biometrics: biometrics,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(child: SecuritySettingsCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('enable_app_lock')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('app_lock_new_pin')), '1357');
    await tester.enterText(
      find.byKey(const Key('app_lock_confirm_pin')),
      '1357',
    );
    final createButton = find.byKey(const Key('app_lock_create_pin'));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('App lock on'), findsOneWidget);
    expect(await AppLockService(storage: storage).verifyPin('1357'), isTrue);
    expect(
      await AppLockService(storage: storage).areBiometricsEnabled(),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('app_lock_biometrics_toggle')));
    await tester.pumpAndSettle();
    expect(
      await AppLockService(storage: storage).areBiometricsEnabled(),
      isFalse,
    );
    expect(biometrics.authenticationCount, 0);

    await tester.tap(find.byKey(const Key('app_lock_biometrics_toggle')));
    await tester.pumpAndSettle();
    expect(biometrics.authenticationCount, 1);
    expect(
      await AppLockService(storage: storage).areBiometricsEnabled(),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('disable_app_lock')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_disable_app_lock')));
    await tester.pumpAndSettle();

    expect(find.text('App lock off'), findsOneWidget);
    expect(await AppLockService(storage: storage).isEnabled(), isFalse);
  });
}

Widget _testScope({
  required AppLockStorage storage,
  required BiometricAuthService biometrics,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      appLockStorageProvider.overrideWithValue(storage),
      biometricAuthServiceProvider.overrideWithValue(biometrics),
    ],
    child: child,
  );
}

class _InMemoryAppLockStorage implements AppLockStorage {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeBiometricAuthService implements BiometricAuthService {
  _FakeBiometricAuthService({required this.type, this.authenticates = false});

  final AppBiometricType type;
  final bool authenticates;
  var authenticationCount = 0;

  @override
  Future<bool> authenticate() async {
    authenticationCount += 1;
    return authenticates;
  }

  @override
  Future<AppBiometricType> availableType() async => type;
}
