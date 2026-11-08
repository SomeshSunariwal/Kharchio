class PaymentNotificationDraft {
  final double amount;
  final String merchant;
  final String category;
  final DateTime date;
  final String currency;
  const PaymentNotificationDraft(
    this.amount,
    this.merchant,
    this.category,
    this.date, {
    this.currency = 'INR',
  });
}

final _amount = RegExp(
  r'(₹|\$|\b(?:INR|USD|Rs\.?))\s*(\d[\d,]*(?:\.\d{1,2})?)(?![\d,.]\d|\d)',
  caseSensitive: false,
);
final _expense = RegExp(
  r'\b(?:spent|debited|paid|payment (?:of|done|successful)|sent|transferred|purchase|charged)\b',
  caseSensitive: false,
);
final _incoming = RegExp(
  r'\b(?:credited|received|refund(?:ed)?|reversal|reversed|cashback|failed|declined|unsuccessful|pending|otp|one.time password|collect request|payment request|request(?:ed)? (?:for|to|money)|pay now)\b',
  caseSensitive: false,
);
final _destination = RegExp(
  r'\b(?:at|to|towards|for|merchant)\s+(?!(?:card|account|a/c)\b)(.+?)(?=\s+\b(?:on|from|via|using|ref|reference|txn|transaction|upi|avl|available|balance)\b|[.!?]|$)',
  caseSensitive: false,
);
final _timestamp = RegExp(
  r'\b(\d{4})-(\d{2})-(\d{2})[: T](\d{2}):(\d{2}):(\d{2})\b',
);

/// Conservative bank/UPI parser. Unclear notifications stay out of the queue.
PaymentNotificationDraft? parsePaymentNotification(
  String text, {
  DateTime? postedAt,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (!_expense.hasMatch(normalized) || _incoming.hasMatch(normalized)) {
    return null;
  }
  final amountMatch = _amount.firstMatch(normalized);
  if (amountMatch == null) return null;
  final value = double.tryParse(amountMatch[2]!.replaceAll(',', ''));
  if (value == null || !value.isFinite || value <= 0 || value > 9999999999.99) {
    return null;
  }
  final marker = amountMatch[1]!.toUpperCase();
  final currency = marker == 'USD' || marker == r'$' ? 'USD' : 'INR';

  final timestamp = _timestamp.firstMatch(normalized);
  var date = postedAt ?? DateTime.now();
  if (timestamp != null) {
    final parts = [for (var i = 1; i <= 6; i++) int.parse(timestamp[i]!)];
    date = DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2] ||
        date.hour != parts[3] ||
        date.minute != parts[4] ||
        date.second != parts[5]) {
      return null;
    }
  }

  final tail = redactPaymentText(normalized.substring(amountMatch.end));
  final extracted = _destination.firstMatch(tail)?[1]?.trim();
  final merchant = extracted == null || extracted.isEmpty
      ? 'Card/UPI payment'
      : extracted;
  final upper = merchant.toUpperCase();
  final category =
      ['ZEPTO', 'BLINKIT', 'INSTAMART', 'BIGBASKET'].any(upper.contains)
      ? 'Groceries'
      : 'Others';
  return PaymentNotificationDraft(
    value,
    merchant,
    category,
    date,
    currency: currency,
  );
}

final _securityFooter = RegExp(
  r'(?:not you\s*\?|if (?:not you|unauthorized)|to block\b|block\+reissue\b|report fraud\b).*',
  caseSensitive: false,
  dotAll: true,
);
final _identifier = RegExp(
  r'\b((?:card|a/c|account|acct|ref(?:erence)?|txn(?: id)?|rrn|utr|ending)(?:\s+(?:ending|no\.?|number|id|in|with))?\s*[:#-]?\s*)[xX*•-]*\d{3,}(?![\d.:])',
  caseSensitive: false,
);
final _contact = RegExp(
  r'https?://\S+|[\w.+-]+@[\w.-]+|(?:\+\d{1,3}[ -]?)?\d{7,}',
  caseSensitive: false,
);

String redactPaymentText(String value) => value
    .replaceFirst(_securityFooter, '')
    .replaceAllMapped(_identifier, (match) => '${match[1]}[redacted]')
    .replaceAll(_contact, '[redacted]')
    .trim();
