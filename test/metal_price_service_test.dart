import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moniz/services/metal_price_service.dart';

void main() {
  test(
    'fetches gold and silver ounce prices and stores USD per gram',
    () async {
      var requestsInFlight = 0;
      var maxRequestsInFlight = 0;
      final client = MockClient((request) async {
        requestsInFlight += 1;
        if (requestsInFlight > maxRequestsInFlight) {
          maxRequestsInFlight = requestsInFlight;
        }
        expect(request.url.host, 'api.gold-api.com');
        expect(request.headers['User-Agent'], 'Moniz/1.0');
        final isGold = request.url.path == '/price/XAU';
        expect(
          request.url.path == '/price/XAU' || request.url.path == '/price/XAG',
          isTrue,
        );
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final response = http.Response(
          jsonEncode({
            'currency': 'USD',
            'price': isGold ? 4452.799805 : 74.761002,
            'updatedAt': isGold
                ? '2026-05-27T18:02:19Z'
                : '2026-05-27T18:01:19Z',
          }),
          200,
        );
        requestsInFlight -= 1;
        return response;
      });
      final service = GoldApiPriceService(
        client: client,
        quoteSpacing: Duration.zero,
      );

      final snapshot = await service.fetchLatestPrices();

      expect(snapshot.goldPerGramUsd, closeTo(4452.799805 / 31.1034768, 0.001));
      expect(snapshot.silverPerGramUsd, closeTo(74.761002 / 31.1034768, 0.001));
      expect(snapshot.eurToUsd, isNull);
      expect(snapshot.aedToUsd, isNull);
      expect(snapshot.priceTimestamp, DateTime.utc(2026, 5, 27, 18, 1, 19));
      expect(maxRequestsInFlight, 1);
    },
  );

  test('rejects missing or invalid metal prices', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'price': -1, 'updatedAt': '2026-05-27T18:02:19Z'}),
        200,
      ),
    );
    final service = GoldApiPriceService(
      client: client,
      quoteSpacing: Duration.zero,
    );

    expect(service.fetchLatestPrices, throwsA(isA<MetalPriceException>()));
  });

  test('surfaces Gold API failed responses', () async {
    final client = MockClient((_) async => http.Response('Unavailable', 503));
    final service = GoldApiPriceService(
      client: client,
      quoteSpacing: Duration.zero,
    );

    expect(
      service.fetchLatestPrices,
      throwsA(
        isA<MetalPriceException>().having(
          (error) => error.message,
          'message',
          'Gold API request failed (HTTP 503).',
        ),
      ),
    );
  });

  test('retries a temporary rate limit response once', () async {
    var goldAttempts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/price/XAU') {
        goldAttempts += 1;
        if (goldAttempts == 1) return http.Response('Limited', 429);
      }
      return http.Response(
        jsonEncode({'price': 100, 'updatedAt': '2026-05-27T18:02:19Z'}),
        200,
      );
    });
    final service = GoldApiPriceService(
      client: client,
      rateLimitRetryDelay: Duration.zero,
      quoteSpacing: Duration.zero,
    );

    final snapshot = await service.fetchLatestPrices();

    expect(goldAttempts, 2);
    expect(snapshot.goldPerGramUsd, closeTo(100 / 31.1034768, 0.001));
  });

  test('explains persistent rate limiting', () async {
    final client = MockClient((_) async => http.Response('Limited', 429));
    final service = GoldApiPriceService(
      client: client,
      rateLimitRetryDelay: Duration.zero,
      quoteSpacing: Duration.zero,
    );

    expect(
      service.fetchLatestPrices,
      throwsA(
        isA<MetalPriceException>().having(
          (error) => error.message,
          'message',
          'Gold API is temporarily rejecting requests. '
              'Wait a moment and refresh again.',
        ),
      ),
    );
  });

  test('fetches weekly gold and silver averages from daily history', () async {
    final timestamps = [
      _epochSeconds(DateTime.utc(2026, 6, 1)),
      _epochSeconds(DateTime.utc(2026, 6, 2)),
      _epochSeconds(DateTime.utc(2026, 6, 3)),
      _epochSeconds(DateTime.utc(2026, 6, 4)),
      _epochSeconds(DateTime.utc(2026, 6, 5)),
    ];
    final client = MockClient((request) async {
      expect(request.url.host, 'query1.finance.yahoo.com');
      expect(request.url.queryParameters['range'], '37d');
      expect(request.url.queryParameters['interval'], '1d');
      expect(request.headers['User-Agent'], 'Moniz/1.0');
      final symbol = request.url.pathSegments.last;
      return http.Response(
        jsonEncode(
          _chartPayload(
            timestamps: timestamps,
            closes: symbol == 'GC=F'
                ? const [3100, 3110, 3120, 3130, 3140]
                : const [31, 32, 33, 34, 35],
          ),
        ),
        200,
      );
    });
    final service = YahooFinanceMetalHistoryService(client: client);

    final history = await service.fetchWeeklyAverages(days: 30);

    expect(history, hasLength(1));
    expect(history.single.goldPerGramUsd, closeTo(3120 / 31.1034768, 0.001));
    expect(history.single.silverPerGramUsd, closeTo(33 / 31.1034768, 0.001));
    expect(history.single.priceTimestamp, DateTime.utc(2026, 6, 5));
  });
}

int _epochSeconds(DateTime date) => date.millisecondsSinceEpoch ~/ 1000;

Map<String, Object?> _chartPayload({
  required List<int> timestamps,
  required List<num> closes,
}) {
  return {
    'chart': {
      'result': [
        {
          'timestamp': timestamps,
          'indicators': {
            'quote': [
              {'close': closes},
            ],
          },
        },
      ],
      'error': null,
    },
  };
}
