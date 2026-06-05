import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/metal_price_snapshot.dart';

abstract class MetalPriceService {
  Future<MetalPriceSnapshot> fetchLatestPrices();
}

abstract class MetalPriceHistoryService {
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({required int days});
}

class GoldApiPriceService implements MetalPriceService {
  GoldApiPriceService({
    http.Client? client,
    this.rateLimitRetryDelay = const Duration(seconds: 1),
    this.quoteSpacing = const Duration(milliseconds: 500),
    this.requestTimeout = const Duration(seconds: 30),
  }) : _providedClient = client;

  static final _goldUri = Uri.parse('https://api.gold-api.com/price/XAU');
  static final _silverUri = Uri.parse('https://api.gold-api.com/price/XAG');
  static const _troyOunceInGrams = 31.1034768;

  final http.Client? _providedClient;
  final Duration rateLimitRetryDelay;
  final Duration quoteSpacing;
  final Duration requestTimeout;
  late final http.Client _client = _providedClient ?? http.Client();

  @override
  Future<MetalPriceSnapshot> fetchLatestPrices() async {
    // Use sequential requests: some public endpoints temporarily reject bursts.
    final gold = await _fetchQuote(_goldUri);
    await Future<void>.delayed(quoteSpacing);
    final silver = await _fetchQuote(_silverUri);
    final timestamp = gold.updatedAt.isBefore(silver.updatedAt)
        ? gold.updatedAt
        : silver.updatedAt;

    return MetalPriceSnapshot(
      goldPerGramUsd: gold.priceUsdPerOunce / _troyOunceInGrams,
      silverPerGramUsd: silver.priceUsdPerOunce / _troyOunceInGrams,
      priceTimestamp: timestamp,
      fetchedAt: DateTime.now(),
    );
  }

  Future<_GoldApiQuote> _fetchQuote(Uri uri) async {
    var response = await _get(uri);
    if (response.statusCode == 429) {
      await Future<void>.delayed(rateLimitRetryDelay);
      response = await _get(uri);
    }
    if (response.statusCode == 429) {
      throw const MetalPriceException(
        'Gold API is temporarily rejecting requests. '
        'Wait a moment and refresh again.',
      );
    }
    if (response.statusCode != 200) {
      throw MetalPriceException(
        'Gold API request failed (HTTP ${response.statusCode}).',
      );
    }

    late final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const MetalPriceException('Gold API returned an invalid response.');
    }

    if (payload is! Map<String, dynamic>) {
      throw const MetalPriceException('Gold API returned an invalid response.');
    }

    final price = _validPrice(payload['price']);
    final updatedAt = DateTime.tryParse(payload['updatedAt'] as String? ?? '');
    if (price == null || updatedAt == null) {
      throw const MetalPriceException('Gold API returned invalid price data.');
    }
    return _GoldApiQuote(priceUsdPerOunce: price, updatedAt: updatedAt);
  }

  Future<http.Response> _get(Uri uri) async {
    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              // Gold API rejects dart:io's default user agent with HTTP 429.
              'User-Agent': 'Moniz/1.0',
            },
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const MetalPriceException(
        'Gold API did not respond in time. Please try again.',
      );
    } on http.ClientException {
      throw const MetalPriceException(
        'Cannot connect to Gold API from this device.',
      );
    }
    return response;
  }

  double? _validPrice(Object? value) {
    if (value is! num) return null;
    final price = value.toDouble();
    return price.isFinite && price > 0 ? price : null;
  }
}

class YahooFinanceMetalHistoryService implements MetalPriceHistoryService {
  YahooFinanceMetalHistoryService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _providedClient = client;

  static const _goldSymbol = 'GC=F';
  static const _silverSymbol = 'SI=F';
  static const _troyOunceInGrams = 31.1034768;

  final http.Client? _providedClient;
  final Duration requestTimeout;
  late final http.Client _client = _providedClient ?? http.Client();

  @override
  Future<List<MetalPriceSnapshot>> fetchWeeklyAverages({
    required int days,
  }) async {
    final lookbackDays = days + 7;
    final gold = await _fetchDailyCloses(_goldSymbol, lookbackDays);
    final silver = await _fetchDailyCloses(_silverSymbol, lookbackDays);
    final goldWeeks = _weeklyAverages(gold);
    final silverWeeks = _weeklyAverages(silver);
    final weekStarts = goldWeeks.keys.where(silverWeeks.containsKey).toList()
      ..sort();
    final now = DateTime.now();

    return [
      for (final weekStart in weekStarts)
        MetalPriceSnapshot(
          goldPerGramUsd: goldWeeks[weekStart]!.average / _troyOunceInGrams,
          silverPerGramUsd: silverWeeks[weekStart]!.average / _troyOunceInGrams,
          priceTimestamp: _earlierDate(
            goldWeeks[weekStart]!.latestDate,
            silverWeeks[weekStart]!.latestDate,
          ),
          fetchedAt: now,
        ),
    ];
  }

