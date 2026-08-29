// Moniz agent driver: launches the app and exposes a line-oriented REPL for
// driving it (tap / type / read text / screenshot) over Flutter Driver.
//
//   dart run .claude/skills/run-moniz/driver.dart [-d macos] [--headed]
//
// Reads commands on stdin, one per line. Prints `OK ...` / `ERR ...` per
// command, and `READY` once the app is up. Pipe a heredoc for a batch run, or
// wrap it in tmux for an interactive session. See SKILL.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

const _entry = '.claude/skills/run-moniz/driver_entry.dart';
const _shotDir = 'build/moniz-shots';

/// Every command is bounded so a wedged app surfaces as ERR, not a hang.
const _cmdTimeout = Duration(seconds: 20);

Process? _app;
late FlutterDriver _driver;

Future<void> main(List<String> args) async {
  final device = _flag(args, '-d') ?? _flag(args, '--device') ?? 'macos';
  final attach = _flag(args, '--vm-service');

  String uri;
  if (attach != null) {
    uri = attach;
    stderr.writeln('[driver] attaching to $uri');
  } else {
    uri = await _launch(device);
  }

  stderr.writeln('[driver] connecting Flutter Driver...');
  _driver = await FlutterDriver.connect(
    dartVmServiceUrl: uri,
    // The app animates continuously (kinetic UI), so never let the driver
    // block waiting for the frame queue to drain.
    printCommunication: false,
  );
  await Directory(_shotDir).create(recursive: true);
  stderr.writeln('[driver] ${await _focus()}');

  print('READY $uri');
  await _repl();
}

/// Spawns `flutter run` and waits for it to advertise a VM Service URI.
Future<String> _launch(String device) async {
  stderr.writeln('[driver] flutter run -d $device -t $_entry');
  final app = _app = await Process.start('flutter', [
    'run',
    '-d',
    device,
    '-t',
    _entry,
    '--debug',
  ], mode: ProcessStartMode.normal);

  final found = Completer<String>();
  // Matches: "A Dart VM Service on macOS is available at: http://127.0.0.1:1/ab=/"
  final re = RegExp(r'(http://127\.0\.0\.1:\d+/[^\s]*)');
  app.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
    line,
  ) {
    stderr.writeln('[app] $line');
    if (found.isCompleted) return;
    if (!line.contains('Dart VM Service')) return;
    final m = re.firstMatch(line);
    if (m != null) found.complete(m.group(1)!);
  });
  app.stderr.transform(utf8.decoder).listen((c) => stderr.write('[app!] $c'));
  unawaited(
    app.exitCode.then((c) {
      if (!found.isCompleted) {
        found.completeError(StateError('flutter run exited early (code $c)'));
      }
    }),
  );

  // A cold macOS/iOS build is genuinely slow the first time.
  return found.future.timeout(
    const Duration(minutes: 10),
    onTimeout: () => throw StateError('no VM Service URI after 10 minutes'),
  );
}

Future<void> _repl() async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line == 'quit' || line == 'exit') break;
    try {
      final out = await _run(line).timeout(_cmdTimeout);
      print('OK ${out ?? ''}'.trimRight());
    } on TimeoutException {
      print('ERR timeout after ${_cmdTimeout.inSeconds}s: $line');
    } catch (e) {
      print('ERR ${e.toString().split('\n').first}');
    }
    await stdout.flush();
  }
  await _shutdown();
}

