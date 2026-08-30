# Moniz

A personal wealth and zakat tracker. Record what you hold in cash, gold and
silver; Moniz prices the metals against the live market, totals your wealth,
and works out whether zakat is due against the gold or silver nisab.

Everything stays on the device. The only network calls fetch gold and silver
prices, and they carry none of your holding details.

## Running it

```sh
flutter pub get
flutter run          # add -d macos, -d chrome, or a device id
flutter test
```

## How the numbers are worked out

**Wealth.** Metals are valued as `weight x purity x live price per gram`.
Monetary holdings are converted into the display currency. Sold holdings are
excluded from the total.

**Zakat.** A holding is assessed once it has been held for one lunar year
(354 days) from its start date, or on your chosen Ramadan date if you use that
schedule. Zakat is 2.5% of the assessed total, and only when that total reaches
the nisab - 85 g of gold, or 612.36 g of silver, at the current price.

A holding saved without a start date counts towards your wealth but cannot be
assessed for zakat, since there is no date to measure the year from. The Zakat
screen reports how many holdings are in that state.

## Metal prices

Refresh uses Gold API's public XAU and XAG endpoints. The returned USD
troy-ounce prices are converted to USD per gram, and the latest successful
snapshot is cached locally.

Prices refresh once at startup and can be refreshed again from Settings. Gold
API can respond slowly, so requests allow up to 30 seconds before reporting a
timeout.

On native targets, requests identify themselves as `Moniz/1.0`: Gold API
answers the default Dart client identity with HTTP 429 while accepting the same
public endpoints from browsers and terminal clients.

## Currencies

Gold API returns no foreign-exchange rates, so Moniz only values a currency it
has a rate it can stand behind:

- **USD** - the base currency.
- **AED** - converted at the central-bank peg of 3.6725 per USD, held since
  1997. A constant is accurate here rather than a guess.
- **Everything else, including EUR** - recordable on a holding, kept in the
  ledger, but left out of totals, charts and zakat until a live FX source is
  added. The dashboard says when a holding is being excluded for this reason.

Totals and charts can be displayed in USD or AED.

## Storage and app lock

Holdings live in Hive boxes encrypted at rest, with the key held in the
platform keychain or keystore. App lock adds a 4-digit PIN (and biometrics
where available) on launch and on resume; the PIN is stored as a PBKDF2-SHA256
verifier, and repeated wrong entries are throttled.
