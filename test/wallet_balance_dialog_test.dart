import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:moniz/main.dart';
import 'package:moniz/models/asset.dart';
import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/models/money_entry.dart';
import 'package:moniz/models/portfolio_snapshot.dart';
import 'package:moniz/models/recurring_entry.dart';
import 'package:moniz/models/zakat_settings.dart';
import 'package:moniz/providers/app_lock_provider.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/providers/money_entry_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_wallet_dlg_');
    Hive.init(hiveDirectory.path);
    registerMonizAdapters();
    await Hive.openBox<Asset>('assets');
    await Hive.openBox<MetalPriceSnapshot>('metalPrices');
    await Hive.openBox<ZakatSettings>('zakatSettings');
    await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
    await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
    await Hive.openBox<dynamic>('uiPreferences');
    await Hive.openBox<MoneyEntry>('moneyEntries');
    await Hive.openBox<MoneyCategory>('moneyCategories');
    await Hive.openBox<MoneyAccount>('moneyAccounts');
    await Hive.openBox<RecurringEntry>('moneyRecurrences');
  });

  setUp(() async {
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<dynamic>('uiPreferences').clear();
    await seedMoneyDefaults();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  Future<_RecordingAccounts> openDialog(WidgetTester tester) async {
    final accounts = _RecordingAccounts();
    await tester.pumpWidget(_buildApp(accounts: accounts));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_wallet_balance_edit')),
      300,
      scrollable: _verticalScrollableIn(const Key('settings_scroll')),
    );
    await tester.tap(find.byKey(const Key('settings_wallet_balance_edit')));
    await _pump(tester);
    return accounts;
  }

  testWidgets('saving keeps a start date the wallet already had', (
    tester,
  ) async {
    // Somebody changing the amount should not silently lose the date the
    // hawl is measured from.
    await tester.runAsync(() async {
      await Hive.box<MoneyAccount>('moneyAccounts').put(
        MoneyAccount.defaultId,
        MoneyAccount(
          id: MoneyAccount.defaultId,
          label: 'Wallet',
          openingBalance: 1000,
          openedOn: DateTime(2025, 3, 4),
        ),
      );
    });

    final accounts = await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('wallet_balance_field')),
      '2500',
    );
    await tester.tap(find.byKey(const Key('save_wallet_balance')));
    await _pump(tester);

    expect(accounts.openings.single.balance, 2500);
    expect(accounts.openings.single.openedOn, DateTime(2025, 3, 4));
  });

  testWidgets('the date the picker returns is what gets saved', (tester) async {
    await tester.runAsync(() async {
      await Hive.box<MoneyAccount>('moneyAccounts').put(
        MoneyAccount.defaultId,
        const MoneyAccount(
          id: MoneyAccount.defaultId,
          label: 'Wallet',
          openingBalance: 1000,
        ),
      );
    });

    final accounts = await openDialog(tester);
    expect(find.text('Set a start date'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet_opened_on')));
    await _pump(tester);
    // Accepting whatever the picker opened on is enough: the point is that
    // the choice reaches the write at all.
    await tester.tap(find.text('OK'));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('save_wallet_balance')));
    await _pump(tester);

    // Without a start date zakat can never measure a lunar year on this
    // wallet, so it would stay excluded forever.
    expect(accounts.openings.single.openedOn, isNotNull);
  });

  testWidgets('cancelling writes nothing', (tester) async {
    final accounts = await openDialog(tester);
    await tester.enterText(
      find.byKey(const Key('wallet_balance_field')),
      '9999',
    );
    await tester.tap(find.byKey(const Key('cancel_wallet_balance')));
    await _pump(tester);

    expect(accounts.openings, isEmpty);
    expect(accounts.saved, isEmpty);
  });
}

/// Records instead of writing.
///
/// A Hive write issued from inside a tap handler never settles under fake
/// async and hangs the run.
class _RecordingAccounts extends MoneyAccountNotifier {
  _RecordingAccounts()
    : super(accountBox: Hive.box<MoneyAccount>('moneyAccounts'));

  final saved = <MoneyAccount>[];
  final openings = <({String id, double balance, DateTime? openedOn})>[];

  @override
  Future<void> upsert(MoneyAccount account) async {
    saved.add(account);
    state = [
      ...state.where((existing) => existing.id != account.id),
      account,
    ];
  }

  @override
  Future<void> setOpeningBalance(
    String id, {
    required double openingBalance,
    DateTime? openedOn,
  }) async {
    openings.add((id: id, balance: openingBalance, openedOn: openedOn));
  }
}

Future<void> _pump(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 300));
}

Finder _verticalScrollableIn(Key key) {
  return find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
}

Widget _buildApp({required _RecordingAccounts accounts}) {
  return ProviderScope(
    overrides: [
      appLockStorageProvider.overrideWithValue(_InMemoryAppLockStorage()),
      biometricAuthServiceProvider.overrideWithValue(
        const _UnavailableBiometricAuthService(),
      ),
      metalPriceServiceProvider.overrideWithValue(
        _UnavailableMetalPriceService(),
      ),
      moneyAccountProvider.overrideWith((ref) => accounts),
    ],
    child: const MonizApp(),
  );
}

class _UnavailableMetalPriceService implements MetalPriceService {
  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    throw const MetalPriceException('Unavailable in widget test.');
  }
}

class _UnavailableBiometricAuthService implements BiometricAuthService {
  const _UnavailableBiometricAuthService();

  @override
  Future<bool> authenticate() async => false;

  @override
  Future<AppBiometricType> availableType() async => AppBiometricType.none;
}

class _InMemoryAppLockStorage implements AppLockStorage {
  final _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
