import 'package:blackcard/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// S26 Ultra: 1440 × 3120 px panel at ~3.5 dpr, portrait.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 3120);
  tester.view.devicePixelRatio = 3.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows Hold Near Reader on a true-black screen', (tester) async {
    usePhoneScreen(tester);
    // Stand in for the Android side: no card stored yet.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('blackcard/native'),
      (call) async => null,
    );

    await tester.pumpWidget(const BlackcardApp());
    await tester.pumpAndSettle();

    expect(find.text('Hold Near Reader'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF000000));

    // Without a stored card the placeholder invites a pick.
    expect(find.text('Tap to choose a card image'), findsOneWidget);
  });

  testWidgets('shown event runs the flick and reports NFC off', (tester) async {
    usePhoneScreen(tester);
    const channel = MethodChannel('blackcard/native');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'nfcEnabled') return false;
      return null;
    });

    await tester.pumpWidget(const BlackcardApp());
    await tester.pump();

    // Simulate the Activity coming to the foreground.
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('shown')),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('NFC is off'), findsOneWidget);
    expect(find.text('Hold Near Reader'), findsNothing);

    // Hiding resets the session; no timers should be left running.
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(const MethodCall('hidden')),
      (_) {},
    );
    await tester.pump();
  });
}