Future<String?> _run(String line) async {
  final sp = line.indexOf(' ');
  final cmd = sp == -1 ? line : line.substring(0, sp);
  final rest = sp == -1 ? '' : line.substring(sp + 1).trim();

  switch (cmd) {
    case 'screenshot':
      final name = rest.isEmpty ? 'shot' : rest;
      final path = name.contains('/') ? name : '$_shotDir/$name.png';
      await _focus();
      final bytes = await _driver.screenshot();
      await File(path).writeAsBytes(bytes);
      return '$path (${bytes.length} bytes)';

    case 'tap':
      // Unsynchronized: the kinetic UI never reaches a quiescent frame state.
      await _driver.runUnsynchronized(() => _driver.tap(_finder(rest)));
      return rest;

    case 'waitfor':
      await _driver.runUnsynchronized(
        () => _driver.waitFor(_finder(rest), timeout: _cmdTimeout),
      );
      return rest;

    case 'waitgone':
      await _driver.runUnsynchronized(
        () => _driver.waitForAbsent(_finder(rest), timeout: _cmdTimeout),
      );
      return rest;

    case 'exists':
      try {
        await _driver.runUnsynchronized(
          () => _driver.waitFor(_finder(rest), timeout: const Duration(seconds: 3)),
        );
        return 'yes';
      } catch (_) {
        return 'no';
      }

    case 'text':
      return _driver.runUnsynchronized(() => _driver.getText(_finder(rest)));

    case 'enter':
      await _driver.enterText(rest);
      return rest;

    case 'scroll':
      // scroll <finder> <dx> <dy>
      final parts = rest.split(RegExp(r'\s+'));
      final dy = double.parse(parts.removeLast());
      final dx = double.parse(parts.removeLast());
      await _driver.runUnsynchronized(
        () => _driver.scroll(
          _finder(parts.join(' ')),
          dx,
          dy,
          const Duration(milliseconds: 400),
        ),
      );
      return 'dx=$dx dy=$dy';

    case 'rendertree':
      // The dump is multi-megabyte; never return it inline.
      final t = (await _driver.getRenderTree()).tree ?? '';
      final path = rest.isEmpty ? '$_shotDir/rendertree.txt' : rest;
      await File(path).writeAsString(t);
      return '$path (${t.length} chars) - grep it';

    case 'strings':
      // Every string currently in the render tree, deduped. This is the
      // practical way to discover what is on screen before tapping.
      final tree = (await _driver.getRenderTree()).tree ?? '';
      final seen = <String>{};
      for (final m in RegExp(r'"([^"\n]{1,60})"').allMatches(tree)) {
        final v = m.group(1)!.trim();
        if (v.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(v)) seen.add(v);
      }
      final list = seen.toList()..sort();
      return '\n${list.join('\n')}';

    case 'focus':
      return _focus();

    // No `diagnostics` command on purpose: getWidgetDiagnostics() hangs
    // against this app even inside runUnsynchronized. Use `strings`.

    case 'reload':
      return _appKey('r');

    case 'restart':
      return _appKey('R');

    default:
      throw ArgumentError('unknown command: $cmd');
  }
}

/// Sends a hot-reload/restart keystroke to the `flutter run` we spawned.
Future<String> _appKey(String k) async {
  final app = _app;
  if (app == null) throw StateError('attached mode: no `flutter run` to signal');
  app.stdin.write(k);
  await app.stdin.flush();
  await Future<void>.delayed(const Duration(seconds: 3));
  return k == 'r' ? 'hot reload' : 'hot restart';
}

/// Brings the macOS app window to the front.
///
/// Non-negotiable on macOS: an occluded/background Flutter window stops
/// producing frames, which makes every `tap` time out and every screenshot
/// byte-identical to the last one rendered.
Future<String> _focus() async {
  final r = await Process.run('osascript', [
    '-e',
    'tell application "System Events" to set frontmost of '
        '(first process whose name is "moniz") to true',
  ]);
  return r.exitCode == 0 ? 'foregrounded' : 'focus failed: ${r.stderr}';
}

/// `key:save_asset` | `text:Zakat` | `tooltip:Notifications` | `type:AppBar`
SerializableFinder _finder(String spec) {
  final i = spec.indexOf(':');
  if (i == -1) {
    throw ArgumentError('finder must be key:/text:/tooltip:/type: — got "$spec"');
  }
  final kind = spec.substring(0, i);
  final value = spec.substring(i + 1);
  switch (kind) {
    case 'key':
      return find.byValueKey(value);
    case 'text':
      return find.text(value);
    case 'tooltip':
      return find.byTooltip(value);
    case 'type':
      return find.byType(value);
    default:
      throw ArgumentError('unknown finder kind: $kind');
  }
}

Future<void> _shutdown() async {
  try {
    await _driver.close();
  } catch (_) {}
  final app = _app;
  if (app != null) {
    try {
      app.stdin.write('q');
      await app.stdin.flush();
      await app.exitCode.timeout(const Duration(seconds: 10));
    } catch (_) {
      app.kill(ProcessSignal.sigterm);
    }
  }
  exit(0);
}

String? _flag(List<String> a, String name) {
  final i = a.indexOf(name);
  return (i == -1 || i + 1 >= a.length) ? null : a[i + 1];
}
