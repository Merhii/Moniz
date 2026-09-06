import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'models/asset.dart';
import 'models/money_entry.dart';
import 'models/recurring_entry.dart';
import 'models/metal_price_snapshot.dart';
import 'models/portfolio_snapshot.dart';
import 'models/zakat_settings.dart';
import 'providers/asset_provider.dart';
import 'providers/display_currency_provider.dart';
import 'providers/metal_price_provider.dart';
import 'providers/portfolio_snapshot_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'providers/daily_nudge_provider.dart';
import 'providers/price_alert_provider.dart';
import 'providers/zakat_reminder_provider.dart';
import 'providers/zakat_provider.dart';
import 'services/dashboard_filter.dart';
import 'services/hive_encryption.dart';
import 'services/local_notification_service.dart';
import 'services/money_category_catalog.dart';
import 'services/recurrence_planner.dart';
import 'services/app_lock_service.dart';
import 'services/currency_converter.dart';
import 'services/position_performance.dart';
import 'services/portfolio_analytics.dart';
import 'services/transaction_history_service.dart';
import 'services/wealth_calculator.dart';
import 'services/price_alert_worker.dart';
import 'services/zakat_engine.dart';
import 'theme/app_theme.dart';
import 'ui/kinetic/kinetic_widgets.dart';
import 'widgets/about_page.dart';
import 'widgets/today_page.dart';
import 'widgets/asset_form_dialog.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/notification_settings_screen.dart';
import 'widgets/portfolio_insights_card.dart';
import 'widgets/security_settings_card.dart';
import 'widgets/transaction_history_screen.dart';
import 'widgets/zakat_mark_paid_button.dart';

void main() {
  // Nothing is awaited before runApp. Anything that can fail - reaching the
  // keychain for the box key, opening Hive, the notification plugin - happens
  // inside MonizBootstrap, where a failure can be shown on screen instead of
  // killing main and leaving a blank window.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MonizBootstrap()));
}

/// Every box the app stores data in. Encryption is bootstrapped from this
/// list, so a box added here is encrypted by that fact alone — and a box left
/// off it would sit in plaintext beside the rest.
const monizBoxNames = [
  'assets',
  'metalPrices',
  'zakatSettings',
  'zakatPayments',
  'portfolioSnapshots',
  'uiPreferences',
  'moneyEntries',
  'moneyCategories',
  'moneyAccounts',
  'moneyRecurrences',
];

/// Opens the encrypted Hive boxes the app runs on.
///
/// Safe to call again after a failure: adapters are only registered once, and
/// reopening an already-open box returns the open one.
Future<void> openMonizStorage() async {
  await Hive.initFlutter();

  registerMonizAdapters();

  // The keychain outlives the app: delete Moniz and reinstall it and the PIN
  // is still there, now guarding a database that is not. The box files are
  // created the first time they are opened, so their absence here means this
  // is the first launch of a fresh install and any credential we find belongs
  // to a previous one.
  final isFreshInstall = !await Hive.boxExists('assets');

  final cipher = await HiveEncryption().bootstrap(monizBoxNames);

  await Hive.openBox<Asset>('assets', encryptionCipher: cipher);
  await Hive.openBox<MetalPriceSnapshot>(
    'metalPrices',
    encryptionCipher: cipher,
  );
  await Hive.openBox<ZakatSettings>('zakatSettings', encryptionCipher: cipher);
  await Hive.openBox<ZakatPaymentRecord>(
    'zakatPayments',
    encryptionCipher: cipher,
  );
  await Hive.openBox<PortfolioSnapshot>(
    'portfolioSnapshots',
    encryptionCipher: cipher,
  );
  await Hive.openBox<dynamic>('uiPreferences', encryptionCipher: cipher);
  // Spending is at least as sensitive as holdings, so it gets the same cipher
  // rather than a plaintext box beside the encrypted ones.
  await Hive.openBox<MoneyEntry>('moneyEntries', encryptionCipher: cipher);
  await Hive.openBox<MoneyCategory>(
    'moneyCategories',
    encryptionCipher: cipher,
  );
  await Hive.openBox<MoneyAccount>('moneyAccounts', encryptionCipher: cipher);
  await Hive.openBox<RecurringEntry>(
    'moneyRecurrences',
    encryptionCipher: cipher,
  );
  await seedMoneyDefaults();
  await materialiseDueRecurrences();

  await discardOrphanedAppLock(
    isFreshInstall: isFreshInstall,
    storage: const SecureAppLockStorage(),
  );
}

/// Drops an app-lock credential left behind by a previous install.
///
/// Only on the first launch of a fresh install. A PIN set during a normal
/// session is kept: by the next launch the box files exist, so this does
/// nothing. Anything restored from a backup brings its boxes with it and is
/// likewise left alone.
@visibleForTesting
Future<void> discardOrphanedAppLock({
  required bool isFreshInstall,
  required AppLockStorage storage,
}) async {
  if (!isFreshInstall) return;
  await AppLockService(storage: storage).removePin();
}

/// Registers every Hive adapter the app needs, once.
///
/// The type argument matters: Hive matches a value to an adapter with
/// `value is T`, so registering through a `TypeAdapter<dynamic>` makes the
/// first adapter match every value and every write goes to the wrong one.
/// Writes the starting categories and the single wallet account a fresh
/// install needs. Runs on every start so a later release can add a category
/// without a migration; anything already stored is left alone.
@visibleForTesting
Future<void> seedMoneyDefaults() async {
  final categories = Hive.box<MoneyCategory>('moneyCategories');
  final missing = MoneyCategoryCatalog.missingFrom(categories.keys.cast());
  if (missing.isNotEmpty) {
    await categories.putAll({
      for (final category in missing) category.id: category,
    });
  }

  final accounts = Hive.box<MoneyAccount>('moneyAccounts');
  if (!accounts.containsKey(MoneyAccount.defaultId)) {
    await accounts.put(
      MoneyAccount.defaultId,
      MoneyCategoryCatalog.defaultAccount,
    );
  }
}

/// Writes the entries every recurring rule owes since it last ran.
///
/// Runs at startup, before anything reads the ledger, so a salary that landed
/// while the app was closed is already there. Idempotent: each rule records
/// the last date it produced, and occurrences are generated strictly after it.
@visibleForTesting
Future<void> materialiseDueRecurrences({DateTime? now}) async {
  final rules = Hive.box<RecurringEntry>('moneyRecurrences');
  if (rules.isEmpty) return;

  final entries = Hive.box<MoneyEntry>('moneyEntries');
  const planner = RecurrencePlanner();
  final at = now ?? DateTime.now();

  for (final rule in rules.values.toList()) {
    final result = planner.materialise(rule: rule, now: at);
    if (result.entries.isEmpty) continue;
    await entries.putAll({
      for (final entry in result.entries) entry.id: entry,
    });
    await rules.put(rule.id, result.rule);
  }
}

