import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/src/data/local_vault.dart';
import 'package:keepsake/src/screens/auth_screen.dart';

void main() {
  testWidgets(
    'sign-in and registration scroll at narrow width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: AuthScreen(vault: LocalVault(), onAuthSuccess: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Create account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Where should your vault live?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
