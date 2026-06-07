import 'package:flutter_test/flutter_test.dart';
import 'package:chats/main.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const ChatApp());
    await tester.pump();
    expect(find.byType(ChatApp), findsOneWidget);
  });
}
