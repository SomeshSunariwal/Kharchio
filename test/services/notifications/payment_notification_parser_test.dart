import 'package:flutter_test/flutter_test.dart';
import 'package:kharchio/services/notifications/payment_notification_parser.dart';

void main() {
  test('extracts amount, merchant, category, and time from HDFC spend', () {
    final draft = parsePaymentNotification(
      'Spent Rs.105 On HDFC Bank Card 9027 At ZEPTO MARKETPLACE PRIV On 2026-11-08:18:54:37.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 9027 to 7308080808',
    );
    expect(draft?.amount, 105);
    expect(draft?.merchant, 'ZEPTO MARKETPLACE PRIV');
    expect(draft?.category, 'Groceries');
    expect(draft?.date, DateTime(2026, 11, 8, 18, 54, 37));
  });

  test('ignores unrelated and malformed notifications', () {
    expect(parsePaymentNotification('Rs.105 credited to your account'), isNull);
    expect(
      parsePaymentNotification(
        'Spent Rs.105 On HDFC Bank Card 9027 At Shop On 2026-13-08:18:54:37',
      ),
      isNull,
    );
  });

  test('recognizes debit and UPI payments from other providers', () {
    final postedAt = DateTime(2026, 11, 8, 12, 30);
    final bank = parsePaymentNotification(
      'INR 1,250.50 debited from your account to AMAZON PAY. Avl Bal INR 5000',
      postedAt: postedAt,
    );
    expect(bank?.amount, 1250.50);
    expect(bank?.merchant, 'AMAZON PAY');
    expect(bank?.category, 'Others');
    expect(bank?.date, postedAt);
    final upi = parsePaymentNotification(
      'You paid ₹299 to BLINKIT via UPI. Transaction successful',
      postedAt: postedAt,
    );
    expect(upi?.amount, 299);
    expect(upi?.merchant, 'BLINKIT');
    expect(upi?.category, 'Groceries');
  });

  test('rejects credits, refunds and failed payments', () {
    expect(
      parsePaymentNotification('INR 500 credited to your account'),
      isNull,
    );
    expect(parsePaymentNotification('Refund of Rs.500 received'), isNull);
    expect(parsePaymentNotification('Payment of Rs.500 failed'), isNull);
  });

  test('detects USD and removes card identifiers and security instructions', () {
    const message =
        r'USD 24.90 charged to card ending 9027 at COFFEE SHOP. Not you? Call 18002586161';
    final draft = parsePaymentNotification(message);
    expect(draft?.currency, 'USD');
    expect(draft?.amount, 24.9);
    expect(draft?.merchant, 'COFFEE SHOP');
    final redacted = redactPaymentText(message);
    expect(redacted, contains('USD 24.90'));
    expect(redacted, isNot(contains('9027')));
    expect(redacted, isNot(contains('18002586161')));
  });
}
