import 'package:blackcard/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows Hold Near Reader on a true-black screen', (tester) async {
    // Stand in for the Android side: no card stored yet.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('blackcard/native'),
      (call) async => null,
    );

    await tester.pumpWidget(const BlackcardApp());
    await tester.pumpAndSettle();

    expect(find.text('Hold Near Reader'), findsOneWidget);
    expect(find.byIcon(Icons.contactless_outlined), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF000000));

    // Without a stored card the placeholder invites a pick.
    expect(find.text('Tap to choose a card image'), findsOneWidget);
  });
}
