import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categories.dart';
import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../database/local_store.dart';
import '../../services/ai/expense_extractor.dart';
import '../../services/ai/model_manager.dart';
import '../../services/ai/native_ai.dart';
import '../../services/ai/online_ai_client.dart';
import '../../services/ai/online_ai_settings.dart';
import '../../services/notifications/payment_notification_parser.dart';
import '../../services/notifications/pending_payment_reviews.dart';
import '../../shared/widgets.dart';
import 'expense_draft_card.dart';

class PaymentReviewHost extends ConsumerStatefulWidget {
  const PaymentReviewHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  static void reviewItem(BuildContext context, String id) =>
      context.getInheritedWidgetOfExactType<_PaymentReviewScope>()!.review(id);

  @override
  ConsumerState<PaymentReviewHost> createState() => _PaymentReviewHostState();
}

class _PaymentReviewScope extends InheritedWidget {
  const _PaymentReviewScope({required this.review, required super.child});
  final ValueChanged<String> review;

  @override
  bool updateShouldNotify(_PaymentReviewScope oldWidget) => false;
}

class _PaymentReviewHostState extends ConsumerState<PaymentReviewHost>
    with WidgetsBindingObserver {
  final _requested = <String>{};
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (!supportsPaymentNotifications) return;
    WidgetsBinding.instance.addObserver(this);
    paymentNotificationChannel.setMethodCallHandler((call) async {
      if (call.method == 'paymentDetected' && call.arguments is String) {
        ref.invalidate(pendingPaymentReviewsProvider);
        _requestReview(call.arguments as String);
      } else if (call.method == 'reviewTapped') {
        await _consumeTap();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_consumeTap()),
    );
  }

  @override
  void dispose() {
    if (supportsPaymentNotifications) {
      WidgetsBinding.instance.removeObserver(this);
      paymentNotificationChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(pendingPaymentReviewsProvider);
      unawaited(_consumeTap());
    }
  }

  Future<void> _consumeTap() async {
    try {
      final id = await paymentNotificationChannel.invokeMethod<String>(
        'consumeReviewTap',
      );
      if (id != null) _requested.add(id);
      _schedule();
    } on PlatformException {
      // The pending list is still available from Settings.
    } on MissingPluginException {
      // No native host in previews and tests.
    }
  }

  void _schedule() {
    if (!mounted ||
        _requested.isEmpty ||
        _showing ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_review());
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _review() async {
    final context = widget.navigatorKey.currentContext;
    if (_showing || context == null || _requested.isEmpty) return;
    _showing = true;
    final ids = _requested.toSet();
    _requested.removeAll(ids);
    try {
      final reviews = await loadPendingPaymentReviews();
      for (final review in reviews) {
        if (!mounted || !context.mounted) break;
        if (!ids.contains(review.id)) continue;
        _requested.remove(review.id);
        final outcome = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: .16),
          builder: (_) => _PaymentReviewDialog(
            id: review.id,
            text: review.text,
            draft: review.draft,
          ),
        );
        if (outcome == null) break;
        await resolvePaymentReview(review.id, outcome);
        if (!mounted || !context.mounted) break;
        ref.invalidate(pendingPaymentReviewsProvider);
        if (outcome == 'dismissed') notice(context, 'Review dismissed.');
      }
    } catch (_) {
      if (context.mounted) {
        notice(context, 'Could not open payment reviews.', isError: true);
      }
    } finally {
      _showing = false;
      _schedule();
    }
  }

  void _requestReview(String id) {
    _requested.add(id);
    _schedule();
  }

  @override
  Widget build(BuildContext context) =>
      _PaymentReviewScope(review: _requestReview, child: widget.child);
}

class _PaymentReviewDialog extends ConsumerStatefulWidget {
  const _PaymentReviewDialog({
    required this.id,
    required this.text,
    required this.draft,
  });
  final String id, text;
  final PaymentNotificationDraft draft;

  @override
  ConsumerState<_PaymentReviewDialog> createState() =>
      _PaymentReviewDialogState();
}

