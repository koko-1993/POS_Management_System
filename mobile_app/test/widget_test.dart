import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

import "package:shwe_htoo_thit_mobile/main.dart";

void main() {
  testWidgets("boots into mobile app shell", (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {});

    await tester.pumpWidget(const ShweHtooThitMobileApp());
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text("Mobile Sales App"), findsOneWidget);
  });
}
