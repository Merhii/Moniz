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

  static double? usdRateFor(String? currency, {MetalPriceSnapshot? prices}) {
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

  static String formatMoney(double value, String currency, {int decimals = 2}) {
    final normalized = normalize(currency);
    final amount = formatNumber(value, decimals: decimals);
    if (normalized == 'USD') return '\$$amount';
    return '$normalized $amount';
  }

  static String formatNumber(double value, {int? decimals}) {
    final amount = decimals == null
        ? _trimNumber(value)
        : value.toStringAsFixed(decimals);
    return _withThousandsSeparators(amount);
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

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString();
  }

  static String _withThousandsSeparators(String amount) {
    final sign = amount.startsWith('-') ? '-' : '';
    final unsignedAmount = sign.isEmpty ? amount : amount.substring(1);
    final decimalIndex = unsignedAmount.indexOf('.');
    final whole = decimalIndex == -1
        ? unsignedAmount
        : unsignedAmount.substring(0, decimalIndex);
    final decimal = decimalIndex == -1
        ? ''
        : unsignedAmount.substring(decimalIndex);
    final groupedWhole = StringBuffer(sign);

    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) {
        groupedWhole.write(',');
      }
      groupedWhole.write(whole[index]);
    }

    return groupedWhole.toString() + decimal;
  }
}
