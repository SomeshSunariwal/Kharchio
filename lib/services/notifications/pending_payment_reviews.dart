import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'payment_notification_parser.dart';

const paymentNotificationChannel = MethodChannel(
  'com.somesh.kharchio/payment_notifications',
);
bool get supportsPaymentNotifications =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class PendingPaymentReview {
  const PendingPaymentReview(this.id, this.text, this.draft);

  final String id, text;
  final PaymentNotificationDraft draft;

  String get description => redactPaymentText(text);
}

final pendingPaymentReviewsProvider =
    FutureProvider.autoDispose<List<PendingPaymentReview>>(
      (_) => loadPendingPaymentReviews(),
    );

Future<List<PendingPaymentReview>> loadPendingPaymentReviews() async {
  final raw = await paymentNotificationChannel.invokeMethod<String>('pending');
  final items = (jsonDecode(raw ?? '[]') as List).whereType<Map>();
  final reviews = <PendingPaymentReview>[];
  for (final item in items) {
    final id = item['id'];
    final text = item['text'];
    final postedAt = item['postedAt'];
    if (id is! String || text is! String || postedAt is! int) continue;
    final draft = parsePaymentNotification(
      text,
      postedAt: DateTime.fromMillisecondsSinceEpoch(postedAt),
    );
    if (draft != null) reviews.add(PendingPaymentReview(id, text, draft));
  }
  return reviews;
}

Future<void> resolvePaymentReview(String id, String outcome) =>
    paymentNotificationChannel.invokeMethod<void>('resolve', {
      'id': id,
      'outcome': outcome,
    });

Future<int> clearPendingPaymentReviews() async =>
    await paymentNotificationChannel.invokeMethod<int>('clearPending') ?? 0;
