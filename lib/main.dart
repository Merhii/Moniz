import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/asset.dart';
import 'models/metal_price_snapshot.dart';
import 'models/portfolio_snapshot.dart';
import 'models/zakat_settings.dart';
import 'providers/asset_provider.dart';
import 'providers/display_currency_provider.dart';
import 'providers/metal_price_provider.dart';
import 'providers/portfolio_snapshot_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/zakat_provider.dart';
import 'services/dashboard_filter.dart';
import 'services/local_notification_service.dart';
import 'services/currency_converter.dart';
import 'services/position_performance.dart';
import 'services/portfolio_analytics.dart';
import 'services/transaction_history_service.dart';
import 'services/wealth_calculator.dart';
import 'services/zakat_engine.dart';
import 'theme/app_theme.dart';
import 'ui/kinetic/kinetic_widgets.dart';
import 'widgets/asset_form_dialog.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/notification_settings_screen.dart';
import 'widgets/portfolio_insights_card.dart';
import 'widgets/security_settings_card.dart';
import 'widgets/transaction_history_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(AssetTypeAdapter());
  Hive.registerAdapter(AssetTagAdapter());
  Hive.registerAdapter(AssetAdapter());
  Hive.registerAdapter(MetalPriceSnapshotAdapter());
  Hive.registerAdapter(ZakatScheduleModeAdapter());
  Hive.registerAdapter(NisabStandardAdapter());
  Hive.registerAdapter(ZakatSettingsAdapter());
  Hive.registerAdapter(ZakatPaymentRecordAdapter());
  Hive.registerAdapter(PortfolioSnapshotAdapter());

  await Hive.openBox<Asset>('assets');
  await Hive.openBox<MetalPriceSnapshot>('metalPrices');
  await Hive.openBox<ZakatSettings>('zakatSettings');
  await Hive.openBox<ZakatPaymentRecord>('zakatPayments');
  await Hive.openBox<PortfolioSnapshot>('portfolioSnapshots');
  await Hive.openBox<dynamic>('uiPreferences');

  await localNotificationService.initialize();

  runApp(const ProviderScope(child: MonizApp()));
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
      home: const KineticHome(),
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
      const DashboardPage(),
      const HoldingsPage(),
      const ZakatPage(),
      const SettingsPage(),
    ];
    final colors = context.kinetic;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: colors.background,
        leadingWidth: 64,
        leading: const SizedBox(width: 64),
        centerTitle: true,
        title: _selectedPage == 0
            ? const _MonizLogo()
            : KineticText(
                _selectedPage == 1
                    ? 'Ledger'
                    : _selectedPage == 2
                        ? 'Zakat'
                        : 'Settings',
                style: AppTheme.titleStyle(colors).copyWith(fontSize: 22),
              ),
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
      label: 'Wealth',
      icon: Icons.account_balance_wallet_outlined,
      key: Key('dashboard_nav'),
    ),
    (
      label: 'Ledger',
      icon: Icons.receipt_long_outlined,
      key: Key('holdings_nav'),
    ),
    (
      label: 'Zakat',
      icon: Icons.volunteer_activism_outlined,
      key: Key('zakat_nav'),
    ),
    (label: 'Settings', icon: Icons.tune_rounded, key: Key('settings_nav')),
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
    final displayZakat =
        CurrencyConverter.convertFromUsd(
          zakatResult.amountDueUsd,
          displayCurrency,
          prices: metalPriceState.snapshot,
        ) ??
        zakatResult.amountDueUsd;
    final summaryNote = [
      if (totals.hasUnpricedMetals)
        'Refresh metal prices in Settings to include metal holdings.',
      if (totals.hasUnsupportedCurrencies)
        'Some holdings use unsupported currencies and are excluded.',
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
            zakat: displayZakat,
            currency: totals.currency,
            onCurrencySelected: (currency) => ref
                .read(displayCurrencyProvider.notifier)
                .setCurrency(currency),
            note: summaryNote.isEmpty ? null : summaryNote,
          ),
        ),
        SliverToBoxAdapter(
          child: TickerTape(
            height: 40,
            fontSize: 13,
            items: _metalTickerItems(metalPriceState),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
              ),
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
                    pageBuilder: (_, _, _) => const TransactionHistoryScreen(),
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
              ProfitLossCard(
                summary: performance,
                cardless: true,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
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

class _WealthHero extends StatelessWidget {
  const _WealthHero({
    required this.wealthLabel,
    required this.totalWealth,
    required this.zakat,
    required this.currency,
    required this.onCurrencySelected,
    this.note,
  });

  final String wealthLabel;
  final double totalWealth;
  final double zakat;
  final String currency;
  final ValueChanged<String> onCurrencySelected;
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
                _CurrencySelector(
                  selectedCurrency: currency,
                  onSelected: onCurrencySelected,
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
                      _formatMoney(zakat, currency: currency),
                      fontSize: 20,
                      color: colors.accent,
                      currency: currency,
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

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({
    required this.selectedCurrency,
    required this.onSelected,
  });

  final String selectedCurrency;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.28),
        borderRadius: AppTheme.pillRadius,
        border: Border.all(
          color: colors.border.withValues(alpha: 0.5),
          width: AppTheme.hairlineWidth,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: CurrencyConverter.supportedCurrencies
            .map(
              (currency) => CurrencyChip(
                key: Key('home_display_currency_$currency'),
                currency: currency,
                selected: selectedCurrency == currency,
                onTap: () => onSelected(currency),
                compact: true,
              ),
            )
            .toList(),
      ),
    );
  }
}

