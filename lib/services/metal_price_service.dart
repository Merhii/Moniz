import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/metal_price_snapshot.dart';

abstract class MetalPriceService {
  Future<MetalPriceSnapshot> fetchLatestPrices();
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