class _PaymentReviewDialogState extends ConsumerState<_PaymentReviewDialog>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  late final ExpenseDraft _draft;
  late final AppCurrency _currency;
  bool _extracting = false;
  bool _saving = false;
  bool _rejected = false;
  String? _status;
  NativeAiJob? _job;
  late final _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  void _syncShimmer() {
    if (_extracting && !MediaQuery.disableAnimationsOf(context)) {
      if (!_shimmer.isAnimating) _shimmer.repeat();
    } else {
      _shimmer.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncShimmer();
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _currency = AppCurrency.values.firstWhere(
      (value) => value.code == draft.currency,
    );
    final names = ref.read(categoriesProvider).map((category) => category.name);
    _draft = ExpenseDraft(
      title: draft.merchant,
      amount: draft.amount.toStringAsFixed(2),
      category: names.contains(draft.category) ? draft.category : names.first,
    );
  }

  @override
  void dispose() {
    _job?.cancel();
    _shimmer.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    if (_extracting || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _extracting = true;
      _rejected = false;
      _status = 'Extracting payment details…';
    });
    _syncShimmer();
    NativeAiJob? job;
    try {
      final preferences = ref.read(preferencesProvider);
      final categories = ref
          .read(categoriesProvider)
          .map((c) => c.name)
          .toList();
      final text = redactPaymentText(widget.text);
      final currency = widget.draft.currency;
      final List<ExtractedExpense> result;
      if (preferences.aiMode == AiMode.online) {
        final provider = preferences.onlineAiProvider;
        final keys = ref.read(onlineAiKeysProvider);
        final createClient = ref.read(onlineAiClientFactoryProvider);
        if (provider == OnlineAiProvider.none) {
          throw StateError('No AI provider selected.');
        }
        final key = await keys.read(provider);
        final models = await keys.models(provider);
        if (!mounted) return;
        if (key == null || models == null) {
          throw StateError('Online AI is unavailable.');
        }
        final client = createClient(provider, key);
        try {
          result = await client.extract(
            text: text,
            categories: categories,
            currency: currency,
            models: models,
            paymentNotification: true,
          );
        } finally {
          client.close();
        }
      } else {
        final models = await ref
            .read(offlineModelsProvider.notifier)
            .requireAvailable(expense: true);
        if (!mounted) return;
        job = NativeAiJob();
        _job = job;
        await NativeAiJob.setProcessing(
          mode: preferences.expenseProcessing.nativeValue,
        );
        if (!mounted) return;
        result = await ExpenseExtractor().extract(
          job: job,
          model: models.qwen,
          text: text,
          categories: categories,
          currency: currency,
          paymentNotification: true,
        );
      }
      if (!mounted) return;
      if (result.isEmpty) {
        setState(() {
          _rejected = true;
          _status = 'AI did not find a completed expense.';
        });
        return;
      }
      final expense = result.single;
      if (expense.isRefund || expense.amount != widget.draft.amount) {
        throw const FormatException(
          'AI amount does not match the notification.',
        );
      }
      final merchant = redactPaymentText(expense.title);
      final description = redactPaymentText(expense.description);
      if (merchant.isEmpty) throw const FormatException('Missing merchant.');
      setState(() {
        _draft.title.text = merchant;
        _draft.description.text =
            description.toLowerCase() == merchant.toLowerCase()
            ? ''
            : description;
        _draft.category = expense.category;
        _status = 'AI extracted the payment details.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status = null);
        notice(
          context,
          'Could not extract payment details with AI.',
          isError: true,
        );
      }
    } finally {
      _job = null;
      if (job != null) {
        job.dispose();
        try {
          await NativeAiJob.releaseModels();
        } catch (_) {
          // Review remains available if the native runtime could not clean up.
        }
      }
      if (mounted) {
        setState(() => _extracting = false);
        _syncShimmer();
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _extracting || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = 'notification-${sha256.convert(utf8.encode(widget.id))}';
      final title = _draft.title.text.trim();
      final amount = double.parse(_draft.amount.text.trim());
      final existing = await ref.read(localStoreProvider).readExpenses();
      if (!mounted) return;
      final date = DateTime.now();
      final duplicate = existing.any(
        (expense) =>
            expense.id == id ||
            (expense.type == _draft.type &&
                expense.currencyCode == _currency.code &&
                expense.amount == amount &&
                expense.title.toLowerCase() == title.toLowerCase() &&
                expense.date.difference(widget.draft.date).abs() <
                    const Duration(seconds: 60)),
      );
      if (!duplicate) {
        await ref.read(expensesProvider.notifier).save([
          Expense(
            id: id,
            title: title,
            description: _draft.description.text.trim(),
            amount: amount,
            category: _draft.category,
            type: _draft.type,
            date: date,
            currencyCode: _currency.code,
          ),
        ]);
      }
      if (mounted) {
        if (duplicate) {
          notice(context, 'This expense is already recorded.');
        }
        Navigator.pop(context, 'saved');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = 'Could not save the expense. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final preferences = ref.watch(preferencesProvider);
    final online = preferences.aiMode == AiMode.online;
    final subtitle =
        _status ??
        (online
            ? 'The AI button sends a redacted message to ${preferences.onlineAiProvider.label}.'
            : null);
    final editable = !_extracting && !_saving && !_rejected;
    final validCategory = categories.any(
      (category) => category.name == _draft.category,
    );
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxWidth: 420),
        child: SurfaceCard(
          padding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CategoryIcon(_draft.category, size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Review detected expense',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExpenseDraftCard(
                    d: _draft,
                    categories: categories,
                    currency: _currency,
                    editable: editable,
                    shimmer:
                        _extracting && !MediaQuery.disableAnimationsOf(context)
                        ? _shimmer
                        : null,
                    onCategoryChanged: (value) =>
                        setState(() => _draft.category = value),
                    onTypeChanged: (value) =>
                        setState(() => _draft.type = value),
                    onRemove: _saving || _extracting
                        ? null
                        : () => Navigator.pop(context, 'dismissed'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          IconButton.outlined(
                            tooltip: online
                                ? 'Extract with online AI'
                                : 'Extract with on-device AI',
                            onPressed: _extracting || _saving ? null : _extract,
                            icon: const Icon(
                              Icons.auto_awesome_outlined,
                              size: 19,
                            ),
                          ),
                          if (_extracting)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Padding(
                                  // Match the outlined button inside its touch target.
                                  padding: const EdgeInsets.all(4),
                                  child: _AiProcessingBorder(
                                    animation: _shimmer,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text(
                                  'Review later',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                ),
                                onPressed: editable && validCategory
                                    ? _save
                                    : null,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  spacing: 4,
                                  children: [
                                    const Icon(Icons.add_rounded, size: 18),
                                    Flexible(
                                      child: Text(
                                        _saving
                                            ? 'Adding…'
                                            : _draft.type ==
                                                  TransactionType.refund
                                            ? 'Add refund'
                                            : 'Add expense',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AiProcessingBorder extends StatelessWidget {
  const _AiProcessingBorder({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final ring = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: green, width: 2),
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return ring;
    final dim = green.withValues(alpha: .25);
    return AnimatedBuilder(
      animation: animation,
      child: ring,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => SweepGradient(
          colors: [dim, dim, green, const Color(0xFFB4F7E4), green, dim],
          stops: const [0, .62, .79, .88, .94, 1],
          transform: GradientRotation(animation.value * 2 * math.pi),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}