@visibleForTesting
void registerMonizAdapters() {
  _registerAdapter(MoneyDirectionAdapter());
  _registerAdapter(MoneyCategoryAdapter());
  _registerAdapter(MoneyAccountAdapter());
  _registerAdapter(MoneyEntryAdapter());
  _registerAdapter(RecurrenceFrequencyAdapter());
  _registerAdapter(RecurringEntryAdapter());
  _registerAdapter(AssetTypeAdapter());
  _registerAdapter(AssetTagAdapter());
  _registerAdapter(AssetAdapter());
  _registerAdapter(MetalPriceSnapshotAdapter());
  _registerAdapter(ZakatScheduleModeAdapter());
  _registerAdapter(NisabStandardAdapter());
  _registerAdapter(ZakatSettingsAdapter());
  _registerAdapter(ZakatPaymentRecordAdapter());
  _registerAdapter(PortfolioSnapshotAdapter());
}

void _registerAdapter<T>(TypeAdapter<T> adapter) {
  if (Hive.isAdapterRegistered(adapter.typeId)) return;
  Hive.registerAdapter<T>(adapter);
}

/// Opens storage before handing over to [MonizApp], and shows why it could not
/// when that fails.
///
/// The app deliberately refuses to run rather than falling back to unencrypted
/// boxes: a silent downgrade would drop the guarantee without anyone noticing.
class MonizBootstrap extends StatefulWidget {
  const MonizBootstrap({super.key, this.openStorage, this.startNotifications});

  final Future<void> Function()? openStorage;
  final Future<void> Function()? startNotifications;

  @override
  State<MonizBootstrap> createState() => _MonizBootstrapState();
}

enum _Startup { opening, ready, failed }

class _MonizBootstrapState extends State<MonizBootstrap> {
  var _startup = _Startup.opening;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _startup = _Startup.opening;
      _failure = null;
    });
    try {
      await (widget.openStorage ?? openMonizStorage)();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startup = _Startup.failed;
        _failure = error;
      });
      return;
    }

    // Notifications are a convenience, not a precondition. Losing them should
    // never cost access to the ledger.
    try {
      await (widget.startNotifications ??
          localNotificationService.initialize)();
    } catch (_) {
      // Ignored on purpose.
    }

    // Hands the OS the entry point for the background price check. Registering
    // the check itself is separate, and only happens once somebody subscribes.
    if (PriceAlertScheduler.isSupported) {
      try {
        await Workmanager().initialize(priceAlertCallbackDispatcher);
      } catch (_) {
        // Ignored on purpose, same reasoning as above.
      }
    }

    if (!mounted) return;
    setState(() => _startup = _Startup.ready);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_startup) {
      _Startup.ready => const MonizApp(),
      _Startup.opening => const _StartupShell(child: _StartupProgress()),
      _Startup.failed => _StartupShell(
        child: _StartupFailure(failure: _failure, onRetry: _open),
      ),
    };
  }
}

/// Minimal app wrapper for the pre-storage screens. The stored theme lives in
/// a box that may not be open, so this follows the system setting.
class _StartupShell extends StatelessWidget {
  const _StartupShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moniz',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: Builder(
        builder: (context) {
          final colors = context.kinetic;
          return Scaffold(
            backgroundColor: colors.background,
            body: DecoratedBox(
              decoration: AppTheme.brandBackground(colors),
              child: SafeArea(child: Center(child: child)),
            ),
          );
        },
      ),
    );
  }
}

class _StartupProgress extends StatelessWidget {
  const _StartupProgress();

  @override
  Widget build(BuildContext context) {
    return const CircularProgressIndicator();
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.failure, required this.onRetry});

  final Object? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: LedgerFrame(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline_rounded, color: colors.accent, size: 42),
              const SizedBox(height: 14),
              KineticText(
                'Moniz could not open your holdings',
                key: const Key('startup_failure_title'),
                align: TextAlign.center,
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
              ),
              const SizedBox(height: 12),
              KineticText(
                'Your holdings are stored encrypted, and the key for them '
                'lives in this device\'s secure storage. That could not be '
                'reached just now, so the app has stopped rather than open '
                'your ledger unprotected.',
                align: TextAlign.center,
                muted: true,
                uppercase: false,
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
              ),
              const SizedBox(height: 12),
              KineticText(
                'Nothing has been changed or lost. Your data is still there, '
                'still encrypted.',
                align: TextAlign.center,
                muted: true,
                uppercase: false,
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
              ),
              if (failure != null) ...[
                const SizedBox(height: 16),
                KineticText(
                  _detail(failure!),
                  key: const Key('startup_failure_detail'),
                  align: TextAlign.center,
                  muted: true,
                  uppercase: false,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              BrutalistButton(
                key: const Key('retry_startup'),
                label: 'Try again',
                expand: true,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _detail(Object failure) {
    final text = failure is PlatformException
        ? (failure.message ?? failure.code)
        : failure.toString();
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }
}

class MonizApp extends ConsumerWidget {
  const MonizApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moniz',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const PriceAlertSync(
        child: ZakatReminderSync(
          child: DailyNudgeSync(child: KineticHome()),
        ),
      ),
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

class KineticHome extends ConsumerStatefulWidget {
  const KineticHome({super.key});

  @override
  ConsumerState<KineticHome> createState() => _KineticHomeState();
}

class _KineticHomeState extends ConsumerState<KineticHome> {
  var _selectedPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(metalPriceProvider.notifier).refreshPrices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TodayPage(),
      const DashboardPage(),
      const ZakatPage(),
      const SettingsPage(),
      const AboutPage(),
    ];
    final colors = context.kinetic;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: colors.background,
        leadingWidth: 64,
        leading: const SizedBox(width: 64),
        centerTitle: true,
        title: _selectedPage == 1
            ? const _MonizLogo()
            : KineticText(switch (_selectedPage) {
                0 => 'Today',
                2 => 'Zakat',
                3 => 'Settings',
                _ => 'About',
              }, style: AppTheme.titleStyle(colors).copyWith(fontSize: 22)),
        actions: [
          Builder(
            builder: (buttonContext) => IconButton(
              key: const Key('open_notifications'),
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_none_rounded),
              onPressed: () => Navigator.of(
                buttonContext,
              ).push<void>(_kineticRoute<void>(const NotificationsScreen())),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          top: false,
          bottom: false,
          child: IndexedStack(index: _selectedPage, children: pages),
        ),
      ),
      bottomNavigationBar: _KineticNav(
        selectedIndex: _selectedPage,
        onSelected: _setPage,
      ),
    );
  }

  void _setPage(int index) {
    setState(() => _selectedPage = index);
  }
}

class _MonizLogo extends StatelessWidget {
  const _MonizLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/moniztransparent.png',
      height: 44,
      fit: BoxFit.contain,
    );
  }
}

