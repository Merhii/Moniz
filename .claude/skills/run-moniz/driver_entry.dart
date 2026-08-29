// Driver-enabled entrypoint for the Moniz app.
//
// Identical to `lib/main.dart` except that it registers the Flutter Driver
// extension before booting, which is what lets
// `.claude/skills/run-moniz/driver.dart` reach into the running app.
//
// Launch with:
//   flutter run -d macos -t .claude/skills/run-moniz/driver_entry.dart
//
// Never point a release build at this file.
import 'package:flutter_driver/driver_extension.dart';
import 'package:moniz/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