class HoldingsPage extends ConsumerWidget {
  const HoldingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetProvider);
    final events = TransactionHistoryService.eventsFor(assets);
    final groupedEvents = _groupEventsByDate(events);
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: _PageHeader(
          eyebrow: null,
          title: 'Holdings',
          detail: 'Add, edit, and scan asset records.',
          trailing: BrutalistButton(
            key: const Key('add_asset_button'),
            label: 'Add asset',
            tone: BrutalistButtonTone.primary,
            onPressed: () => _showAssetFormDialog(context, ref),
          ),
        ),
      ),
      if (assets.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LedgerFrame(
              cardless: true,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: KineticText('No assets yet'),
                ),
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          sliver: SliverList.separated(
            itemCount: assets.length,
            itemBuilder: (context, index) => AssetTile(asset: assets[index], cardless: true),
            separatorBuilder: (context, index) => Divider(
              height: 32,
              thickness: 1,
              color: context.kinetic.border.withValues(alpha: 0.15),
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: KineticText(
            'Transaction history',
            style: AppTheme.titleStyle(context.kinetic).copyWith(fontSize: 22),
          ),
        ),
      ),
    ];

    if (groupedEvents.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
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
      );
    } else {
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
    }

    return CustomScrollView(
      key: const Key('holdings_scroll'),
      slivers: slivers,
    );
  }
}

class ZakatPage extends ConsumerWidget {
  const ZakatPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(zakatProvider);
    final notifier = ref.read(zakatProvider.notifier);
    final result = ZakatEngine.calculate(
      assets: ref.watch(assetProvider),
      prices: ref.watch(metalPriceProvider).snapshot,
      settings: settings,
      payments: notifier.payments,
      today: DateTime.now(),
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
                  final heroSize = (constraints.maxWidth * 0.11).clamp(44.0, 60.0);
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
                              _formatMoney(result.amountDueUsd),
                              key: const Key('zakat_amount_due'),
                              fontSize: heroSize,
                              currency: CurrencyConverter.defaultCurrency,
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
                                      _formatMoney(result.eligibleWealthUsd),
                                      fontSize: 20,
                                      currency: CurrencyConverter.defaultCurrency,
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
                                      result.nisabThresholdUsd == null
                                          ? 'Awaiting'
                                          : _formatMoney(result.nisabThresholdUsd!),
                                      fontSize: 20,
                                      currency: result.nisabThresholdUsd == null
                                          ? null
                                          : CurrencyConverter.defaultCurrency,
                                      color: colors.foreground,
                                    ),
                                  ),
                                  if (result.nisabThresholdUsd != null) ...[
                                    const SizedBox(height: 2),
                                    KineticText(
                                      result.settings.nisabStandard.label,
                                      muted: true,
                                      style: AppTheme.bodyStyle(colors).copyWith(fontSize: 10),
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
                          BrutalistButton(
                            key: const Key('mark_zakat_paid'),
                            label: 'Mark as paid',
                            tone: BrutalistButtonTone.primary,
                            onPressed: () async {
                              await ref
                                  .read(zakatProvider.notifier)
                                  .recordPayment(result, DateTime.now());
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Zakat payment recorded.'),
                                  ),
                                );
                              }
                            },
                          ),
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
                  _AssessmentTile(result.assessments[i], cardless: true),
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
                      'USD, AED, and EUR are converted for totals and dashboard graphs. Other currencies remain recorded but are excluded until FX rates are added.',
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

  static const _currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'AED': 'د.إ',
  };

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
    return SizedBox(
      width: double.infinity,
      child: child,
    );
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
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: KineticText(
                    'Future implementation',
                    muted: true,
                  ),
                ),
              ),
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
    this.trailing,
  });

  final String? eyebrow;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, eyebrow == null ? 6 : 16, 16, 0),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: eyebrow == null ? 4 : 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
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
            );
            if (trailing == null || constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  content,
                  if (trailing != null) ...[
                    const SizedBox(height: 14),
                    trailing!,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: content),
                const SizedBox(width: 18),
                trailing!,
              ],
            );
          },
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

