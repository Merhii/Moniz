import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';

/// The keychain failure that used to kill main() before runApp, leaving a
/// window that never painted.
final _keychainFailure = PlatformException(
  code: '-34018',
  message: "A required entitlement isn't present.",
);

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_startup_');
    Hive.init(hiveDirectory.path);
    Hive.registerAdapter(AssetTypeAdapter());
    Hive.registerAdapter(AssetTagAdapter());
    Hive.registerAdapter(AssetAdapter());
    Hive.registerAdapter(MetalPriceSnapshotAdapter());
    Hive.registerAdapter(ZakatScheduleModeAdapter());
    Hive.registerAdapter(NisabStandardAdapter());
    Hive.registerAdapter(ZakatSettingsAdapter());
    Hive.registerAdapter(ZakatPaymentRecordAdapter());
    Hive.registerAdapter(PortfolioSnapshotAdapter());
    Hive.registerAdapter(MoneyDirectionAdapter());
    Hive.registerAdapter(MoneyCategoryAdapter());
    Hive.registerAdapter(MoneyAccountAdapter());
    Hive.registerAdapter(MoneyEntryAdapter());
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<MoneyCategory>('moneyCategories');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  testWidgets('a keychain failure shows a screen, not a blank window', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(openStorage: () async => throw _keychainFailure),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('startup_failure_title')), findsOneWidget);
    expect(find.textContaining('could not be reached'), findsOneWidget);
    expect(
      find.textContaining('Nothing has been changed or lost'),
      findsOneWidget,
    );
    // The platform's own reason is surfaced rather than swallowed.
    expect(find.textContaining("entitlement isn't present"), findsOneWidget);
    expect(find.byKey(const Key('retry_startup')), findsOneWidget);
  });

  testWidgets('does not quietly fall back to unencrypted storage', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(openStorage: () async => throw _keychainFailure),
    );
    await tester.pump();
    await tester.pump();

    // No ledger, no totals - the app refuses to run rather than open the
    // boxes without the key.
    expect(find.byKey(const Key('dashboard_nav')), findsNothing);
    expect(find.text('TOTAL WEALTH'), findsNothing);
  });

  testWidgets('retry runs the open again', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _boot(
        openStorage: () async {
          attempts += 1;
          throw _keychainFailure;
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(attempts, 1);

    await tester.tap(find.byKey(const Key('retry_startup')));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byKey(const Key('startup_failure_title')), findsOneWidget);
  });

  testWidgets('a broken notification plugin does not block startup', (
    tester,
  ) async {
    await tester.pumpWidget(
      _boot(
        openStorage: () async {},
        startNotifications: () async =>
            throw PlatformException(code: 'notifications_unavailable'),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    // Reached the real app: notifications are a convenience, not a gate.
    expect(find.byKey(const Key('startup_failure_title')), findsNothing);
    expect(find.byKey(const Key('today_nav')), findsOneWidget);
  });
}

Widget _boot({
  required Future<void> Function() openStorage,
  Future<void> Function()? startNotifications,
}) {
  return ProviderScope(
    overrides: [
      appLockStorageProvider.overrideWithValue(_InMemoryAppLockStorage()),
      biometricAuthServiceProvider.overrideWithValue(
        const _UnavailableBiometricAuthService(),
      ),
      metalPriceServiceProvider.overrideWithValue(
        _UnavailableMetalPriceService(),
      ),
      metalPriceHistoryServiceProvider.overrideWithValue(
        const _UnavailableMetalPriceHistoryService(),
      ),
    ],
    child: MonizBootstrap(
      openStorage: openStorage,
      startNotifications: startNotifications ?? () async {},
    ),
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

class _UnavailableBiometricAuthService implements BiometricAuthService {
  const _UnavailableBiometricAuthService();

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<AppBiometricType> availableType() async => AppBiometricType.none;
}

class _UnavailableMetalPriceService implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _UnavailableMetalPriceHistoryService implements MetalPriceHistoryService {
  const _UnavailableMetalPriceHistoryService();

  @override
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({
    required int days,
  }) async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}
