import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/core/categories.dart';
import 'package:kharchio/core/preferences.dart';
import 'package:kharchio/core/theme.dart';
import 'package:kharchio/features/expenses/expense_draft_card.dart';
import 'package:kharchio/features/expenses/payment_review_host.dart';
import 'package:kharchio/features/expenses/pending_payment_reviews_screen.dart';
import 'package:kharchio/services/ai/expense_extractor.dart';
import 'package:kharchio/services/ai/online_ai_client.dart';
import 'package:kharchio/services/ai/online_ai_settings.dart';
import 'package:kharchio/services/notifications/pending_payment_reviews.dart';
import 'package:kharchio/shared/app_dropdown.dart';
import 'package:kharchio/shared/widgets.dart';

class _TestCategories extends CategoriesStore {
  @override
  List<ExpenseCategory> build() => defaultCategories;
}

class _TestOnlineKeys extends OnlineAiKeys {
  @override
  Future<String?> read(OnlineAiProvider provider) async => 'test-key';

  @override
  Future<OnlineAiModels?> models(OnlineAiProvider provider) async =>
      const OnlineAiModels(speech: 'speech', expense: 'expense');
}

class _PendingExtraction extends OnlineAiClient {
  _PendingExtraction(super.provider, super.key);

  final result = Completer<List<ExtractedExpense>>();

  @override
  Future<List<ExtractedExpense>> extract({
    required String text,
    required List<String> categories,
    required String currency,
    required OnlineAiModels models,
    String language = 'auto',
    bool paymentNotification = false,
  }) => result.future;
}

