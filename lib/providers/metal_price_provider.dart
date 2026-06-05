import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../models/metal_price_snapshot.dart';
import '../services/metal_price_service.dart';

class MetalPriceState {
  const MetalPriceState({
    this.snapshot,
    this.historicalPrices = const [],
    this.isRefreshing = false,
    this.isCached = false,
    this.errorMessage,
  });

  final MetalPriceSnapshot? snapshot;
  final List<MetalPriceSnapshot> historicalPrices;
  final bool isRefreshing;
  final bool isCached;
  final String? errorMessage;

  MetalPriceState copyWith({
    MetalPriceSnapshot? snapshot,
    List<MetalPriceSnapshot>? historicalPrices,
    bool? isRefreshing,
    bool? isCached,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MetalPriceState(
      snapshot: snapshot ?? this.snapshot,
      historicalPrices: historicalPrices ?? this.historicalPrices,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isCached: isCached ?? this.isCached,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class MetalPriceNotifier extends StateNotifier<MetalPriceState> {
  MetalPriceNotifier({
    required Box<MetalPriceSnapshot> priceBox,
    required MetalPriceService priceService,
    required MetalPriceHistoryService historyService,
  }) : _priceBox = priceBox,
       _priceService = priceService,
       _historyService = historyService,
       super(_initialState(priceBox));

  static const _cacheKey = 'latest_usd_gram_prices';
  static const _historyDays = 90;

  final Box<MetalPriceSnapshot> _priceBox;
  final MetalPriceService _priceService;
  final MetalPriceHistoryService _historyService;

  static MetalPriceState _initialState(Box<MetalPriceSnapshot> priceBox) {
    final cachedSnapshot = priceBox.get(_cacheKey);
    return cachedSnapshot == null
        ? const MetalPriceState()
        : MetalPriceState(snapshot: cachedSnapshot, isCached: true);
  }

  Future<void> refreshPrices() async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      final snapshot = await _priceService.fetchLatestPrices();
      await _priceBox.put(_cacheKey, snapshot);
      state = state.copyWith(
        snapshot: snapshot,
        isRefreshing: false,
        isCached: false,
      );
      await _refreshHistoricalPrices();
    } on MetalPriceException catch (error) {
      debugPrint('Metal price refresh failed: ${error.message}');
      state = state.copyWith(
        isRefreshing: false,
        isCached: state.snapshot != null,
        errorMessage: error.message,
      );
    } catch (error) {
      debugPrint(
        'Metal price refresh failed unexpectedly: ${error.runtimeType}: $error',
      );
      state = state.copyWith(
        isRefreshing: false,
        isCached: state.snapshot != null,
        errorMessage: 'Unable to refresh prices right now.',
      );
    }
  }

  Future<void> _refreshHistoricalPrices() async {
    try {
      final historicalPrices = await _historyService.fetchWeeklyAverages(
        days: _historyDays,
      );
      state = state.copyWith(historicalPrices: historicalPrices);
    } on MetalPriceException catch (error) {
      debugPrint('Historical metal price refresh failed: ${error.message}');
    } catch (error) {
      debugPrint(
        'Historical metal price refresh failed unexpectedly: '
        '${error.runtimeType}: $error',
      );
    }
  }
}

final metalPriceServiceProvider = Provider<MetalPriceService>(
  (ref) => GoldApiPriceService(),
);

final metalPriceHistoryServiceProvider = Provider<MetalPriceHistoryService>(
  (ref) => YahooFinanceMetalHistoryService(),
);

final metalPriceProvider =
    StateNotifierProvider<MetalPriceNotifier, MetalPriceState>(
      (ref) => MetalPriceNotifier(
        priceBox: Hive.box<MetalPriceSnapshot>('metalPrices'),
        priceService: ref.read(metalPriceServiceProvider),
        historyService: ref.read(metalPriceHistoryServiceProvider),
      ),
    );
