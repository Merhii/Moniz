import '../models/metal_price_snapshot.dart';

class CurrencyConverter {
  CurrencyConverter._();

  static const defaultCurrency = 'USD';
  static const supportedCurrencies = ['USD', 'AED', 'EUR'];

  static const _defaultUsdRates = <String, double>{
    'USD': 1,
    'AED': 1 / 3.6725,
    'EUR': 1.08,
  };

  static String normalize(String? currency) {
    final normalized = (currency ?? defaultCurrency).trim().toUpperCase();
    return normalized.isEmpty ? defaultCurrency : normalized;
  }

  static bool isSupported(String? currency) {
    return supportedCurrencies.contains(normalize(currency));
  }

  static double? usdRateFor(
    String? currency, {
    MetalPriceSnapshot? prices,
  }) {
    final normalized = normalize(currency);
    return prices?.usdRateFor(normalized) ?? _defaultUsdRates[normalized];
  }

  static double? convert(
    double amount, {
    required String from,
    required String to,
    MetalPriceSnapshot? prices,
  }) {
    final fromRate = usdRateFor(from, prices: prices);
    final toRate = usdRateFor(to, prices: prices);
    if (fromRate == null || toRate == null || toRate == 0) return null;
    return amount * fromRate / toRate;
  }

  static double? convertFromUsd(
    double amount,
    String to, {
    MetalPriceSnapshot? prices,
  }) {
    return convert(amount, from: defaultCurrency, to: to, prices: prices);
  }

  static String formatMoney(
    double value,
    String currency, {
    int decimals = 2,
  }) {
    final normalized = normalize(currency);
    final amount = value.toStringAsFixed(decimals);
    if (normalized == 'USD') return '\$$amount';
    return '$normalized $amount';
  }

  static String compactMoney(double value, String currency) {
    final normalized = normalize(currency);
    final prefix = normalized == 'USD' ? r'$' : '$normalized ';
    if (value >= 1000000) {
      return '$prefix${(value / 1000000).toStringAsFixed(1)}m';
    }
    if (value >= 1000) {
      return '$prefix${(value / 1000).toStringAsFixed(1)}k';
    }
    return '$prefix${value.toStringAsFixed(0)}';
  }
}