  Future<List<_DailyClose>> _fetchDailyCloses(String symbol, int days) async {
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$symbol',
      {'range': '${days}d', 'interval': '1d'},
    );
    late final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'Moniz/1.0',
            },
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const MetalPriceException(
        'Historical metal prices did not respond in time.',
      );
    } on http.ClientException {
      throw const MetalPriceException(
        'Cannot connect to historical metal prices from this device.',
      );
    }

    if (response.statusCode != 200) {
      throw MetalPriceException(
        'Historical metal price request failed (HTTP ${response.statusCode}).',
      );
    }

    late final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const MetalPriceException(
        'Historical metal prices returned an invalid response.',
      );
    }

    final result = _chartResult(payload);
    final timestamps = result['timestamp'];
    final quote = _firstQuote(result);
    final closes = quote?['close'];
    if (timestamps is! List ||
        closes is! List ||
        timestamps.length != closes.length) {
      throw const MetalPriceException(
        'Historical metal prices returned invalid chart data.',
      );
    }

    final points = <_DailyClose>[];
    for (var index = 0; index < timestamps.length; index++) {
      final timestamp = timestamps[index];
      final close = closes[index];
      if (timestamp is! num || close is! num) continue;
      final price = close.toDouble();
      if (!price.isFinite || price <= 0) continue;
      points.add(
        _DailyClose(
          date: DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt() * 1000,
            isUtc: true,
          ),
          priceUsdPerOunce: price,
        ),
      );
    }
    if (points.isEmpty) {
      throw const MetalPriceException(
        'Historical metal prices did not include valid closes.',
      );
    }
    return points;
  }

  Map<String, dynamic> _chartResult(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      throw const MetalPriceException(
        'Historical metal prices returned an invalid response.',
      );
    }
    final chart = payload['chart'];
    if (chart is! Map<String, dynamic>) {
      throw const MetalPriceException(
        'Historical metal prices returned an invalid response.',
      );
    }
    final result = chart['result'];
    if (result is! List ||
        result.isEmpty ||
        result.first is! Map<String, dynamic>) {
      throw const MetalPriceException(
        'Historical metal prices returned invalid chart data.',
      );
    }
    return result.first as Map<String, dynamic>;
  }

  Map<String, dynamic>? _firstQuote(Map<String, dynamic> result) {
    final indicators = result['indicators'];
    if (indicators is! Map<String, dynamic>) return null;
    final quote = indicators['quote'];
    if (quote is! List ||
        quote.isEmpty ||
        quote.first is! Map<String, dynamic>) {
      return null;
    }
    return quote.first as Map<String, dynamic>;
  }

  Map<DateTime, _WeeklyAverage> _weeklyAverages(List<_DailyClose> closes) {
    final buckets = <DateTime, List<_DailyClose>>{};
    for (final close in closes) {
      buckets.putIfAbsent(_weekStart(close.date), () => []).add(close);
    }
    return {
      for (final entry in buckets.entries)
        entry.key: _WeeklyAverage.from(entry.value),
    };
  }

  DateTime _weekStart(DateTime date) {
    final utcDate = DateTime.utc(date.year, date.month, date.day);
    return utcDate.subtract(Duration(days: utcDate.weekday - DateTime.monday));
  }
}

DateTime _earlierDate(DateTime first, DateTime second) {
  return first.isBefore(second) ? first : second;
}

class _DailyClose {
  const _DailyClose({required this.date, required this.priceUsdPerOunce});

  final DateTime date;
  final double priceUsdPerOunce;
}

class _WeeklyAverage {
  const _WeeklyAverage({required this.average, required this.latestDate});

  final double average;
  final DateTime latestDate;

  factory _WeeklyAverage.from(List<_DailyClose> closes) {
    final sum = closes.fold<double>(
      0,
      (total, close) => total + close.priceUsdPerOunce,
    );
    final latestDate = closes
        .map((close) => close.date)
        .reduce((latest, date) => date.isAfter(latest) ? date : latest);
    return _WeeklyAverage(average: sum / closes.length, latestDate: latestDate);
  }
}

class _GoldApiQuote {
  const _GoldApiQuote({
    required this.priceUsdPerOunce,
    required this.updatedAt,
  });

  final double priceUsdPerOunce;
  final DateTime updatedAt;
}

class MetalPriceException implements Exception {
  const MetalPriceException(this.message);

  final String message;

  @override
  String toString() => message;
}
