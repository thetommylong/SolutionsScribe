import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solutionscribe/app.dart';

void main() {
  testWidgets('App renders upload dropzone on startup',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SolutionsScribeApp()));

    expect(
      find.text('Drag and drop a file, or click to choose'),
      findsOneWidget,
    );
  });
}