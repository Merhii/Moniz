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
import 'package:moniz/providers/coach_tour_provider.dart';
import 'package:moniz/providers/metal_price_provider.dart';
import 'package:moniz/services/app_lock_service.dart';
import 'package:moniz/services/biometric_auth_service.dart';
import 'package:moniz/services/metal_price_service.dart';
import 'package:moniz/ui/kinetic/kinetic_widgets.dart';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('moniz_tour_');
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
    await Hive.box<dynamic>('uiPreferences').clear();
    await Hive.box<MoneyEntry>('moneyEntries').clear();
    await Hive.box<MoneyCategory>('moneyCategories').clear();
    await Hive.box<MoneyAccount>('moneyAccounts').clear();
    await seedMoneyDefaults();
  });

  tearDownAll(() async {
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  String appBarTitle(WidgetTester tester) {
    return tester
        .widget<KineticText>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(KineticText),
              )
              .first,
        )
        .text;
  }

  String bodyText(WidgetTester tester) {
    return tester
        .widget<KineticText>(find.byKey(const Key('coach_tour_body')))
        .text;
  }

  testWidgets('a first launch is met with the walkthrough', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);

    expect(find.byKey(const Key('coach_tour')), findsOneWidget);
    expect(bodyText(tester), contains('The total above follows'));
  });

  testWidgets('it explains the loop, not the buttons', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);

    final seen = <String>[];
    for (var step = 0; step < 5; step++) {
      seen.add(bodyText(tester));
      await tester.tap(find.byKey(const Key('coach_tour_next')));
      await _pump(tester);
    }

    // The three pillars have to be named, because nothing else in the app
    // says the tabs are one thing.
    expect(seen[3], contains('Gold, silver and cash'));
    expect(seen[4], contains('zakat'));
    expect(find.byKey(const Key('coach_tour')), findsNothing);
  });

  testWidgets('it counts the steps so the end is in sight', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);

    expect(find.text('1 of 5'), findsOneWidget);
    await tester.tap(find.byKey(const Key('coach_tour_next')));
    await _pump(tester);
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('skipping ends it there and then', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);

    await tester.tap(find.byKey(const Key('coach_tour_skip')));
    await _pump(tester);

    expect(find.byKey(const Key('coach_tour')), findsNothing);
  });

  testWidgets('it does not come back on the next launch', (tester) async {
    final seen = _MemoryTourSeen();
    _phone(tester);
    await tester.pumpWidget(_buildApp(seen: seen));
    await _pump(tester);
    await _pump(tester);
    await tester.tap(find.byKey(const Key('coach_tour_skip')));
    await _pump(tester);

    // A walkthrough that reappears every launch stops being help. The same
    // stored choice is carried across, which is what a relaunch does.
    await tester.pumpWidget(_buildApp(seen: seen));
    await _pump(tester);
    await _pump(tester);

    expect(find.byKey(const Key('coach_tour')), findsNothing);
  });

  test('the choice is written down, not just remembered', () async {
    final box = Hive.box<dynamic>('uiPreferences');
    final notifier = TourSeenNotifier(preferencesBox: box);
    expect(notifier.state, isFalse);

    await notifier.markSeen();
    expect(box.get(TourSeenNotifier.storageKey), isTrue);
    // A fresh launch reads it back rather than starting over.
    expect(TourSeenNotifier(preferencesBox: box).state, isTrue);

    await notifier.replay();
    expect(box.get(TourSeenNotifier.storageKey), isFalse);
    expect(TourSeenNotifier(preferencesBox: box).state, isFalse);
  });

  testWidgets('an install that has already seen it is left alone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>(
        'uiPreferences',
      ).put(TourSeenNotifier.storageKey, true);
    });

    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);

    expect(find.byKey(const Key('coach_tour')), findsNothing);
  });

  testWidgets('the app underneath cannot be reached through it', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await _pump(tester);
    expect(find.text('1 of 5'), findsOneWidget);

    // Aimed squarely at a nav tab. The backdrop takes the tap and moves the
    // tour on instead of switching tabs out from under it.
    await tester.tap(find.byKey(const Key('about_nav')), warnIfMissed: false);
    await _pump(tester);

    expect(find.byKey(const Key('coach_tour')), findsOneWidget);
    expect(find.text('2 of 5'), findsOneWidget);
    // The tab is the proof. Advancing the tour alone would still pass if the
    // tap had also fallen through and switched pages underneath.
    expect(appBarTitle(tester), 'Today');
  });

  testWidgets('it can be asked for again from Settings', (tester) async {
    await tester.runAsync(() async {
      await Hive.box<dynamic>(
        'uiPreferences',
      ).put(TourSeenNotifier.storageKey, true);
    });

    _phone(tester);
    await tester.pumpWidget(_buildApp());
    await _pump(tester);
    await tester.tap(find.byKey(const Key('settings_nav')));
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings_replay_tour')),
      300,
      scrollable: _verticalScrollableIn(const Key('settings_scroll')),
    );
    await tester.tap(find.byKey(const Key('settings_replay_tour')));
    await _pump(tester);
    await _pump(tester);

    // Replaying from Settings has to land back on Today, or the tour would
    // have nothing to point at.
    expect(find.byKey(const Key('coach_tour')), findsOneWidget);
    expect(bodyText(tester), contains('The total above follows'));
  });
}

/// A phone-sized viewport.
///
/// At the default 800x600 the lower half of Today is off screen, and an
/// anchor with no position on screen is one the tour walks straight past.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
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

/// Records the choice without writing it.
///
/// A Hive write issued from inside a tap handler never settles under fake
/// async, and it holds the box lock into the next test's setUp. Persistence is
/// asserted directly against the notifier instead, below.
class _MemoryTourSeen extends TourSeenNotifier {
  _MemoryTourSeen()
    : super(preferencesBox: Hive.box<dynamic>('uiPreferences'));

  @override
  Future<void> markSeen() async => state = true;

  @override
  Future<void> replay() async => state = false;
}

Widget _buildApp({TourSeenNotifier? seen}) {
  return ProviderScope(
    overrides: [
      tourSeenProvider.overrideWith((ref) => seen ?? _MemoryTourSeen()),
      appLockStorageProvider.overrideWithValue(_InMemoryAppLockStorage()),
      biometricAuthServiceProvider.overrideWithValue(
        const _UnavailableBiometricAuthService(),
      ),
      metalPriceServiceProvider.overrideWithValue(
        _UnavailableMetalPriceService(),
      ),
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
