import 'dart:convert';

import 'package:http/http.dart' as http;

class ExchangeRateException implements Exception {
  const ExchangeRateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// USD per unit, for the currencies the app can express totals in.
abstract class ExchangeRateService {
  Future<Map<String, double>> fetchUsdRates();
}

/// Reads rates from a free endpoint that needs no key, so nothing about the
/// owner is sent anywhere to price their own money.
class OpenExchangeRateService implements ExchangeRateService {
  OpenExchangeRateService({http.Client? client, this.requestTimeout = const Duration(seconds: 20)})
    : _providedClient = client;

  static final _uri = Uri.parse('https://open.er-api.com/v6/latest/USD');

  /// Floating currencies the app offers. AED is pegged and has a constant
  /// fallback, so it is fetched but never depended on.
  static const wanted = ['EUR', 'AED', 'CAD'];

  final http.Client? _providedClient;
  final Duration requestTimeout;
  late final http.Client _client = _providedClient ?? http.Client();

  @override
  Future<Map<String, double>> fetchUsdRates() async {
    final http.Response response;
    try {
      response = await _client.get(_uri).timeout(requestTimeout);
    } catch (error) {
      throw ExchangeRateException('Could not reach the exchange rate service.');
    }
    if (response.statusCode != 200) {
      throw ExchangeRateException(
        'Exchange rate request failed (HTTP ${response.statusCode}).',
      );
    }

    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const ExchangeRateException(
        'The exchange rate service returned an invalid response.',
      );
    }
    if (payload is! Map<String, dynamic>) {
      throw const ExchangeRateException(
        'The exchange rate service returned an invalid response.',
      );
    }

    final rates = payload['rates'];
    if (rates is! Map) {
      throw const ExchangeRateException(
        'The exchange rate service returned no rates.',
      );
    }

    return parseUsdRates(rates);
  }

  /// The endpoint quotes units per USD; the app works in USD per unit, which
  /// is what [MetalPriceSnapshot.usdRateFor] returns.
  ///
  /// A rate that is missing, unparseable or non-positive is left out rather
  /// than defaulted. A wrong rate is worse than an absent one: an absent one
  /// makes the app say the total is incomplete, a wrong one makes it lie.
  static Map<String, double> parseUsdRates(Map<Object?, Object?> rates) {
    final parsed = <String, double>{};
    for (final code in wanted) {
      final value = rates[code];
      final perUsd = value is num ? value.toDouble() : null;
      if (perUsd == null || !perUsd.isFinite || perUsd <= 0) continue;
      parsed[code] = 1 / perUsd;
    }
    return Map.unmodifiable(parsed);
  }
}
