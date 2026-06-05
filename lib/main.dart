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
import 'services/currency_converter.dart';
import 'services/position_performance.dart';
import 'services/portfolio_analytics.dart';
import 'services/transaction_history_service.dart';
import 'services/wealth_calculator.dart';
import 'services/zakat_engine.dart';
import 'theme/app_theme.dart';
import 'ui/kinetic/kinetic_widgets.dart';
import 'widgets/asset_form_dialog.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/portfolio_insights_card.dart';
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
      body: DecoratedBox(
        decoration: AppTheme.brandBackground(colors),
        child: SafeArea(
          bottom: false,
          child: IndexedStack(index: _selectedPage, children: pages),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _KineticNav(selectedIndex: _selectedPage, onSelected: _setPage),
      ),
    );
  }

  void _setPage(int index) {
    setState(() => _selectedPage = index);
  }
}

class _KineticNav extends StatelessWidget {
  const _KineticNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _tabs = [
    ('WEALTH', Key('dashboard_nav')),
    ('LEDGER', Key('holdings_nav')),
    ('ZAKAT', Key('zakat_nav')),
    ('SYSTEM', Key('settings_nav')),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.72),
        border: Border(
          top: BorderSide(
            color: colors.border,
            width: AppTheme.thickBorderWidth,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < _tabs.length; index++) ...[
            Expanded(
              child: PressableScale(
                key: _tabs[index].$2,
                onTap: () => onSelected(index),
                scale: 0.98,
                child: AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : AppTheme.fast,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: selectedIndex == index
                        ? colors.accent
                        : colors.muted.withValues(alpha: 0.7),
                    borderRadius: AppTheme.pillRadius,
                    border: Border.all(
                      color: selectedIndex == index
                          ? colors.accent
                          : colors.border.withValues(alpha: 0.74),
                      width: AppTheme.thickBorderWidth,
                    ),
                    boxShadow: selectedIndex == index
                        ? AppTheme.glowShadow(colors)
                        : null,
                  ),
                  child: KineticText(
                    _tabs[index].$1,
                    align: TextAlign.center,
                    style: AppTheme.labelStyle(colors).copyWith(
                      color: selectedIndex == index
                          ? colors.accentForeground
                          : colors.foreground,
                      fontSize: 13,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ),
            if (index != _tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
        'Refresh metal prices in SYSTEM to include metal holdings.',
      if (totals.hasUnsupportedCurrencies)
        'Some holdings use unsupported currencies and are excluded.',
    ].join(' ');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _WealthHero(
            wealthLabel: _filter.isActive ? 'Filtered Wealth' : 'Total Wealth',
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
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 14),
              KineticText(
                _filter.isActive
                    ? 'Showing ${filteredAssets.length} of ${assets.length} holdings'
                    : 'Showing all ${assets.length} holdings',
                key: const Key('dashboard_filter_result'),
                muted: true,
              ),
              const SizedBox(height: 14),
              PortfolioInsightsCard(
                analytics: analytics,
                snapshotAnalytics: completeAnalyticsUsd,
                isFiltered: _filter.isActive,
                onOpenHistory: () => Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    reverseTransitionDuration: Duration.zero,
                    pageBuilder: (_, _, _) => const TransactionHistoryScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              PortfolioTrendCard(
                snapshots: snapshots,
                performance: completePerformance,
                assets: assets,
                metalPriceHistory: metalPriceState.historicalPrices,
                displayCurrency: displayCurrency,
              ),
              const SizedBox(height: 14),
              ProfitLossCard(summary: performance),
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
        final heroSize = (constraints.maxWidth * 0.095).clamp(40.0, 72.0);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 300),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            decoration: AppTheme.heroSurface(colors),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  right: -54,
                  top: -72,
                  child: _GlowOrb(
                    size: 178,
                    color: colors.accent.withValues(alpha: 0.18),
                  ),
                ),
                Positioned(
                  right: 54,
                  bottom: -88,
                  child: _GlowOrb(
                    size: 154,
                    color: AppTheme.lightGold.withValues(alpha: 0.10),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        KineticText(
                          'WEALTH / LIVE POSITION',
                          style: AppTheme.labelStyle(colors),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    KineticText(
                      wealthLabel,
                      style: AppTheme.displayStyle(
                        colors,
                      ).copyWith(fontSize: 42, color: colors.foreground),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: KineticNumber(
                          _formatMoney(totalWealth, currency: currency),
                          key: const Key('wealth_hero_total'),
                          fontSize: heroSize,
                          color: colors.accent,
                          currency: currency,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
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
                          child: const Text('HISTORY'),
                        ),
                        _CurrencySelector(
                          selectedCurrency: currency,
                          onSelected: onCurrencySelected,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    BrutalistGrid(
                      minTileWidth: 210,
                      children: [
                        MetricBlock(
                          label: 'Zakat due',
                          value: _formatMoney(zakat, currency: currency),
                          valueColor: colors.profit,
                          currency: currency,
                          detail: 'ALL HOLDINGS',
                        ),
                      ],
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 14),
                      KineticText(
                        note!,
                        muted: true,
                        uppercase: false,
                        style: AppTheme.bodyStyle(
                          colors,
                        ).copyWith(fontSize: 14),
                      ),
                    ],
                  ],
                ),
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
    return Wrap(
      spacing: 6,
      runSpacing: 6,
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
          eyebrow: 'LEDGER',
          title: 'HOLDINGS / EVENTS',
          detail: 'Add, edit, and scan asset records without visual fog.',
          trailing: BrutalistButton(
            key: const Key('add_asset_button'),
            label: 'ADD ASSET',
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
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: KineticText('NO ASSETS YET'),
                ),
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.separated(
            itemCount: assets.length,
            itemBuilder: (context, index) => AssetTile(asset: assets[index]),
            separatorBuilder: (context, index) => const SizedBox(height: 10),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: KineticText(
            'TRANSACTION HISTORY',
            style: AppTheme.displayStyle(
              context.kinetic,
            ).copyWith(fontSize: 34),
          ),
        ),
      ),
    ];

    if (groupedEvents.isEmpty) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: LedgerFrame(
              child: KineticText(
                'ADD HOLDING START OR SOLD DATES TO BUILD THE TIMELINE.',
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
                    _TransactionEventRow(event: entry.value[index]),
                separatorBuilder: (context, index) => const SizedBox(height: 8),
              ),
            ),
          );
      }
    }

    return CustomScrollView(slivers: slivers);
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

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(
            eyebrow: 'ZAKAT',
            title: 'DUE / NISAB',
            detail: 'A hard-edged view of eligible wealth and payment state.',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              _ZakatSettingsBlock(settings: settings),
              const SizedBox(height: 14),
              LedgerFrame(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KineticText(
                      'AMOUNT DUE',
                      style: AppTheme.labelStyle(colors),
                    ),
                    const SizedBox(height: 10),
                    KineticNumber(
                      _formatMoney(result.amountDueUsd),
                      key: const Key('zakat_amount_due'),
                      fontSize: 72,
                      currency: CurrencyConverter.defaultCurrency,
                      color: result.hasPaymentDue
                          ? colors.profit
                          : colors.foreground,
                    ),
                    const SizedBox(height: 14),
                    BrutalistGrid(
                      minTileWidth: 220,
                      children: [
                        MetricBlock(
                          label: 'Eligible wealth',
                          value: _formatMoney(result.eligibleWealthUsd),
                          currency: CurrencyConverter.defaultCurrency,
                        ),
                        MetricBlock(
                          label: 'Nisab',
                          value: result.nisabThresholdUsd == null
                              ? 'AWAITING'
                              : _formatMoney(result.nisabThresholdUsd!),
                          currency: result.nisabThresholdUsd == null
                              ? null
                              : CurrencyConverter.defaultCurrency,
                          detail: result.settings.nisabStandard.label,
                        ),
                      ],
                    ),
                    if (result.message != null) ...[
                      const SizedBox(height: 14),
                      KineticText(
                        result.message!,
                        muted: true,
                        uppercase: false,
                        style: AppTheme.bodyStyle(
                          colors,
                        ).copyWith(fontSize: 14),
                      ),
                    ],
                    if (result.hasPaymentDue) ...[
                      const SizedBox(height: 14),
                      BrutalistButton(
                        key: const Key('mark_zakat_paid'),
                        label: 'MARK AS PAID',
                        tone: BrutalistButtonTone.primary,
                        onPressed: () async {
                          await ref
                              .read(zakatProvider.notifier)
                              .recordPayment(result, DateTime.now());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ZAKAT PAYMENT RECORDED.'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              KineticText(
                'HOLDINGS',
                style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
              ),
              const SizedBox(height: 10),
              if (!result.canCalculate)
                const LedgerFrame(
                  child: KineticText('REFRESH METAL PRICES FROM SYSTEM FIRST.'),
                )
              else if (result.assessments.isEmpty)
                const LedgerFrame(child: KineticText('NO ASSETS ADDED YET.'))
              else
                ...result.assessments.map(_AssessmentTile.new),
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
    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KineticText(
            'CALCULATION SETTINGS',
            style: AppTheme.labelStyle(colors),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ZakatScheduleMode.values
                .map(
                  (mode) => FilterBlock(
                    key: Key('zakat_schedule_${mode.name}'),
                    label: mode.label,
                    selected: settings.scheduleMode == mode,
                    onTap: () => notifier.setScheduleMode(mode),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: NisabStandard.values
                .map(
                  (standard) => FilterBlock(
                    key: Key('nisab_${standard.name}'),
                    label: standard.label,
                    selected: settings.nisabStandard == standard,
                    onTap: () => notifier.setNisabStandard(standard),
                  ),
                )
                .toList(),
          ),
          if (settings.scheduleMode == ZakatScheduleMode.ramadanAnnual) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: KineticText(
                    settings.nextRamadanDueDate == null
                        ? 'NEXT RAMADAN PAYMENT DATE: NOT SELECTED'
                        : 'NEXT RAMADAN PAYMENT DATE: ${_formatDate(settings.nextRamadanDueDate!)}',
                    style: AppTheme.bodyStyle(colors).copyWith(fontSize: 14),
                  ),
                ),
                BrutalistButton(
                  key: const Key('select_ramadan_due_date'),
                  label: 'SELECT',
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate:
                          settings.nextRamadanDueDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) await notifier.setRamadanDueDate(date);
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          KineticText(
            settings.scheduleMode == ZakatScheduleMode.ramadanAnnual
                ? 'On your Ramadan date, all active valued holdings are assessed once.'
                : 'Check monthly; only holdings past one lunar year and not already paid this cycle are assessed.',
            muted: true,
            uppercase: false,
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
          ),
        ],
      ),
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
      slivers: [
        SliverToBoxAdapter(
          child: _PageHeader(
            eyebrow: 'SYSTEM',
            title: 'MODE / PRICES',
            detail: 'Visual state, live metal pricing, and valuation limits.',
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(
            children: [
              LedgerFrame(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KineticText(
                            'THEME MODE',
                            style: AppTheme.labelStyle(colors),
                          ),
                          const SizedBox(height: 8),
                          KineticText(
                            themeMode == ThemeMode.dark
                                ? 'DARK / DEFAULT'
                                : 'LIGHT / INVERTED',
                            style: AppTheme.displayStyle(
                              colors,
                            ).copyWith(fontSize: 34),
                          ),
                        ],
                      ),
                    ),
                    BrutalistButton(
                      key: const Key('theme_mode_toggle'),
                      label: themeMode == ThemeMode.dark
                          ? 'LIGHT MODE'
                          : 'DARK MODE',
                      tone: BrutalistButtonTone.primary,
                      onPressed: () =>
                          ref.read(themeModeProvider.notifier).toggle(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              LedgerFrame(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KineticText(
                      'DISPLAY CURRENCY',
                      style: AppTheme.labelStyle(colors),
                    ),
                    const SizedBox(height: 12),
                    _CurrencySelector(
                      selectedCurrency: displayCurrency,
                      onSelected: (currency) => ref
                          .read(displayCurrencyProvider.notifier)
                          .setCurrency(currency),
                    ),
                    const SizedBox(height: 12),
                    KineticText(
                      'Totals, allocation, and history graphs use this currency.',
                      muted: true,
                      uppercase: false,
                      style: AppTheme.bodyStyle(colors).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              MetalPricesCard(state: metalPriceState),
              const SizedBox(height: 14),
              const LedgerFrame(
                child: KineticText(
                  'USD, AED, AND EUR ARE CONVERTED FOR TOTALS AND DASHBOARD GRAPHS. OTHER CURRENCIES REMAIN RECORDED BUT ARE EXCLUDED UNTIL FX RATES ARE ADDED.',
                  muted: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.detail,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.heroSurface(colors),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Stack(
              children: [
                Positioned(
                  right: -42,
                  top: -52,
                  child: _GlowOrb(
                    size: 132,
                    color: colors.accent.withValues(alpha: 0.13),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KineticText(eyebrow, style: AppTheme.labelStyle(colors)),
                    const SizedBox(height: 10),
                    KineticText(
                      title,
                      style: AppTheme.displayStyle(colors).copyWith(
                        fontSize: (constraints.maxWidth * 0.11).clamp(38, 72),
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    KineticText(
                      detail,
                      muted: true,
                      uppercase: false,
                      style: AppTheme.bodyStyle(colors).copyWith(fontSize: 15),
                    ),
                  ],
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
    return LedgerFrame(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KineticText(
                  'FILTERS',
                  style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
                ),
              ),
              if (filter.isActive)
                BrutalistButton(
                  key: const Key('clear_dashboard_filters'),
                  label: 'RESET',
                  tone: BrutalistButtonTone.primary,
                  onPressed: onClear,
                ),
            ],
          ),
          const SizedBox(height: 16),
          KineticText('ASSET TYPE', style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          const SizedBox(height: 16),
          KineticText('TAG', style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
          const SizedBox(height: 16),
          KineticText('ACTIVITY DATE', style: AppTheme.labelStyle(colors)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                FilterBlock(
                  key: const Key('filter_from_date'),
                  label: 'From',
                  detail: filter.fromDate == null
                      ? 'Any date'
                      : _formatDate(filter.fromDate!),
                  selected: filter.fromDate != null,
                  onTap: onSelectFromDate,
                ),
                FilterBlock(
                  key: const Key('filter_to_date'),
                  label: 'To',
                  detail: filter.toDate == null
                      ? 'Any date'
                      : _formatDate(filter.toDate!),
                  selected: filter.toDate != null,
                  onTap: onSelectToDate,
                ),
              ];
              if (constraints.maxWidth < 460) {
                return Column(
                  children: [
                    buttons.first,
                    const SizedBox(height: 8),
                    buttons.last,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: buttons.first),
                  const SizedBox(width: 8),
                  Expanded(child: buttons.last),
                ],
              );
            },
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: KineticText(
                  'METAL PRICES',
                  style: AppTheme.displayStyle(colors).copyWith(fontSize: 34),
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
                  label: 'REFRESH',
                  tone: BrutalistButtonTone.primary,
                  onPressed: () =>
                      ref.read(metalPriceProvider.notifier).refreshPrices(),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (snapshot == null)
            const KineticText(
              'TAP REFRESH TO LOAD GOLD AND SILVER PRICES.',
              muted: true,
            )
          else
            BrutalistGrid(
              minTileWidth: 210,
              children: [
                MetricBlock(
                  label: 'Gold',
                  value: _formatMoney(snapshot.goldPerGramUsd),
                  currency: CurrencyConverter.defaultCurrency,
                  detail: 'PER GRAM',
                ),
                MetricBlock(
                  label: 'Silver',
                  value: _formatMoney(snapshot.silverPerGramUsd),
                  currency: CurrencyConverter.defaultCurrency,
                  detail: 'PER GRAM',
                ),
                MetricBlock(
                  label: state.isCached ? 'Cached price' : 'Updated',
                  value: _formatTimestamp(snapshot.priceTimestamp),
                  detail: 'LOCAL TIME',
                  valueFontSize: 20,
                  valueMaxLines: 2,
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

class AssetTile extends ConsumerWidget {
  const AssetTile({super.key, required this.asset});

  final Asset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kinetic;
    final isSold = asset.isSold;
    return LedgerFrame(
      padding: const EdgeInsets.all(14),
      background: isSold ? colors.muted : colors.background,
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
                      style: AppTheme.displayStyle(
                        colors,
                      ).copyWith(fontSize: 28),
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
                        color: colors.accent,
                        borderRadius: AppTheme.pillRadius,
                        border: Border.all(
                          color: colors.border,
                          width: AppTheme.thickBorderWidth,
                        ),
                        boxShadow: AppTheme.glowShadow(colors),
                      ),
                      child: KineticText(
                        asset.tag!.label,
                        style: AppTheme.labelStyle(colors).copyWith(
                          color: colors.accentForeground,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              KineticNumber(
                '${_trimNumber(asset.amount)} ${asset.unit}',
                fontSize: 34,
                color: isSold ? colors.mutedForeground : colors.foreground,
                currency: asset.type.isMetal ? null : asset.currency,
              ),
              if (asset.type.isMetal) ...[
                const SizedBox(height: 8),
                KineticText(
                  [
                    '${asset.purity ?? '-'}% PURITY',
                    'PRICES IN ${asset.currency}',
                    if (asset.boughtPrice != null)
                      'BOUGHT ${CurrencyConverter.formatMoney(asset.boughtPrice!, asset.currency)}',
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
                  'SOLD',
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
                label: 'EDIT',
                onPressed: () =>
                    _showAssetFormDialog(context, ref, asset: asset),
              ),
              BrutalistButton(
                label: 'DELETE',
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
    final foreground = isSold
        ? colors.mutedForeground
        : colors.accentForeground;
    final background = isSold ? colors.muted : colors.accent;
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
    this.size = 48,
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
          color: colors.border,
          width: AppTheme.thickBorderWidth,
        ),
        boxShadow: background == colors.accent
            ? AppTheme.glowShadow(colors)
            : null,
      ),
      child: Icon(icon, color: foreground, size: size * 0.48),
    );
  }
}

class _TransactionEventRow extends StatelessWidget {
  const _TransactionEventRow({required this.event});

  final TransactionEvent event;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final isSale = event.type == TransactionEventType.sold;
    final eventBackground = isSale ? colors.loss : colors.profit;
    final eventForeground = eventBackground.computeLuminance() < 0.35
        ? AppTheme.white
        : colors.accentForeground;
    final price = event.price == null
        ? 'NO PRICE'
        : CurrencyConverter.formatMoney(event.price!, event.asset.currency);
    return LedgerFrame(
      padding: const EdgeInsets.all(12),
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
                  style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
                ),
                const SizedBox(height: 5),
                KineticText(price, muted: true),
              ],
            ),
          ),
          KineticText(
            '${_trimNumber(event.asset.amount)} ${event.asset.unit}',
            style: AppTheme.bodyStyle(colors).copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile(this.assessment);

  final ZakatAssetAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final colors = context.kinetic;
    final value = assessment.valueUsd == null
        ? 'NOT VALUED'
        : _formatMoney(assessment.valueUsd!);
    final status = assessment.isIncluded
        ? 'INCLUDED IN AMOUNT DUE'
        : assessment.exclusionReason ?? 'EXCLUDED';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LedgerFrame(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KineticText(
                    assessment.asset.type.label,
                    style: AppTheme.titleStyle(colors).copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 5),
                  KineticText(
                    status,
                    muted: !assessment.isIncluded,
                    style: AppTheme.labelStyle(colors).copyWith(
                      color: assessment.isIncluded
                          ? colors.profit
                          : colors.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            KineticNumber(
              value,
              fontSize: 24,
              currency: assessment.valueUsd == null
                  ? null
                  : CurrencyConverter.defaultCurrency,
            ),
          ],
        ),
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
      'REFRESH METALS IN SYSTEM',
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
