import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/shared/app_notification.dart';

void main() {
  testWidgets('progress stays visible until completion, then dismisses normally', (tester) async {
    late AppNotificationUpdate update;
    await tester.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(
      body: AppNotificationHost(child: Builder(builder: (context) {
        update = appNotificationUpdater(context);
        return const SizedBox.expand();
      })),
    )));
    update('Importing expenses and monthly limits…', progress: 0);
    await tester.pumpAndSettle();
    expect(find.text('0%'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    update('Importing expenses and monthly limits…', progress: .5);
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .5);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('50%'), findsOneWidget);
    update('Imported 10 records.', progress: 1);
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(AppNotificationCard), findsNothing);
  });

  testWidgets('errors replace progress and retain the existing notice design', (tester) async {
    late AppNotificationUpdate update;
    await tester.pumpWidget(MaterialApp(theme: appTheme(), home: Scaffold(
      body: AppNotificationHost(child: Builder(builder: (context) {
        update = appNotificationUpdater(context);
        return const SizedBox.expand();
      })),
    )));
    update('Importing', progress: .4);
    await tester.pumpAndSettle();
    update('Could not import data.', isError: true);
    await tester.pumpAndSettle();
    expect(find.text('Could not import data.'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.widget<AppNotificationCard>(find.byType(AppNotificationCard)).isError, isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(AppNotificationCard), findsNothing);
  });
}
