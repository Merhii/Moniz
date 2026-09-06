import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the app was asked to do when it was opened.
enum LaunchAction { addEntry }

/// Reads the action the home-screen widget attached to the launch intent.
///
/// Consuming rather than reading: the action describes one tap, so returning
/// it twice would reopen capture on the next resume.
abstract class LaunchActionReader {
  Future<LaunchAction?> consume();
}

class PlatformLaunchActionReader implements LaunchActionReader {
  const PlatformLaunchActionReader();

  static const _channel = MethodChannel('moniz/launch_action');

  @override
  Future<LaunchAction?> consume() async {
    // Only Android has the widget; everywhere else the channel is absent and
    // asking for it would throw on every resume.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final action = await _channel.invokeMethod<String>('consumeLaunchAction');
      return switch (action) {
        'add_entry' => LaunchAction.addEntry,
        _ => null,
      };
    } on MissingPluginException {
      // No host implementation, which is the normal case under tests.
      return null;
    } on PlatformException {
      // A widget tap is a convenience. Losing it must not cost the app.
      return null;
    }
  }
}