class _KineticNav extends StatelessWidget {
  const _KineticNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _tabs = [
    (
      label: 'Today',
      icon: Icons.receipt_long_outlined,
      key: Key('today_nav'),
    ),
    (
      label: 'Wealth',
      icon: Icons.account_balance_wallet_outlined,
      key: Key('dashboard_nav'),
    ),
    (
      label: 'Zakat',
      icon: Icons.volunteer_activism_outlined,
      key: Key('zakat_nav'),
    ),
    (label: 'Settings', icon: Icons.tune_rounded, key: Key('settings_nav')),
    (label: 'About', icon: Icons.info_outline_rounded, key: Key('about_nav')),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(
            color: Colors.black.withValues(alpha: 0.12),
            width: AppTheme.hairlineWidth,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Row(
                children: [
                  for (var index = 0; index < _tabs.length; index++)
                    Expanded(
                      child: PressableScale(
                        key: _tabs[index].key,
                        onTap: () => onSelected(index),
                        scale: 0.98,
                        child: _NavItem(
                          label: _tabs[index].label,
                          icon: _tabs[index].icon,
                          selected: selectedIndex == index,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
  });

  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final foreground = selected
        ? colors.accent
        : colors.foreground.withValues(alpha: 0.40);
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.fast,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 23),
          const SizedBox(height: 4),
          KineticText(
            label,
            align: TextAlign.center,
            maxLines: 1,
            style: AppTheme.labelStyle(
              colors,
            ).copyWith(color: foreground, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  var _filter = const DashboardFilter();

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetProvider);
    final filteredAssets = _filter.apply(assets);
    final metalPriceState = ref.watch(metalPriceProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final zakatSettings = ref.watch(zakatProvider);
    final zakatResult = ZakatEngine.calculate(
      assets: assets,
      prices: metalPriceState.snapshot,
      settings: zakatSettings,
      payments: ref.read(zakatProvider.notifier).payments,
      today: DateTime.now(),
    );
    final totals = WealthCalculator.calculate(
      filteredAssets,
      metalPriceState.snapshot,
      displayCurrency,
    );
    final analytics = PortfolioAnalytics.calculate(
      filteredAssets,
      metalPriceState.snapshot,
      displayCurrency: displayCurrency,
    );
    final completeAnalyticsUsd = PortfolioAnalytics.calculateUsd(
      assets,
      metalPriceState.snapshot,
    );
    final performance = PositionPerformance.calculate(
      filteredAssets,
      metalPriceState.snapshot,
      displayCurrency: displayCurrency,
    );
    final completePerformance = PositionPerformance.calculate(
      assets,
      metalPriceState.snapshot,
      displayCurrency: displayCurrency,
    );
    final snapshots = ref.watch(portfolioSnapshotProvider);
    // forDisplay reports the currency it actually used, so a missing rate can
    // no longer show a USD figure wearing another currency's label.
    final displayZakat = CurrencyConverter.forDisplay(
      zakatResult.amountDueUsd,
      displayCurrency,
      prices: metalPriceState.snapshot,
    );
    final summaryNote = [
      if (totals.hasUnpricedMetals)
        'Refresh metal prices in Settings to include metal holdings.',
      if (totals.hasUnsupportedCurrencies)
        'Holdings in a currency with no exchange rate are excluded from this '
            'total.',
    ].join(' ');

    final colors = context.kinetic;
    final sectionDivider = Divider(
      height: 48,
      thickness: 1,
      color: colors.border.withValues(alpha: 0.15),
    );

    return CustomScrollView(
      key: const Key('dashboard_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _WealthHero(
            wealthLabel: _filter.isActive ? 'Filtered wealth' : 'Total wealth',
            totalWealth: totals.totalValue,
            zakat: displayZakat.value,
            zakatCurrency: displayZakat.currency,
            currency: totals.currency,
            note: summaryNote.isEmpty ? null : summaryNote,
          ),
        ),
        SliverToBoxAdapter(
          child: TickerTape(
            height: 40,
            fontSize: 13,
            items: _metalTickerItems(metalPriceState, displayCurrency),
          ),
        ),
        if (assets.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _DashboardEmptyState(
              onAddHolding: () => _showAssetFormDialog(context, ref),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            sliver: SliverList.list(
              children: [
                DashboardFiltersCard(
                  assets: assets,
                  filter: _filter,
                  onTypeSelected: _selectType,
                  onTagSelected: _selectTag,
                  onSelectFromDate: () => _selectDate(isStart: true),
                  onSelectToDate: () => _selectDate(isStart: false),
                  onClear: () =>
                      setState(() => _filter = const DashboardFilter()),
                ),
                const SizedBox(height: 16),
                KineticText(
                  _filter.isActive
                      ? 'Showing ${filteredAssets.length} of ${assets.length} holdings'
                      : 'Showing all ${assets.length} holdings',
                  key: const Key('dashboard_filter_result'),
                  muted: true,
                  style: AppTheme.bodyStyle(
                    colors,
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          // Directly under the filters and the count that describes it. These
          // used to be on separate tabs, so filtering changed a number on one
          // screen and a list on another.
          SliverToBoxAdapter(
            child: _SectionHeading(
              title: 'Holdings',
              trailing: BrutalistButton(
                key: const Key('add_asset_button'),
                label: 'Add asset',
                tone: BrutalistButtonTone.primary,
                onPressed: () => _showAssetFormDialog(context, ref),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList.separated(
              itemCount: filteredAssets.length,
              itemBuilder: (context, index) =>
                  AssetTile(asset: filteredAssets[index], cardless: true),
              separatorBuilder: (context, index) => Divider(
                height: 32,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.15),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverList.list(
              children: [
                sectionDivider,
                PortfolioInsightsCard(
                  analytics: analytics,
                  snapshotAnalytics: completeAnalyticsUsd,
                  isFiltered: _filter.isActive,
                  cardless: true,
                  onOpenHistory: () => Navigator.of(context).push<void>(
                    PageRouteBuilder<void>(
                      transitionDuration: Duration.zero,
                      reverseTransitionDuration: Duration.zero,
                      pageBuilder: (_, _, _) =>
                          const TransactionHistoryScreen(),
                    ),
                  ),
                ),
                sectionDivider,
                PortfolioTrendCard(
                  snapshots: snapshots,
                  performance: completePerformance,
                  assets: assets,
                  metalPriceHistory: metalPriceState.historicalPrices,
                  displayCurrency: displayCurrency,
                  cardless: true,
                ),
                sectionDivider,
                ProfitLossCard(summary: performance, cardless: true),
                const SizedBox(height: 16),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _SectionHeading(title: 'Transaction history'),
          ),
          ..._transactionHistorySlivers(context, assets),
        ],
      ],
    );
  }

  void _selectType(AssetType? type) {
    setState(() {
      _filter = type == null
          ? _filter.copyWith(clearType: true)
          : _filter.copyWith(type: type);
    });
  }

  void _selectTag(AssetTag? tag) {
    setState(() {
      _filter = tag == null
          ? _filter.copyWith(clearTag: true)
          : _filter.copyWith(tag: tag);
    });
  }

  Future<void> _selectDate({required bool isStart}) async {
    final current = isStart ? _filter.fromDate : _filter.toDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (isStart) {
        _filter = _filter.copyWith(
          fromDate: selected,
          clearToDate:
              _filter.toDate != null && selected.isAfter(_filter.toDate!),
        );
      } else {
        _filter = _filter.copyWith(
          toDate: selected,
          clearFromDate:
              _filter.fromDate != null && selected.isBefore(_filter.fromDate!),
        );
      }
    });
  }
}

/// Shown on the dashboard until the first holding exists.
///
/// Filters, allocation and history all need holdings to say anything, so with
/// none they are replaced by the one thing worth doing here.
class _DashboardEmptyState extends StatelessWidget {
  const _DashboardEmptyState({required this.onAddHolding});

  final VoidCallback onAddHolding;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 44,
            color: colors.accent,
          ),
          const SizedBox(height: 16),
          KineticText(
            'No holdings yet',
            key: const Key('dashboard_empty_title'),
            align: TextAlign.center,
            style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
          ),
          const SizedBox(height: 10),
          KineticText(
            'Add your cash, gold and silver to see what you are worth and '
            'whether zakat is due.',
            align: TextAlign.center,
            muted: true,
            uppercase: false,
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 22),
          BrutalistButton(
            key: const Key('dashboard_add_first_holding'),
            label: 'Add your first holding',
            tone: BrutalistButtonTone.primary,
            onPressed: onAddHolding,
          ),
        ],
      ),
    );
  }
}

class _WealthHero extends StatelessWidget {
  const _WealthHero({
    required this.wealthLabel,
    required this.totalWealth,
    required this.zakat,
    required this.zakatCurrency,
    required this.currency,
    this.note,
  });

  final String wealthLabel;
  final double totalWealth;
  final double zakat;
  final String zakatCurrency;
  final String currency;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroSize = (constraints.maxWidth * 0.11).clamp(44.0, 60.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: KineticText(
                        'Live position',
                        muted: true,
                        style: AppTheme.labelStyle(colors).copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('open_transaction_history'),
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          PageRouteBuilder<void>(
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                            pageBuilder: (_, _, _) =>
                                const TransactionHistoryScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded, size: 17),
                      label: const Text('History'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                KineticText(
                  wealthLabel.toUpperCase(),
                  style: AppTheme.labelStyle(colors).copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: KineticNumber(
                      _formatMoney(totalWealth, currency: currency),
                      key: const Key('wealth_hero_total'),
                      fontSize: heroSize,
                      color: colors.foreground,
                      currency: currency,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    KineticText(
                      'ZAKAT DUE: ',
                      muted: true,
                      style: AppTheme.labelStyle(colors).copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    KineticNumber(
                      _formatMoney(zakat, currency: zakatCurrency),
                      fontSize: 20,
                      color: colors.accent,
                      currency: zakatCurrency,
                    ),
                  ],
                ),
                if (note != null) ...[
                  const SizedBox(height: 16),
                  KineticText(
                    note!,
                    muted: true,
                    align: TextAlign.center,
                    style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The timeline that used to sit at the bottom of the Ledger tab.
List<Widget> _transactionHistorySlivers(
  BuildContext context,
  List<Asset> assets,
) {
  final groupedEvents = _groupEventsByDate(
    TransactionHistoryService.eventsFor(assets),
  );
  if (groupedEvents.isEmpty) {
    return const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: LedgerFrame(
            cardless: true,
            padding: EdgeInsets.zero,
            child: KineticText(
              'Add holding start or sold dates to build the timeline.',
              muted: true,
            ),
          ),
        ),
      ),
    ];
  }

  final slivers = <Widget>[];
  for (final entry in groupedEvents.entries) {
    slivers
      ..add(
        SliverPersistentHeader(
          pinned: true,
          delegate: StickyDateHeader(label: _formatDate(entry.key)),
        ),
      )
      ..add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList.separated(
            itemCount: entry.value.length,
            itemBuilder: (context, index) =>
                _TransactionEventRow(event: entry.value[index], cardless: true),
            separatorBuilder: (context, index) => Divider(
              height: 20,
              thickness: 1,
              color: context.kinetic.border.withValues(alpha: 0.15),
            ),
          ),
        ),
      );
  }
  return slivers;
}

/// Titles a run of slivers inside the one scroll view the Wealth tab now is.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: KineticText(
              title,
              style: AppTheme.titleStyle(
                context.kinetic,
              ).copyWith(fontSize: 22),
            ),
          ),
          // Not `?trailing`: that null-aware element is valid Dart and the
          // analyzer prefers it, but the analyzer build_runner pins cannot
          // parse it, which breaks adapter generation for the whole project.
          // ignore: use_null_aware_elements
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class ZakatPage extends ConsumerWidget {
  const ZakatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(zakatProvider);
    final notifier = ref.read(zakatProvider.notifier);
    final prices = ref.watch(metalPriceProvider).snapshot;
    final result = ZakatEngine.calculate(
      assets: ref.watch(assetProvider),
      prices: prices,
      settings: settings,
      payments: notifier.payments,
      today: DateTime.now(),
    );
    final displayCurrency = ref.watch(displayCurrencyProvider);
    // The engine works in USD; the screen shows whatever the dashboard shows,
    // so the same obligation reads the same on both.
    final amountDue = CurrencyConverter.forDisplay(
      result.amountDueUsd,
      displayCurrency,
      prices: prices,
    );
    final eligibleWealth = CurrencyConverter.forDisplay(
      result.eligibleWealthUsd,
      displayCurrency,
      prices: prices,
    );
    final nisab = result.nisabThresholdUsd == null
        ? null
        : CurrencyConverter.forDisplay(
            result.nisabThresholdUsd!,
            displayCurrency,
            prices: prices,
          );
    final colors = context.kinetic;

    final sectionDivider = Divider(
      height: 48,
      thickness: 1,
      color: colors.border.withValues(alpha: 0.15),
    );

    return CustomScrollView(
      key: const Key('zakat_scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(
            eyebrow: null,
            title: 'Due and nisab',
            detail: 'Eligible wealth and payment state.',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          sliver: SliverList.list(
            children: [
              _ZakatSettingsBlock(settings: settings),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final heroSize = (constraints.maxWidth * 0.11).clamp(
                    44.0,
                    60.0,
                  );
                  return LedgerFrame(
                    cardless: true,
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        KineticText(
                          'AMOUNT DUE',
                          style: AppTheme.labelStyle(colors).copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: KineticNumber(
                              amountDue.formatted,
                              key: const Key('zakat_amount_due'),
                              fontSize: heroSize,
                              currency: amountDue.currency,
                              color: result.hasPaymentDue
                                  ? colors.accent
                                  : colors.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  KineticText(
                                    'ELIGIBLE WEALTH',
                                    style: AppTheme.labelStyle(colors).copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                      color: colors.mutedForeground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: KineticNumber(
                                      eligibleWealth.formatted,
                                      fontSize: 20,
                                      currency: eligibleWealth.currency,
                                      color: colors.foreground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 32,
                              width: 1,
                              color: colors.border.withValues(alpha: 0.15),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  KineticText(
                                    'NISAB',
                                    style: AppTheme.labelStyle(colors).copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                      color: colors.mutedForeground,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: KineticNumber(
                                      nisab == null
                                          ? 'Awaiting'
                                          : nisab.formatted,
                                      fontSize: 20,
                                      currency: nisab?.currency,
                                      color: colors.foreground,
                                    ),
                                  ),
                                  if (result.nisabThresholdUsd != null) ...[
                                    const SizedBox(height: 2),
                                    KineticText(
                                      result.settings.nisabStandard.label,
                                      muted: true,
                                      style: AppTheme.bodyStyle(
                                        colors,
                                      ).copyWith(fontSize: 10),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (result.message != null) ...[
                          const SizedBox(height: 20),
                          KineticText(
                            result.message!,
                            muted: true,
                            uppercase: false,
                            align: TextAlign.center,
                            style: AppTheme.bodyStyle(
                              colors,
                            ).copyWith(fontSize: 13),
                          ),
                        ],
                        if (result.hasPaymentDue) ...[
                          const SizedBox(height: 20),
                          ZakatMarkPaidButton(result: result),
                        ],
                      ],
                    ),
                  );
                },
              ),
              sectionDivider,
              KineticText(
                'Holdings',
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
              ),
              const SizedBox(height: 14),
              if (!result.canCalculate)
                const LedgerFrame(
                  cardless: true,
                  padding: EdgeInsets.zero,
                  child: KineticText(
                    'Refresh metal prices from Settings first.',
                  ),
                )
              else if (result.assessments.isEmpty)
                const LedgerFrame(
                  cardless: true,
                  padding: EdgeInsets.zero,
                  child: KineticText('No assets added yet.'),
                )
              else ...[
                for (var i = 0; i < result.assessments.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 24,
                      thickness: 1,
                      color: colors.border.withValues(alpha: 0.15),
                    ),
                  _AssessmentTile(
                    result.assessments[i],
                    displayCurrency: displayCurrency,
                    prices: prices,
                    cardless: true,
                  ),
                ],
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _ZakatSettingsBlock extends ConsumerWidget {
  const _ZakatSettingsBlock({required this.settings});

  final ZakatSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final notifier = ref.read(zakatProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: KineticDropdown<ZakatScheduleMode>(
                key: const Key('zakat_schedule_mode'),
                label: 'Schedule',
                value: settings.scheduleMode,
                items: ZakatScheduleMode.values,
                onChanged: (mode) {
                  if (mode != null) notifier.setScheduleMode(mode);
                },
                itemLabelBuilder: (mode) => mode.label,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: KineticDropdown<NisabStandard>(
                key: const Key('zakat_nisab_standard'),
                label: 'Nisab Standard',
                value: settings.nisabStandard,
                items: NisabStandard.values,
                onChanged: (standard) {
                  if (standard != null) notifier.setNisabStandard(standard);
                },
                itemLabelBuilder: (standard) => standard.label,
              ),
            ),
          ],
        ),
        if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) ...[
          const SizedBox(height: 16),
          KineticDatePickerTile(
            key: const Key('select_ramadan_due_date'),
            label: 'Next Ramadan',
            value: settings.nextRamadanDueDate == null
                ? 'Select date'
                : _formatDate(settings.nextRamadanDueDate!),
            selected: settings.nextRamadanDueDate != null,
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: settings.nextRamadanDueDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null) await notifier.setRamadanDueDate(date);
            },
          ),
        ],
        const SizedBox(height: 16),
        KineticText(
          settings.scheduleMode == ZakatScheduleMode.ramadanAnnual
              ? 'On your Ramadan date, all active valued holdings are assessed once.'
              : 'Check monthly; only holdings past one lunar year and not already paid this cycle are assessed.',
          muted: true,
          uppercase: false,
          style: AppTheme.bodyStyle(colors).copyWith(fontSize: 12),
        ),
      ],
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final displayCurrency = ref.watch(displayCurrencyProvider);
    final metalPriceState = ref.watch(metalPriceProvider);
    final colors = context.kinetic;
    return CustomScrollView(
      key: const Key('settings_scroll'),
      slivers: [
        const SliverToBoxAdapter(
          child: _PageHeader(
            title: 'Preferences',
            detail: 'Preferences, security, prices, and alerts.',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
          sliver: SliverList.list(
            children: [
              _SettingsSection(
                title: 'Preferences',
                children: [
                  _SettingsActionRow(
                    key: const Key('theme_mode_toggle'),
                    title: 'Theme mode',
                    detail: themeMode == ThemeMode.dark
                        ? 'Dark mode'
                        : 'Light mode',
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                  Divider(
                    height: 24,
                    thickness: 1,
                    color: colors.border.withValues(alpha: 0.15),
                  ),
                  _SettingsCurrencyRow(
                    selectedCurrency: displayCurrency,
                    onSelected: (currency) => ref
                        .read(displayCurrencyProvider.notifier)
                        .setCurrency(currency),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: 'Security',
                children: const [SecuritySettingsCard()],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: 'Alerts',
                children: const [NotificationSettingsScreen()],
              ),
              const SizedBox(height: 28),
              _SettingsSection(
                title: 'Prices',
                children: [
                  MetalPricesCard(state: metalPriceState),
                  const SizedBox(height: 16),
                  const LedgerFrame(
                    cardless: true,
                    padding: EdgeInsets.zero,
                    child: KineticText(
                      'Totals and dashboard graphs are shown in USD or AED, whose peg is fixed. Holdings in any other currency stay in your ledger but are left out of valuation until a live exchange-rate source is added.',
                      muted: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(
          title,
          uppercase: true,
          style: AppTheme.labelStyle(
            colors,
          ).copyWith(color: colors.accent, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    super.key,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return PressableScale(
      onTap: onTap,
      scale: 0.99,
      child: _SettingsSurface(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    title,
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 4),
                  KineticText(
                    detail,
                    muted: true,
                    style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.mutedForeground,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCurrencyRow extends StatelessWidget {
  const _SettingsCurrencyRow({
    required this.selectedCurrency,
    required this.onSelected,
  });

  final String selectedCurrency;
  final ValueChanged<String> onSelected;

  static const _currencySymbols = {'USD': '\$', 'EUR': '€', 'AED': 'د.إ'};

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return _SettingsSurface(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  'Display currency',
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                KineticText(
                  'Totals and charts',
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 125,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: colors.foreground.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.border.withValues(alpha: 0.10),
                width: 1.0,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('settings_currency_dropdown'),
                value: selectedCurrency,
                isExpanded: true,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: colors.accent,
                  size: 20,
                ),
                dropdownColor: colors.background,
                borderRadius: BorderRadius.circular(8),
                style: AppTheme.bodyStyle(colors).copyWith(
                  color: colors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                onChanged: (val) {
                  if (val != null) onSelected(val);
                },
                items: CurrencyConverter.supportedCurrencies.map((currency) {
                  final symbol = _currencySymbols[currency] ?? '';
                  return DropdownMenuItem<String>(
                    key: Key('settings_currency_option_$currency'),
                    value: currency,
                    child: Text('$currency ($symbol)'),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSurface extends StatelessWidget {
  const _SettingsSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity, child: child);
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: colors.background,
        centerTitle: true,
        leading: IconButton(
          key: const Key('close_notifications'),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: KineticText(
          'Notifications',
          style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          key: const Key('notifications_scroll'),
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 24),
              sliver: SliverToBoxAdapter(child: NotificationSettingsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    this.eyebrow,
    required this.title,
    required this.detail,
  });

  final String? eyebrow;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, eyebrow == null ? 6 : 16, 16, 0),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: eyebrow == null ? 4 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              KineticText(
                eyebrow!.toUpperCase(),
                muted: true,
                style: AppTheme.labelStyle(colors).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 6),
            ],
            KineticText(
              title,
              style: AppTheme.titleStyle(
                colors,
              ).copyWith(fontSize: 24, color: colors.foreground),
            ),
            const SizedBox(height: 6),
            KineticText(
              detail,
              muted: true,
              style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardFiltersCard extends StatelessWidget {
  const DashboardFiltersCard({
    super.key,
    required this.assets,
    required this.filter,
    required this.onTypeSelected,
    required this.onTagSelected,
    required this.onSelectFromDate,
    required this.onSelectToDate,
    required this.onClear,
  });

  final List<Asset> assets;
  final DashboardFilter filter;
  final ValueChanged<AssetType?> onTypeSelected;
  final ValueChanged<AssetTag?> onTagSelected;
  final VoidCallback onSelectFromDate;
  final VoidCallback onSelectToDate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final visibleTypes = [
      AssetType.cash,
      AssetType.gold,
      AssetType.silver,
      if (assets.any((asset) => asset.type == AssetType.bankSavings))
        AssetType.bankSavings,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: KineticText(
                'Filters',
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 18),
              ),
            ),
            if (filter.isActive)
              TextButton(
                key: const Key('clear_dashboard_filters'),
                onPressed: onClear,
                child: KineticText(
                  'Reset',
                  style: AppTheme.labelStyle(
                    colors,
                  ).copyWith(color: colors.accent),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _FilterRail(
          label: 'Type',
          children: [
            FilterBlock(
              key: const Key('filter_type_all'),
              label: 'All',
              selected: filter.type == null,
              onTap: () => onTypeSelected(null),
            ),
            ...visibleTypes.map(
              (type) => FilterBlock(
                key: Key('filter_type_${type.name}'),
                label: type.label,
                selected: filter.type == type,
                onTap: () => onTypeSelected(type),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FilterRail(
          label: 'Tag',
          children: [
            FilterBlock(
              key: const Key('filter_tag_all'),
              label: 'All',
              selected: filter.tag == null,
              onTap: () => onTagSelected(null),
            ),
            ...AssetTag.values.map(
              (tag) => FilterBlock(
                key: Key('filter_tag_${tag.name}'),
                label: tag.label,
                selected: filter.tag == tag,
                onTap: () => onTagSelected(tag),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        KineticText('Date', style: AppTheme.labelStyle(colors)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: KineticDatePickerTile(
                key: const Key('filter_from_date'),
                label: 'From',
                value: filter.fromDate == null
                    ? 'Any date'
                    : _formatDate(filter.fromDate!),
                selected: filter.fromDate != null,
                onTap: onSelectFromDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KineticDatePickerTile(
                key: const Key('filter_to_date'),
                label: 'To',
                value: filter.toDate == null
                    ? 'Any date'
                    : _formatDate(filter.toDate!),
                selected: filter.toDate != null,
                onTap: onSelectToDate,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterRail extends StatefulWidget {
  const _FilterRail({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  State<_FilterRail> createState() => _FilterRailState();
}

class _FilterRailState extends State<_FilterRail> {
  var _fadeStart = false;
  var _fadeEnd = false;

  /// Fades whichever edge has more chips past it. On a phone the tag rail runs
  /// off the screen with nothing to say so - "Salary" is sliced in half and
  /// "Business Profit" is not visible at all.
  void _syncEdges(ScrollMetrics metrics) {
    final fadeStart = metrics.extentBefore > 1;
    final fadeEnd = metrics.extentAfter > 1;
    if (fadeStart == _fadeStart && fadeEnd == _fadeEnd) return;
    // Notifications arrive mid-layout, so the rebuild has to wait for the
    // frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _fadeStart = fadeStart;
        _fadeEnd = fadeEnd;
      });
    });
  }

  Shader _edgeFade(Rect bounds) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        _fadeStart ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
        _fadeEnd ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
      ],
      stops: const [0, 0.06, 0.92, 1],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(widget.label, style: AppTheme.labelStyle(colors)),
        const SizedBox(height: 8),
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _syncEdges(notification.metrics);
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _syncEdges(notification.metrics);
              return false;
            },
            child: ShaderMask(
              shaderCallback: _edgeFade,
              blendMode: BlendMode.dstIn,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (
                      var index = 0;
                      index < widget.children.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(width: 8),
                      widget.children[index],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MetalPricesCard extends ConsumerWidget {
  const MetalPricesCard({super.key, required this.state});

  final MetalPriceState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final snapshot = state.snapshot;
    return LedgerFrame(
      cardless: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KineticText(
                  'Metal prices',
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
                ),
              ),
              if (state.isRefreshing)
                SizedBox(
                  height: 26,
                  width: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colors.accent,
                  ),
                )
              else
                BrutalistButton(
                  key: const Key('refresh_metal_prices'),
                  label: 'Refresh',
                  tone: BrutalistButtonTone.primary,
                  onPressed: () =>
                      ref.read(metalPriceProvider.notifier).refreshPrices(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (snapshot == null)
            const KineticText(
              'Tap refresh to load gold and silver prices.',
              muted: true,
            )
          else
            Column(
              children: [
                _MetalPriceRow(
                  label: 'Gold',
                  value: _formatMoney(snapshot.goldPerGramUsd),
                ),
                Divider(
                  height: 24,
                  thickness: 1,
                  color: colors.border.withValues(alpha: 0.15),
                ),
                _MetalPriceRow(
                  label: 'Silver',
                  value: _formatMoney(snapshot.silverPerGramUsd),
                ),
                Divider(
                  height: 24,
                  thickness: 1,
                  color: colors.border.withValues(alpha: 0.15),
                ),
                _MetalPriceRow(
                  label: state.isCached ? 'Cached price' : 'Updated',
                  value: _formatTimestamp(snapshot.priceTimestamp),
                  isDetail: true,
                ),
              ],
            ),
          if (state.errorMessage != null) ...[
            const SizedBox(height: 12),
            KineticText(
              state.errorMessage!,
              key: const Key('metal_price_error'),
              style: AppTheme.bodyStyle(colors).copyWith(color: colors.danger),
              uppercase: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetalPriceRow extends StatelessWidget {
  const _MetalPriceRow({
    required this.label,
    required this.value,
    this.isDetail = false,
  });

  final String label;
  final String value;
  final bool isDetail;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  label.toUpperCase(),
                  style: AppTheme.labelStyle(colors).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: colors.mutedForeground,
                  ),
                ),
                if (!isDetail) ...[
                  const SizedBox(height: 2),
                  KineticText(
                    'per gram',
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(fontSize: 11, color: colors.mutedForeground),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  KineticText(
                    'local time',
                    style: AppTheme.bodyStyle(
                      colors,
                    ).copyWith(fontSize: 11, color: colors.mutedForeground),
                  ),
                ],
              ],
            ),
          ),
          if (isDetail)
            KineticText(
              value,
              style: AppTheme.bodyStyle(colors).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.foreground,
              ),
            )
          else
            KineticNumber(
              value,
              fontSize: 22,
              currency: CurrencyConverter.defaultCurrency,
              color: colors.foreground,
            ),
        ],
      ),
    );
  }
}

class AssetTile extends ConsumerWidget {
  const AssetTile({super.key, required this.asset, this.cardless = false});

  final Asset asset;
  final bool cardless;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final isSold = asset.isSold;
    final displayCurrency = ref.watch(displayCurrencyProvider);
    // Grams of gold say nothing about what a holding is worth, and neither
    // does an amount recorded in a currency the totals are not shown in.
    final needsValue =
        !isSold &&
        (asset.type.isMetal ||
            CurrencyConverter.normalize(asset.currency) !=
                CurrencyConverter.normalize(displayCurrency));
    final value = needsValue
        ? WealthCalculator.valueAsset(
            asset,
            ref.watch(metalPriceProvider).snapshot,
            displayCurrency: displayCurrency,
          )
        : null;
    return LedgerFrame(
      cardless: cardless,
      padding: cardless
          ? const EdgeInsets.symmetric(vertical: 12)
          : const EdgeInsets.all(14),
      background: cardless
          ? Colors.transparent
          : (isSold ? colors.muted : colors.background),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AssetTypeIcon(type: asset.type, isSold: isSold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KineticText(
                      asset.type.label,
                      style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
                    ),
                  ),
                  if (asset.tag != null) const SizedBox(width: 8),
                  if (asset.tag != null)
                    Container(
                      key: Key('asset_tag_chip_${asset.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: 0.16),
                        borderRadius: AppTheme.pillRadius,
                        border: Border.all(
                          color: colors.accent.withValues(alpha: 0.46),
                          width: AppTheme.hairlineWidth,
                        ),
                      ),
                      child: KineticText(
                        asset.tag!.label,
                        style: AppTheme.labelStyle(
                          colors,
                        ).copyWith(color: colors.accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              KineticNumber(
                '${_trimNumber(asset.amount)} ${asset.unit}',
                fontSize: 28,
                color: isSold ? colors.mutedForeground : colors.foreground,
                currency: asset.type.isMetal ? null : asset.currency,
              ),
              if (needsValue) ...[
                const SizedBox(height: 6),
                KineticText(
                  value == null
                      ? (asset.type.isMetal
                            ? 'Worth unknown until prices refresh'
                            : 'Worth unknown: no '
                                  '${CurrencyConverter.normalize(asset.currency)} '
                                  'exchange rate')
                      : 'Worth ${CurrencyConverter.formatMoney(value, displayCurrency)}',
                  key: Key('asset_value_${asset.id}'),
                  muted: true,
                  uppercase: false,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
                ),
              ],
              if (asset.type.isMetal) ...[
                const SizedBox(height: 8),
                KineticText(
                  [
                    '${asset.purity ?? '-'}% purity',
                    if (asset.boughtPrice != null)
                      'Bought ${CurrencyConverter.formatMoney(asset.boughtPrice!, asset.currency)}',
                  ].join(' / '),
                  key: Key('asset_metal_detail_${asset.id}'),
                  muted: true,
                ),
              ],
              if (asset.note != null && asset.note!.isNotEmpty) ...[
                const SizedBox(height: 8),
                KineticText(
                  asset.note!,
                  muted: true,
                  uppercase: false,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
                ),
              ],
              if (asset.isSold) ...[
                const SizedBox(height: 8),
                KineticText(
                  'Sold',
                  style: AppTheme.labelStyle(
                    colors,
                  ).copyWith(color: colors.profit),
                ),
              ],
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BrutalistButton(
                key: Key('edit_asset_${asset.id}'),
                label: 'Edit',
                onPressed: () =>
                    _showAssetFormDialog(context, ref, asset: asset),
              ),
              BrutalistButton(
                key: Key('delete_asset_${asset.id}'),
                label: 'Delete',
                tone: BrutalistButtonTone.danger,
                onPressed: () => _confirmDeleteAsset(context, ref, asset),
              ),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _AssetTypeIcon extends StatelessWidget {
  const _AssetTypeIcon({required this.type, this.isSold = false});

  final AssetType type;
  final bool isSold;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final icon = switch (type) {
      AssetType.cash => Icons.payments_outlined,
      AssetType.bankSavings => Icons.account_balance_outlined,
      AssetType.gold => Icons.workspace_premium_outlined,
      AssetType.silver => Icons.circle_outlined,
    };
    final foreground = isSold ? colors.mutedForeground : colors.accent;
    final background = isSold
        ? colors.muted
        : colors.accent.withValues(alpha: 0.16);
    return _LedgerIcon(
      icon: icon,
      foreground: foreground,
      background: background,
    );
  }
}

class _LedgerIcon extends StatelessWidget {
  const _LedgerIcon({
    required this.icon,
    required this.foreground,
    required this.background,
    this.size = 40,
  });

  final IconData icon;
  final Color foreground;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppTheme.tightRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.56),
          width: AppTheme.hairlineWidth,
        ),
      ),
      child: Icon(icon, color: foreground, size: size * 0.48),
    );
  }
}

class _TransactionEventRow extends StatelessWidget {
  const _TransactionEventRow({required this.event, this.cardless = false});

  final TransactionEvent event;
  final bool cardless;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isSale = event.type == TransactionEventType.sold;
    final eventBackground = isSale ? colors.loss : colors.profit;
    final eventForeground = eventBackground.computeLuminance() < 0.35
        ? AppTheme.white
        : colors.accentForeground;
    final price = event.price == null
        ? 'No price'
        : CurrencyConverter.formatMoney(event.price!, event.asset.currency);
    return LedgerFrame(
      cardless: cardless,
      padding: cardless
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.all(12),
      borderWidth: 1,
      child: Row(
        children: [
          _LedgerIcon(
            icon: isSale
                ? Icons.remove_circle_outline
                : Icons.add_circle_outline,
            foreground: eventForeground,
            background: eventBackground,
            size: 42,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  '${isSale ? 'Sold' : 'Acquired'} ${event.asset.type.label}',
                  style: AppTheme.titleStyle(
                    colors,
                  ).copyWith(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                KineticText(
                  price,
                  muted: true,
                  style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          KineticNumber(
            '${_trimNumber(event.asset.amount)} ${event.asset.unit}',
            fontSize: 18,
            color: colors.foreground,
            currency: event.asset.type.isMetal ? null : event.asset.currency,
          ),
        ],
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile(
    this.assessment, {
    required this.displayCurrency,
    required this.prices,
    this.cardless = false,
  });

  final ZakatAssetAssessment assessment;
  final String displayCurrency;
  final MetalPriceSnapshot? prices;
  final bool cardless;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final value = assessment.valueUsd == null
        ? null
        : CurrencyConverter.forDisplay(
            assessment.valueUsd!,
            displayCurrency,
            prices: prices,
          );
    final status = assessment.isIncluded
        ? 'Included in amount due'
        : assessment.exclusionReason ?? 'Excluded';
    return LedgerFrame(
      cardless: cardless,
      padding: cardless
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  assessment.asset.type.label,
                  style: AppTheme.titleStyle(
                    colors,
                  ).copyWith(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                KineticText(
                  status,
                  muted: !assessment.isIncluded,
                  style: AppTheme.labelStyle(colors).copyWith(
                    color: assessment.isIncluded
                        ? colors.profit
                        : colors.mutedForeground,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          KineticNumber(
            value?.formatted ?? 'Not valued',
            fontSize: 18,
            currency: value?.currency,
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmDeleteAsset(
  BuildContext context,
  WidgetRef ref,
  Asset asset,
) async {
  final description =
      '${asset.type.label} - ${_trimNumber(asset.amount)} ${asset.unit}';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete this holding?'),
      content: Text(
        '$description will be removed permanently. This cannot be undone.',
      ),
      actions: [
        TextButton(
          key: const Key('cancel_delete_asset'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('confirm_delete_asset'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await ref.read(assetProvider.notifier).removeAsset(asset.id);
}

Future<void> _showAssetFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Asset? asset,
}) async {
  final result = await Navigator.of(
    context,
  ).push<Asset>(_kineticRoute<Asset>(AssetFormDialog(asset: asset)));
  if (result == null) return;

  final notifier = ref.read(assetProvider.notifier);
  if (asset == null) {
    await notifier.addAsset(result);
  } else {
    await notifier.updateAsset(result);
  }

  final justSold = result.isSold && !(asset?.isSold ?? false);
  if (justSold && context.mounted) {
    await _offerToRecordProceeds(context, ref, result);
  }
}

/// Offers to put the money from a sale back into the ledger.
///
/// Marking a holding sold takes it out of wealth and zakat but records
/// nothing in its place, so the proceeds simply vanish: sell 20g of gold for
/// $2,000 and the total drops by $2,000 with the money nowhere. It is offered
/// rather than automatic because the cash may already have been recorded by
/// hand, and adding it twice would be worse than not adding it at all.
Future<void> _offerToRecordProceeds(
  BuildContext context,
  WidgetRef ref,
  Asset sold,
) async {
  final proceeds = sold.soldPrice;
  if (proceeds == null || proceeds <= 0) return;

  final amount = CurrencyConverter.formatMoney(proceeds, sold.currency);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Record what you received?'),
      content: Text(
        'This sale takes ${sold.type.label.toLowerCase()} out of your wealth '
        'and zakat. Add the $amount you received as cash so it still counts. '
        'Skip if you have already recorded it.',
      ),
      actions: [
        TextButton(
          key: const Key('skip_sale_proceeds'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          key: const Key('record_sale_proceeds'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Add as cash'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await ref
      .read(assetProvider.notifier)
      .addAsset(buildSaleProceeds(sold, const Uuid().v4()));
}

/// The cash holding standing in for a sale.
///
/// It carries the sold holding's own start date, not the sale date, so the
/// lunar year continues across the sale. Restarting it would let selling just
/// before an anniversary reset the zakat owed on that wealth.
@visibleForTesting
Asset buildSaleProceeds(Asset sold, String id) {
  return Asset(
    id: id,
    type: AssetType.cash,
    amount: sold.soldPrice!,
    unit: sold.currency,
    currency: sold.currency,
    boughtDate: sold.boughtDate,
    tag: sold.tag,
    note:
        'Proceeds from selling ${_trimNumber(sold.amount)} ${sold.unit} '
        'of ${sold.type.label.toLowerCase()}',
  );
}

PageRouteBuilder<T> _kineticRoute<T>(Widget child) {
  return PageRouteBuilder<T>(
    transitionDuration: AppTheme.fast,
    reverseTransitionDuration: AppTheme.fast,
    pageBuilder: (context, animation, secondaryAnimation) => child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      );
    },
  );
}

Map<DateTime, List<TransactionEvent>> _groupEventsByDate(
  List<TransactionEvent> events,
) {
  final sorted = [...events]..sort((a, b) => b.date.compareTo(a.date));
  final grouped = <DateTime, List<TransactionEvent>>{};
  for (final event in sorted) {
    final key = DateTime(event.date.year, event.date.month, event.date.day);
    grouped.putIfAbsent(key, () => []).add(event);
  }
  return grouped;
}

List<String> _metalTickerItems(MetalPriceState state, String displayCurrency) {
  final snapshot = state.snapshot;
  if (state.isRefreshing) {
    return const [
      'REFRESHING METAL PRICES',
      'GOLD PRICE UPDATING',
      'SILVER PRICE UPDATING',
    ];
  }
  if (snapshot == null) {
    return const [
      'GOLD PRICE PENDING',
      'SILVER PRICE PENDING',
      'REFRESH METALS IN SETTINGS',
    ];
  }
  // Prices are fetched in USD per gram; show them in whatever currency the
  // totals above the ticker are in, so the two do not disagree.
  final gold = CurrencyConverter.convertFromUsd(
    snapshot.goldPerGramUsd,
    displayCurrency,
    prices: snapshot,
  );
  final silver = CurrencyConverter.convertFromUsd(
    snapshot.silverPerGramUsd,
    displayCurrency,
    prices: snapshot,
  );
  final currency = gold == null || silver == null
      ? CurrencyConverter.defaultCurrency
      : displayCurrency;
  return [
    'LIVE GOLD ${_formatMoney(gold ?? snapshot.goldPerGramUsd, currency: currency)} / G',
    'LIVE SILVER ${_formatMoney(silver ?? snapshot.silverPerGramUsd, currency: currency)} / G',
    '${state.isCached ? 'CACHED' : 'UPDATED'} ${_formatTimestamp(snapshot.priceTimestamp)}',
  ];
}

String _formatMoney(
  double value, {
  String currency = CurrencyConverter.defaultCurrency,
}) {
  return CurrencyConverter.formatMoney(value, currency);
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _formatTimestamp(DateTime date) {
  final localDate = date.toLocal();
  final month = localDate.month.toString().padLeft(2, '0');
  final day = localDate.day.toString().padLeft(2, '0');
  final hour = localDate.hour.toString().padLeft(2, '0');
  final minute = localDate.minute.toString().padLeft(2, '0');
  return '${localDate.year}-$month-$day $hour:$minute';
}

String _trimNumber(double value) {
  return CurrencyConverter.formatNumber(value);
}
