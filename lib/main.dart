import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/asset.dart';
import 'models/metal_price_snapshot.dart';
import 'models/portfolio_snapshot.dart';
import 'models/zakat_settings.dart';
import 'providers/asset_provider.dart';
import 'providers/metal_price_provider.dart';
import 'providers/portfolio_snapshot_provider.dart';
import 'providers/zakat_provider.dart';
import 'services/dashboard_filter.dart';
import 'services/portfolio_analytics.dart';
import 'services/transaction_history_service.dart';
import 'services/wealth_calculator.dart';
import 'services/zakat_engine.dart';
import 'widgets/asset_form_dialog.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/portfolio_insights_card.dart';
import 'widgets/transaction_history_screen.dart';
import 'widgets/zakat_breakdown_screen.dart';

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
  runApp(const ProviderScope(child: MonizApp()));
}

class MonizApp extends StatelessWidget {
  const MonizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moniz',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFD4AF37),
          secondary: const Color(0xFF22C55E),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
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
    final titles = ['Dashboard', 'Holdings', 'Settings'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Moniz - ${titles[_selectedPage]}'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: _selectedPage == 1
          ? FloatingActionButton(
              key: const Key('add_asset_fab'),
              onPressed: () => _showAssetFormDialog(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: IndexedStack(
        index: _selectedPage,
        children: [
          DashboardPage(onOpenSettings: () => _setPage(2)),
          const HoldingsPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedPage,
        onDestinationSelected: _setPage,
        destinations: const [
          NavigationDestination(
            key: Key('dashboard_nav'),
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            key: Key('holdings_nav'),
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Holdings',
          ),
          NavigationDestination(
            key: Key('settings_nav'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _setPage(int index) {
    setState(() => _selectedPage = index);
  }
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

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
    final zakatSettings = ref.watch(zakatProvider);
    final zakatResult = ZakatEngine.calculate(
      assets: assets,
      prices: metalPriceState.snapshot,
      settings: zakatSettings,
      payments: ref.read(zakatProvider.notifier).payments,
      today: DateTime.now(),
    );
    final totals = WealthCalculator.calculateUsd(
      filteredAssets,
      metalPriceState.snapshot,
    );
    final analytics = PortfolioAnalytics.calculate(
      filteredAssets,
      metalPriceState.snapshot,
    );
    final completeAnalytics = PortfolioAnalytics.calculate(
      assets,
      metalPriceState.snapshot,
    );
    final profitLoss = TransactionHistoryService.realizedProfitLossFor(
      filteredAssets,
    );
    final snapshots = ref.watch(portfolioSnapshotProvider);
    final summaryNote = [
      if (totals.hasUnpricedMetals)
        'Refresh metal prices in Settings to include metal holdings.',
      if (totals.hasUnsupportedCurrencies)
        'Non-USD cash holdings are excluded until FX conversion is added.',
    ].join(' ');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Track, compare, and filter your wealth.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        SummaryCard(
          wealthLabel: _filter.isActive ? 'Filtered Wealth' : 'Total Wealth',
          totalWealth: totals.totalUsd,
          zakat: zakatResult.amountDueUsd,
          note: summaryNote.isEmpty ? null : summaryNote,
          onViewZakat: widget.onOpenSettings,
        ),
        const SizedBox(height: 16),
        DashboardFiltersCard(
          assets: assets,
          filter: _filter,
          onTypeSelected: _selectType,
          onTagSelected: _selectTag,
          onSelectFromDate: () => _selectDate(isStart: true),
          onSelectToDate: () => _selectDate(isStart: false),
          onClear: () => setState(() => _filter = const DashboardFilter()),
        ),
        const SizedBox(height: 16),
        Text(
          _filter.isActive
              ? 'Showing ${filteredAssets.length} of ${assets.length} holdings'
              : 'Showing all ${assets.length} holdings',
          key: const Key('dashboard_filter_result'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        PortfolioInsightsCard(
          analytics: analytics,
          snapshotAnalytics: completeAnalytics,
          isFiltered: _filter.isActive,
          onOpenHistory: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const TransactionHistoryScreen(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PortfolioTrendCard(snapshots: snapshots),
        const SizedBox(height: 16),
        ProfitLossCard(results: profitLoss),
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

class HoldingsPage extends ConsumerWidget {
  const HoldingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Holdings',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              key: const Key('add_asset_button'),
              onPressed: () => _showAssetFormDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Add Asset'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Add, edit, and organize your asset records.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 18),
        if (assets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('No assets yet', style: TextStyle(fontSize: 18)),
            ),
          )
        else
          ...assets.map((asset) => AssetTile(asset: asset)),
      ],
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(zakatProvider);
    final metalPriceState = ref.watch(metalPriceProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('Zakat Settings & Payments'),
            subtitle: Text(
              '${settings.scheduleMode.label} | ${settings.nisabStandard.label}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ZakatBreakdownScreen(),
              ),
            ),
            key: const Key('view_zakat_breakdown'),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.currency_exchange),
            title: Text('Currencies'),
            subtitle: Text(
              'USD is valued in totals. AED and EUR remain available for recorded transactions.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        MetalPricesCard(state: metalPriceState),
      ],
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
    final visibleTypes = [
      AssetType.cash,
      AssetType.gold,
      AssetType.silver,
      if (assets.any((asset) => asset.type == AssetType.bankSavings))
        AssetType.bankSavings,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFF1A1D24),
        border: Border.all(color: const Color(0xFF252A34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: Color(0xFFD4AF37),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Narrow your dashboard view',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (filter.isActive)
                FilledButton.tonalIcon(
                  key: const Key('clear_dashboard_filters'),
                  onPressed: onClear,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reset'),
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _FilterSectionLabel(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Asset Type',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterPill(
                key: const Key('filter_type_all'),
                label: const Text('All'),
                selected: filter.type == null,
                onTap: () => onTypeSelected(null),
              ),
              ...visibleTypes.map(
                (type) => _FilterPill(
                  key: Key('filter_type_${type.name}'),
                  label: Text(type.label),
                  icon: _assetIcon(type),
                  selected: filter.type == type,
                  onTap: () => onTypeSelected(type),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _FilterSectionLabel(icon: Icons.sell_outlined, label: 'Tag'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterPill(
                key: const Key('filter_tag_all'),
                label: const Text('All'),
                selected: filter.tag == null,
                onTap: () => onTagSelected(null),
              ),
              ...AssetTag.values.map(
                (tag) => _FilterPill(
                  key: Key('filter_tag_${tag.name}'),
                  label: Text(tag.label),
                  selected: filter.tag == tag,
                  onTap: () => onTagSelected(tag),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _FilterSectionLabel(
            icon: Icons.calendar_today_outlined,
            label: 'Activity Date',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FilterDateButton(
                  key: const Key('filter_from_date'),
                  label: 'From',
                  date: filter.fromDate,
                  onPressed: onSelectFromDate,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterDateButton(
                  key: const Key('filter_to_date'),
                  label: 'To',
                  date: filter.toDate,
                  onPressed: onSelectToDate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDateButton extends StatelessWidget {
  const _FilterDateButton({
    super.key,
    required this.label,
    required this.date,
    required this.onPressed,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF20242C),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date == null ? 'Any date' : _formatDate(date!),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.calendar_month_outlined,
                color: Color(0xFFD4AF37),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Widget label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? const Color(0xFF16181D) : Colors.white;
    return Material(
      color: selected ? const Color(0xFFD4AF37) : const Color(0xFF20242C),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: IconTheme(
            data: IconThemeData(color: foreground, size: 15),
            child: DefaultTextStyle(
              style: TextStyle(color: foreground, fontWeight: FontWeight.w500),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 7),
                      child: Icon(Icons.check_rounded),
                    )
                  else if (icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Icon(icon),
                    ),
                  label,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _assetIcon(AssetType type) {
  switch (type) {
    case AssetType.cash:
      return Icons.payments_outlined;
    case AssetType.bankSavings:
      return Icons.account_balance_outlined;
    case AssetType.gold:
      return Icons.circle_outlined;
    case AssetType.silver:
      return Icons.circle_outlined;
  }
}

String _formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

Future<void> _showAssetFormDialog(
  BuildContext context,
  WidgetRef ref, {
  Asset? asset,
}) async {
  final result = await showDialog<Asset>(
    context: context,
    builder: (_) => AssetFormDialog(asset: asset),
  );
  if (result == null) return;

  final notifier = ref.read(assetProvider.notifier);
  if (asset == null) {
    await notifier.addAsset(result);
  } else {
    await notifier.updateAsset(result);
  }
}

class SummaryCard extends StatelessWidget {
  final String wealthLabel;
  final double totalWealth;
  final double zakat;
  final String? note;
  final VoidCallback onViewZakat;

  const SummaryCard({
    super.key,
    this.wealthLabel = 'Total Wealth',
    required this.totalWealth,
    required this.zakat,
    required this.onViewZakat,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1A1D24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wealthLabel, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            '\$${totalWealth.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Zakat Due (all holdings)',
                style: TextStyle(color: Colors.grey),
              ),
              TextButton(
                key: const Key('open_settings_from_dashboard'),
                onPressed: onViewZakat,
                child: const Text('Settings'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\$${zakat.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 28,
              color: Color(0xFF22C55E),
              fontWeight: FontWeight.bold,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 16),
            Text(note!, style: const TextStyle(color: Colors.grey)),
          ],
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
    final snapshot = state.snapshot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1A1D24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Metal Prices',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (state.isRefreshing)
                const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  key: const Key('refresh_metal_prices'),
                  tooltip: 'Refresh prices',
                  onPressed: () =>
                      ref.read(metalPriceProvider.notifier).refreshPrices(),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          if (snapshot == null)
            const Text(
              'Tap refresh to load gold and silver prices.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            _PriceRow(label: 'Gold', price: snapshot.goldPerGramUsd),
            const SizedBox(height: 8),
            _PriceRow(label: 'Silver', price: snapshot.silverPerGramUsd),
            const SizedBox(height: 10),
            Text(
              '${state.isCached ? 'Cached price' : 'Updated'}: '
              '${_formatTimestamp(snapshot.priceTimestamp)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              state.errorMessage!,
              key: const Key('metal_price_error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final localDate = date.toLocal();
    final month = localDate.month.toString().padLeft(2, '0');
    final day = localDate.day.toString().padLeft(2, '0');
    final hour = localDate.hour.toString().padLeft(2, '0');
    final minute = localDate.minute.toString().padLeft(2, '0');
    return '${localDate.year}-$month-$day $hour:$minute';
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.price});

  final String label;
  final double price;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          '\$${price.toStringAsFixed(2)} / gram',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class AssetTile extends ConsumerWidget {
  final Asset asset;

  const AssetTile({super.key, required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF1A1D24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      asset.type.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (asset.tag != null)
                      Chip(
                        key: Key('asset_tag_chip_${asset.id}'),
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(_assetTagIcon(asset.tag!), size: 15),
                        label: Text(asset.tag!.label),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${asset.amount} ${asset.unit}',
                  style: const TextStyle(color: Colors.grey),
                ),
                if (asset.type.isMetal) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${asset.purity ?? '-'}% purity | Prices in ${asset.currency}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
                if (asset.note != null && asset.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(asset.note!, style: const TextStyle(color: Colors.grey)),
                ],
                if (asset.isSold) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Sold',
                    style: TextStyle(color: Color(0xFF22C55E)),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit asset',
            onPressed: () => _showAssetFormDialog(context, ref, asset: asset),
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Delete asset',
            onPressed: () {
              ref.read(assetProvider.notifier).removeAsset(asset.id);
            },
            icon: const Icon(Icons.delete),
          ),
        ],
      ),
    );
  }
}

IconData _assetTagIcon(AssetTag tag) {
  switch (tag) {
    case AssetTag.freelance:
      return Icons.laptop_mac_outlined;
    case AssetTag.emergency:
      return Icons.warning_amber_outlined;
    case AssetTag.gift:
      return Icons.card_giftcard;
    case AssetTag.salary:
      return Icons.payments_outlined;
    case AssetTag.businessProfit:
      return Icons.trending_up;
  }
}
