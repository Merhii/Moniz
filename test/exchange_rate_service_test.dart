import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:moniz/models/metal_price_snapshot.dart';
import 'package:moniz/services/currency_converter.dart';
import 'package:moniz/services/exchange_rate_service.dart';

void main() {
  group('parsing', () {
    test('quotes are inverted into USD per unit', () {
      // The endpoint says how many euros a dollar buys; the app works the
      // other way round.
      final rates = OpenExchangeRateService.parseUsdRates({
        'EUR': 0.92,
        'AED': 3.6725,
        'CAD': 1.36,
      });

      expect(rates['EUR'], closeTo(1 / 0.92, 1e-9));
      expect(rates['AED'], closeTo(1 / 3.6725, 1e-9));
      expect(rates['CAD'], closeTo(1 / 1.36, 1e-9));
    });

    test('currencies the app does not offer are ignored', () {
      final rates = OpenExchangeRateService.parseUsdRates({
        'EUR': 0.92,
        'JPY': 155.0,
      });

      expect(rates.keys, ['EUR']);
    });

    test('a nonsense rate is left out rather than defaulted', () {
      // A wrong rate is worse than a missing one: missing makes the app say
      // the total is incomplete, wrong makes it lie.
      final rates = OpenExchangeRateService.parseUsdRates({
        'EUR': 0,
        'AED': -1,
        'CAD': 'many',
      });

      expect(rates, isEmpty);
    });

    test('a missing rate is simply absent', () {
      final rates = OpenExchangeRateService.parseUsdRates({'EUR': 0.92});

      expect(rates.containsKey('CAD'), isFalse);
    });
  });

  group('fetching', () {
    OpenExchangeRateService serviceReturning(
      String body, {
      int status = 200,
    }) {
      return OpenExchangeRateService(
        client: MockClient((_) async => http.Response(body, status)),
      );
    }

    test('reads the rates out of a successful response', () async {
      final service = serviceReturning(
        jsonEncode({
          'result': 'success',
          'base_code': 'USD',
          'rates': {'EUR': 0.92, 'AED': 3.6725, 'CAD': 1.36},
        }),
      );

      final rates = await service.fetchUsdRates();
      expect(rates.keys.toSet(), {'EUR', 'AED', 'CAD'});
    });

    test('a failed request throws rather than returning nothing', () async {
      // Silently returning an empty map would look like "no rates exist",
      // which is a different thing from "could not ask".
      final service = serviceReturning('{}', status: 503);

      expect(
        service.fetchUsdRates(),
        throwsA(isA<ExchangeRateException>()),
      );
    });

    test('an invalid body throws', () async {
      final service = serviceReturning('not json');

      expect(
        service.fetchUsdRates(),
        throwsA(isA<ExchangeRateException>()),
      );
    });

    test('a response with no rates throws', () async {
      final service = serviceReturning(jsonEncode({'result': 'success'}));

      expect(
        service.fetchUsdRates(),
        throwsA(isA<ExchangeRateException>()),
      );
    });
  });

  group('conversion through a snapshot', () {
    MetalPriceSnapshot snapshot({
      double? eur,
      double? cad,
      double? aed,
    }) {
      return MetalPriceSnapshot(
        goldPerGramUsd: 100,
        silverPerGramUsd: 1,
        priceTimestamp: DateTime.utc(2026, 9, 7),
        fetchedAt: DateTime.utc(2026, 9, 7),
        eurToUsd: eur,
        aedToUsd: aed,
        cadToUsd: cad,
      );
    }

    test('a euro amount converts once a rate exists', () {
      final usd = CurrencyConverter.convert(
        100,
        from: 'EUR',
        to: 'USD',
        prices: snapshot(eur: 1 / 0.92),
      );

      expect(usd, closeTo(108.70, 0.01));
    });

    test('Canadian dollars convert too', () {
      final usd = CurrencyConverter.convert(
        100,
        from: 'CAD',
        to: 'USD',
        prices: snapshot(cad: 1 / 1.36),
      );

      expect(usd, closeTo(73.53, 0.01));
    });

    test('without a rate the conversion refuses rather than guesses', () {
      expect(
        CurrencyConverter.convert(
          100,
          from: 'EUR',
          to: 'USD',
          prices: snapshot(),
        ),
        isNull,
      );
    });

    test('the dirham peg still works with no snapshot at all', () {
      // Offline, on a fresh install, AED must not become unusable.
      expect(
        CurrencyConverter.convert(367.25, from: 'AED', to: 'USD'),
        closeTo(100, 0.01),
      );
    });

    test('a fetched dirham rate is preferred over the constant', () {
      final usd = CurrencyConverter.convert(
        100,
        from: 'AED',
        to: 'USD',
        prices: snapshot(aed: 0.5),
      );

      expect(usd, 50);
    });

    test('every offered currency has a mark of its own', () {
      // Two currencies sharing a mark in a picker that offers both is how
      // somebody records the wrong one.
      final symbols = [
        for (final currency in CurrencyConverter.recordableCurrencies)
          CurrencyConverter.symbolFor(currency),
      ];

      expect(symbols.toSet(), hasLength(symbols.length));
      expect(CurrencyConverter.symbolFor('CAD'), r'C$');
      expect(CurrencyConverter.symbolFor('USD'), r'$');
    });

    test('all four currencies are offered', () {
      expect(CurrencyConverter.supportedCurrencies, [
        'USD',
        'AED',
        'EUR',
        'CAD',
      ]);
      expect(CurrencyConverter.recordableCurrencies, [
        'USD',
        'AED',
        'EUR',
        'CAD',
      ]);
    });
  });
}
