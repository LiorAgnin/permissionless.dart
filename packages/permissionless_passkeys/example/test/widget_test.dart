// Smoke test for Passkeys Example app.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:permissionless_passkeys_example/main.dart';

void main() {
  testWidgets('App loads home screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: PasskeysExampleApp(),
      ),
    );

    // Verify the home screen loads with the expected title
    expect(find.text('Passkeys Smart Account'), findsOneWidget);
  });
}
