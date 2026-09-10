import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khinsider/app.dart';
import 'package:khinsider/core/theme.dart';

void main() {
  testWidgets('App boots to search screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: KhinsiderApp()));
    await tester.pump();

    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search game soundtracks…'), findsOneWidget);
  });

  test('Dark theme is generated', () {
    expect(AppTheme.dark().brightness, Brightness.dark);
  });
}
