import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellinote/app/app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IntelliNoteApp());

    // Verify that the app builds
    expect(find.byType(IntelliNoteApp), findsOneWidget);
  });
}