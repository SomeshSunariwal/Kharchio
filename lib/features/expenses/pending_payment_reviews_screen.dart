import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../services/notifications/pending_payment_reviews.dart';
import '../../shared/destructive_confirmation.dart';
import '../../shared/swipe_delete_expense.dart';
import '../../shared/widgets.dart';
import 'payment_review_host.dart';

class PendingPaymentReviewsScreen extends ConsumerStatefulWidget {
  const PendingPaymentReviewsScreen({super.key});

  @override
  ConsumerState<PendingPaymentReviewsScreen> createState() =>
      _PendingPaymentReviewsScreenState();
}

class _PendingPaymentReviewsScreenState
    extends ConsumerState<PendingPaymentReviewsScreen> {
  bool _clearing = false;

  Future<void> _clearAll() async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Clear all pending reviews?',
      message:
          'This dismisses every pending review. Saved transactions are kept.',
      confirmLabel: 'Clear all',
    );
    if (!mounted || !confirmed) return;
    setState(() => _clearing = true);
    try {
      await clearPendingPaymentReviews();
      if (!mounted) return;
      ref.invalidate(pendingPaymentReviewsProvider);
      notice(context, 'Pending reviews cleared.');
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not clear pending reviews.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviews = ref.watch(pendingPaymentReviewsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pending expense reviews',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: reviews.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load pending expense reviews.'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(pendingPaymentReviewsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (items) => Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Detected payments appear here for review. Tap a transaction to edit it, or swipe left to dismiss.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: items.isEmpty
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: SurfaceCard(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Center(
                                    heightFactor: 1,
                                    child: Text(
                                      'No pending expense reviews.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : ScrollableListCard(
                              itemCount: items.length,
                              itemBuilder: (context, index) =>
                                  _PendingPaymentRow(
                                    key: ValueKey(items[index].id),
                                    review: items[index],
                                  ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: items.isEmpty || _clearing ? null : _clearAll,
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                      label: Text(
                        _clearing ? 'Clearing…' : 'Clear all reviews',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingPaymentRow extends ConsumerWidget {
  const _PendingPaymentRow({super.key, required this.review});
  final PendingPaymentReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = review.draft;
    final currency = AppCurrency.values.firstWhere(
      (value) => value.code == draft.currency,
    );
    return SwipeRevealDelete(
      actionLabel: 'Dismiss',
      errorMessage: 'Could not dismiss the review. Please try again.',
      onDelete: () async {
        await resolvePaymentReview(review.id, 'dismissed');
        if (context.mounted) {
          ref.invalidate(pendingPaymentReviewsProvider);
          notice(context, 'Review dismissed.');
        }
      },
      child: InkWell(
        onTap: () => PaymentReviewHost.reviewItem(context, review.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  alignment: AlignmentDirectional.centerEnd,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    currency.format(draft.amount),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
