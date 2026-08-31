import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moniz/theme/app_theme.dart';
import 'package:moniz/widgets/about_page.dart';

void main() {
  test('displayed app version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      contains(
        'version: ${currentAppVersion.version}'
        '+${currentAppVersion.buildNumber}',
      ),
    );
  });

  testWidgets('shows app version, privacy, widgets, and support', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AboutPage(
            versionLoader: () async =>
                const AppVersionInfo(version: '1.2.3', buildNumber: '45'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('About MONIZ'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('Build 45'), findsOneWidget);
    expect(find.text('PRIVACY'), findsOneWidget);
    expect(find.text('Your data stays yours'), findsOneWidget);
    expect(find.text('WIDGETS'), findsOneWidget);
    expect(find.text('Android home-screen widget'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
    expect(find.text('Copy support link'), findsOneWidget);
  });
}
