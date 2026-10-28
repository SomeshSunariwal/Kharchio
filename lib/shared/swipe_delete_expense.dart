import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/expense_store.dart';
import '../core/theme.dart';
import 'destructive_confirmation.dart';

Future<bool> confirmExpenseDeletion(BuildContext context, String title) =>
    confirmDestructiveAction(
      context,
      title: 'Delete expense?',
      message: 'Delete "$title"? This cannot be undone.',
      confirmLabel: 'OK',
    );

/// Expense actions use the same reveal interaction as other deletable rows.
class SwipeDeleteExpense extends ConsumerWidget {
  final Expense expense;
  final Widget child;
  const SwipeDeleteExpense({
    super.key,
    required this.expense,
    required this.child,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => SwipeRevealDelete(
    onDelete: () async {
      if (await confirmExpenseDeletion(context, expense.title)) {
        await ref.read(expensesProvider.notifier).delete(expense.id);
      }
    },
    errorMessage: 'Could not delete the expense. Please try again.',
    child: child,
  );
}

/// Reveals an action without dismissing the row or changing its height.
class SwipeRevealDelete extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onDelete;
  final String errorMessage;
  const SwipeRevealDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.errorMessage = 'Could not delete this item. Please try again.',
  });
  @override
  State<SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<SwipeRevealDelete>
    with SingleTickerProviderStateMixin {
  static const actionWidth = 76.0;
  late final slide = AnimationController(
    vsync: this,
    upperBound: 1.28,
    duration: const Duration(milliseconds: 200),
  );
  bool busy = false;
  double dragValue = 0;

  void settle(bool open, {double velocity = 0}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      slide.value = open ? 1 : 0;
    } else {
      slide
          .animateWith(
            SpringSimulation(
              const SpringDescription(mass: 1, stiffness: 420, damping: 32),
              slide.value,
              open ? 1 : 0,
              velocity.clamp(-8.0, 8.0),
            ),
          )
          .then<void>((_) {
            if (mounted) slide.value = open ? 1 : 0;
          });
    }
  }

  Future<void> remove() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onDelete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.errorMessage)));
      }
    } finally {
      if (mounted) {
        settle(false);
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: slide,
    builder: (context, _) => Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Show delete button'): () =>
            settle(true),
      },
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: actionWidth,
                  height: double.infinity,
                  child: ExcludeSemantics(
                    excluding: slide.value < .99,
                    child: IgnorePointer(
                      ignoring: slide.value < .99 || busy,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Material(
                          color: red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: red, width: 1),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: remove,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Delete',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(-actionWidth * slide.value, 0),
              child: GestureDetector(
                onHorizontalDragStart: busy
                    ? null
                    : (_) {
                        slide.stop();
                        dragValue = slide.value;
                      },
                onHorizontalDragUpdate: busy
                    ? null
                    : (details) {
                        dragValue = (dragValue - details.delta.dx / actionWidth)
                            .clamp(0.0, double.infinity);
                        final excess = dragValue - 1;
                        slide.value =
                            excess > 0 &&
                                !MediaQuery.disableAnimationsOf(context)
                            ? 1 + .28 * excess / (.28 + excess)
                            : dragValue.clamp(0.0, 1.0);
                      },
                onHorizontalDragEnd: busy
                    ? null
                    : (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        settle(
                          velocity.abs() > 250
                              ? velocity < 0
                              : slide.value > .45,
                          velocity: -velocity / actionWidth,
                        );
                      },
                onHorizontalDragCancel: busy
                    ? null
                    : () => settle(slide.value > .45),
                onTap: slide.value > 0 ? () => settle(false) : null,
                child: AbsorbPointer(
                  absorbing: slide.value > 0 || busy,
                  child: Material(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: widget.child,
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
