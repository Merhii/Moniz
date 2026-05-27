# moniz

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Metal Prices

Metal price refresh uses Gold API's public XAU and XAG endpoints. The returned
USD troy-ounce prices are converted to USD per gram for asset valuation and the
latest successful snapshot is cached locally.

Prices refresh once when the app starts and can be refreshed again from
Settings. Gold API can occasionally respond slowly, so requests allow up to
30 seconds before displaying a timeout error.

On native Flutter targets, requests identify themselves as `Moniz/1.0`
because Gold API currently responds to the default Dart client identity with
HTTP 429 even while accepting the same public endpoints from browsers and
terminal clients.

Gold API does not return foreign-exchange rates. USD monetary holdings are
included in totals; AED and EUR remain recordable transaction currencies but
are excluded from USD valuation until a separate FX source is integrated.