void main() {
  testWidgets(
    'rows scroll inside the card and clear all requires confirmation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final messenger = tester.binding.defaultBinaryMessenger;
      final queue = [
        for (var i = 0; i < 24; i++)
          {
            'id': 'review-$i',
            'text': 'You paid Rs.299 to Store $i via UPI',
            'postedAt': 1794139200000,
          },
      ];
      messenger.setMockMethodCallHandler(paymentNotificationChannel, (
        call,
      ) async {
        if (call.method == 'pending') return jsonEncode(queue);
        if (call.method == 'clearPending') {
          final count = queue.length;
          queue.clear();
          return count;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          paymentNotificationChannel,
          null,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(),
            home: const PendingPaymentReviewsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final card = find.byType(SurfaceCard);
      final clear = find.text('Clear all reviews');
      final cardBounds = tester.getRect(card);
      final clearBounds = tester.getRect(clear);
      expect(find.text('Store 0').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -450));
      await tester.pumpAndSettle();
      expect(find.text('Store 0').hitTestable(), findsNothing);
      expect(tester.getRect(card), cardBounds);
      expect(tester.getRect(clear), clearBounds);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(SurfaceCard),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(queue, hasLength(24));
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(queue, isEmpty);
      expect(find.text('No pending expense reviews.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'a cold-start tap opens only its expense and the card trash dismisses it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final messenger = tester.binding.defaultBinaryMessenger;
      var consumed = false;
      final outcomes = <Object?>[];
      messenger.setMockMethodCallHandler(paymentNotificationChannel, (
        call,
      ) async {
        switch (call.method) {
          case 'consumeReviewTap':
            if (consumed) return null;
            consumed = true;
            return 'selected';
          case 'pending':
            return jsonEncode([
              {
                'id': 'other',
                'text': 'You paid Rs.400 to OTHER SHOP via UPI',
                'postedAt': 1794139200000,
              },
              {
                'id': 'selected',
                'text': 'You paid Rs.299 to BLINKIT via UPI',
                'postedAt': 1794139200000,
              },
            ]);
          case 'resolve':
            outcomes.add(call.arguments);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          paymentNotificationChannel,
          null,
        ),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      final extraction = _PendingExtraction(
        OnlineAiProvider.claude,
        'test-key',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoriesProvider.overrideWith(_TestCategories.new),
            onlineAiKeysProvider.overrideWithValue(_TestOnlineKeys()),
            onlineAiClientFactoryProvider.overrideWithValue(
              (_, _) => extraction,
            ),
            initialPreferencesProvider.overrideWithValue(
              const AppPreferences(
                aiMode: AiMode.online,
                onlineAiProvider: OnlineAiProvider.claude,
              ),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(),
            navigatorKey: navigatorKey,
            builder: (_, child) => PaymentReviewHost(
              navigatorKey: navigatorKey,
              openReviews: () => fail('A single alert should open its draft'),
              child: child!,
            ),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review detected expense'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('The AI button sends')).dx,
        tester.getTopLeft(find.text('Review detected expense')).dx,
      );
      expect(find.text('299.00'), findsOneWidget);
      expect(find.text('BLINKIT'), findsOneWidget);
      expect(find.text('OTHER SHOP'), findsNothing);
      expect(find.byTooltip('Extract with online AI'), findsOneWidget);
      expect(find.byType(ExpenseDraftCard), findsOneWidget);
      expect(find.byType(AppDropdown<String>), findsOneWidget);
      expect(find.byType(AppDropdown<AppCurrency>), findsNothing);
      expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
      expect(
        tester.getCenter(find.byTooltip('Extract with online AI')).dx,
        lessThan(tester.getCenter(find.text('Review later')).dx),
      );
      expect(
        tester.getCenter(find.text('Review later')).dy,
        closeTo(tester.getCenter(find.text('Add expense')).dy, 1),
      );
      expect(
        tester
            .getTopRight(
              find
                  .ancestor(
                    of: find.byTooltip('Extract with online AI'),
                    matching: find.byType(Row),
                  )
                  .first,
            )
            .dx,
        closeTo(tester.getTopRight(find.byType(ExpenseDraftCard)).dx, 1),
      );
      expect(find.byTooltip('More review actions'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Add expense')).dx -
            tester.getTopRight(find.byIcon(Icons.add_rounded)).dx,
        closeTo(4, .1),
      );
      await tester.tap(find.byTooltip('Extract with online AI'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(ShaderMask), findsOneWidget);
      final shimmeringFields = find.descendant(
        of: find.byType(ExpenseDraftCard),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.foregroundPainter != null &&
              (widget.child is TextFormField ||
                  widget.child is AppDropdown<String> ||
                  widget.child is Focus),
        ),
      );
      expect(shimmeringFields, findsNWidgets(4));
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.enabled),
        everyElement(false),
      );
      expect(
        tester
            .widget<AppDropdown<String>>(find.byType(AppDropdown<String>))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
        isNull,
      );
      extraction.result.complete([
        const ExtractedExpense('BLINKIT', 'Paid via UPI', 'Groceries', 299),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(ShaderMask), findsNothing);
      expect(shimmeringFields, findsNothing);
      expect(find.text('AI extracted the payment details.'), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.enabled),
        everyElement(true),
      );
      await tester.tap(find.text('Refund'));
      await tester.pumpAndSettle();
      expect(find.text('Add refund'), findsOneWidget);
      expect(find.text('299.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove refund card'));
      await tester.pumpAndSettle();
      expect(find.text('Review detected expense'), findsNothing);
      expect(outcomes, [
        {'id': 'selected', 'outcome': 'dismissed'},
      ]);
    },
  );

  testWidgets(
    'group alert opens the list, where drafts can be reviewed or dismissed',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final messenger = tester.binding.defaultBinaryMessenger;
      var tap = paymentReviewGroupTap;
      final queue = {
        'coffee': 'Spent Rs.145 on HDFC Bank Card 9027 at COFFEE SHOP. Not you? Call 18002586161',
        'groceries': 'You paid Rs.299 to BLINKIT via UPI',
      };
      messenger.setMockMethodCallHandler(paymentNotificationChannel, (
        call,
      ) async {
        switch (call.method) {
          case 'consumeReviewTap':
            final target = tap;
            tap = '';
            return target.isEmpty ? null : target;
          case 'pending':
            return jsonEncode([
              for (final entry in queue.entries)
                {
                  'id': entry.key,
                  'text': entry.value,
                  'postedAt': 1794139200000,
                },
            ]);
          case 'resolve':
            final arguments = call.arguments as Map;
            expect(arguments['outcome'], 'dismissed');
            expect(queue.remove(arguments['id']), isNotNull);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          paymentNotificationChannel,
          null,
        ),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [categoriesProvider.overrideWith(_TestCategories.new)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: appTheme(),
            builder: (_, child) => PaymentReviewHost(
              navigatorKey: navigatorKey,
              openReviews: () => navigatorKey.currentState!.push<void>(
                MaterialPageRoute(
                  builder: (_) => const PendingPaymentReviewsScreen(),
                ),
              ),
              child: child!,
            ),
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = find.text('Pending expense reviews');
      expect(heading, findsOneWidget);
      expect(find.text('Review detected expense'), findsNothing);
      final arrow = find.descendant(
        of: find.byType(BackButton),
        matching: find.byType(Icon),
      );
      expect(
        tester.getTopLeft(heading).dx - tester.getTopRight(arrow).dx,
        closeTo(10, .1),
      );
      expect(find.text('₹ 145.00'), findsOneWidget);
      expect(find.textContaining('9027'), findsNothing);
      expect(find.textContaining('18002586161'), findsNothing);
      await tester.drag(find.text('COFFEE SHOP'), const Offset(-110, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('COFFEE SHOP'), findsNothing);
      expect(find.text('Review dismissed.'), findsOneWidget);
      await tester.tap(find.text('BLINKIT'));
      await tester.pumpAndSettle();
      expect(find.text('299.00'), findsOneWidget);
      expect(find.byTooltip('Extract with on-device AI'), findsOneWidget);
      await tester.tap(find.text('Review later'));
      await tester.pumpAndSettle();
      expect(find.text('Review detected expense'), findsNothing);
      expect(queue.keys, ['groceries']);
      await tester.drag(find.text('BLINKIT'), const Offset(-110, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dismiss').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('No pending expense reviews.'), findsOneWidget);
      expect(
        find.textContaining('Detected payments appear here'),
        findsOneWidget,
      );
    },
  );
}