class _FilterRail extends StatelessWidget {
  const _FilterRail({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KineticText(label, style: AppTheme.labelStyle(colors)),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                children[index],
              ],
            ],
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
              style: AppTheme.bodyStyle(colors).copyWith(color: colors.loss),
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
                    style: AppTheme.bodyStyle(colors).copyWith(
                      fontSize: 11,
                      color: colors.mutedForeground,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  KineticText(
                    'local time',
                    style: AppTheme.bodyStyle(colors).copyWith(
                      fontSize: 11,
                      color: colors.mutedForeground,
                    ),
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
  const AssetTile({
    super.key,
    required this.asset,
    this.cardless = false,
  });

  final Asset asset;
  final bool cardless;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final isSold = asset.isSold;
    return LedgerFrame(
      cardless: cardless,
      padding: cardless ? const EdgeInsets.symmetric(vertical: 12) : const EdgeInsets.all(14),
      background: cardless ? Colors.transparent : (isSold ? colors.muted : colors.background),
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
              if (asset.type.isMetal) ...[
                const SizedBox(height: 8),
                KineticText(
                  [
                    '${asset.purity ?? '-'}% purity',
                    'Prices in ${asset.currency}',
                    if (asset.boughtPrice != null)
                      'Bought ${CurrencyConverter.formatMoney(asset.boughtPrice!, asset.currency)}',
                  ].join(' / '),
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
                label: 'Edit',
                onPressed: () =>
                    _showAssetFormDialog(context, ref, asset: asset),
              ),
              BrutalistButton(
                label: 'Delete',
                tone: BrutalistButtonTone.danger,
                onPressed: () =>
                    ref.read(assetProvider.notifier).removeAsset(asset.id),
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
  const _TransactionEventRow({
    required this.event,
    this.cardless = false,
  });

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
      padding: cardless ? const EdgeInsets.symmetric(vertical: 10) : const EdgeInsets.all(12),
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
                  style: AppTheme.titleStyle(colors).copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
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
    this.cardless = false,
  });

  final ZakatAssetAssessment assessment;
  final bool cardless;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final value = assessment.valueUsd == null
        ? 'Not valued'
        : _formatMoney(assessment.valueUsd!);
    final status = assessment.isIncluded
        ? 'Included in amount due'
        : assessment.exclusionReason ?? 'Excluded';
    return LedgerFrame(
      cardless: cardless,
      padding: cardless ? const EdgeInsets.symmetric(vertical: 10) : const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KineticText(
                  assessment.asset.type.label,
                  style: AppTheme.titleStyle(colors).copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
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
            value,
            fontSize: 18,
            currency: assessment.valueUsd == null
                ? null
                : CurrencyConverter.defaultCurrency,
          ),
        ],
      ),
    );
  }
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

List<String> _metalTickerItems(MetalPriceState state) {
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
  return [
    'LIVE GOLD ${_formatMoney(snapshot.goldPerGramUsd)} / G',
    'LIVE SILVER ${_formatMoney(snapshot.silverPerGramUsd)} / G',
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
