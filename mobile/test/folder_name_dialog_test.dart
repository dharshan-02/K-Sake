import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepsake/src/widgets/folder_name_dialog.dart';

void main() {
  testWidgets('cancelling folder creation closes without a framework error', (
    tester,
  ) async {
    Future<String?>? dialogResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  dialogResult = showDialog<String>(
                    context: context,
                    builder: (_) => const FolderNameDialog(
                      title: 'Create folder',
                      submitLabel: 'Create',
                      fieldLabel: 'Folder name',
                      hintText: 'For example, Receipts',
                    ),
                  );
                },
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await dialogResult, isNull);
    expect(tester.takeException(), isNull);
    expect(find.text('Create folder'), findsNothing);
  });

  testWidgets('folder dialog returns the entered name', (tester) async {
    Future<String?>? dialogResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  dialogResult = showDialog<String>(
                    context: context,
                    builder: (_) => const FolderNameDialog(
                      title: 'Create folder',
                      submitLabel: 'Create',
                      fieldLabel: 'Folder name',
                      hintText: 'For example, Receipts',
                    ),
                  );
                },
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' Receipts ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(await dialogResult, 'Receipts');
    expect(tester.takeException(), isNull);
  });
}
