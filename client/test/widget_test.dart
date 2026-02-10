import 'package:flutter_test/flutter_test.dart';
import 'package:intelli_note/app/app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IntelliNoteApp());

    // Verify that the app builds
    expect(find.byType(IntelliNoteApp), findsOneWidget);
  });
}
