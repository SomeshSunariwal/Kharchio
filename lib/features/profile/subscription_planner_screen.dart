import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/preferences.dart';
import '../../core/subscriptions.dart';
import '../../core/theme.dart';
import '../../database/subscription_store.dart';
import '../../services/notifications/subscription_reminders.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/modern_date_picker.dart';
import '../../shared/widgets.dart';
import 'subscription_renewal_dialog.dart';
import 'renew_subscription_popup.dart';

const _frequencies = {1: 'Monthly', 3: 'Quarterly', 12: 'Yearly'};

String subscriptionRenewalLocation(SubscriptionDue renewal) => Uri(
  path: '/subscription-planner',
  queryParameters: {'plan': renewal.planId, 'due': '${renewal.dueDay}'},
).toString();

class SubscriptionPlannerScreen extends ConsumerStatefulWidget {
  final SubscriptionDue? openRenewal;
  const SubscriptionPlannerScreen({super.key, this.openRenewal});

  @override
  ConsumerState<SubscriptionPlannerScreen> createState() => _PlannerState();
}

class _PlannerState extends ConsumerState<SubscriptionPlannerScreen> {
  @override
  void initState() {
    super.initState();
    final target = widget.openRenewal;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final state = await ref.read(subscriptionsProvider.future);
        if (!mounted) return;
        final plan = state.plansById[target.planId];
        if (plan != null) _renewal(plan, subscriptionDate(target.dueDay));
      } catch (_) {
        if (mounted) {
          notice(context, 'Could not open the renewal.', isError: true);
        }
      }
    });
  }

  void _renewal(SubscriptionPlan plan, DateTime date) {
    final day = subscriptionDay(date);
    final paid =
        ref
            .read(subscriptionsProvider)
            .value
            ?.renewal(plan.id, day)
            ?.expenseId !=
        null;
    if (paid) {
      showDialog<void>(
        context: context,
        builder: (_) => SubscriptionRenewalDialog(plan: plan, initialDue: date),
      );
    } else {
      showRenewSubscriptionPopup(context, (plan: plan, dueDay: day));
    }
  }

  void _edit({SubscriptionPlan? plan, DateTime? nextDue}) => showDialog<void>(
    context: context,
    builder: (_) => _PlanEditor(plan: plan, nextDue: nextDue),
  );

  Future<void> _enablePhoneAlerts() async {
    try {
      await enableSubscriptionAlerts();
      if (mounted) ref.invalidate(subscriptionAlertPermissionProvider);
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not open notification settings.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final permission = ref.watch(subscriptionAlertPermissionProvider).value;
    final plans = ref.watch(subscriptionsProvider);
    return PlannerPage(
      title: 'Subscription Planner',
      addLabel: 'Add Subscription',
      onAdd: () => _edit(),
      child: Padding(
        padding: settingsPageContentPadding,
        child: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load subscriptions.'),
                TextButton(
                  onPressed: () => ref.invalidate(subscriptionsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (state) => _planList(state, permission),
        ),
      ),
    );
  }

  Widget _planList(SubscriptionState state, bool? permission) {
    final now = DateTime.now();
    final nextDates = {
      for (final plan in state.plans) plan.id: state.nextDue(plan, now),
    };
    final ordered = [...state.plans]
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return nextDates[a.id]!.compareTo(nextDates[b.id]!);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set up recurring payments and renewal reminders.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (supportsSubscriptionReminders &&
            permission == false &&
            ordered.any(
              (plan) => plan.active && plan.reminderDays != null,
            )) ...[
          TextButton.icon(
            onPressed: _enablePhoneAlerts,
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('Enable phone notifications'),
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: ordered.isEmpty
              ? const SurfaceCard(
                  child: Center(child: Text('No subscriptions yet.')),
                )
              : ScrollableListCard(
                  itemCount: ordered.length,
                  itemBuilder: (_, index) => _planRow(
                    state,
                    ordered[index],
                    now,
                    nextDates[ordered[index].id]!,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _planRow(
    SubscriptionState state,
    SubscriptionPlan plan,
    DateTime now,
    DateTime nextDue,
  ) {
    final reviewDue = state.dueToReview(plan, now);
    final overdue =
        plan.active && subscriptionDay(reviewDue) < subscriptionDay(now);
    final currency = AppCurrency.fromCode(plan.currencyCode);
    final tone = plan.active ? green : context.appColors.muted;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _edit(plan: plan, nextDue: nextDue),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.autorenew_rounded, size: 15, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SettingsRowLabel(
                  plan.name,
                  [
                    '${_frequencies[plan.intervalMonths]}',
                    if (!plan.active)
                      'Paused'
                    else if (overdue)
                      'Payment unconfirmed · ${DateFormat('d MMM').format(reviewDue)}'
                    else
                      'Renews ${DateFormat('d MMM yyyy').format(nextDue)}',
                  ].join(' · '),
                  descriptionMaxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: settingsListRowHeight - 12,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    currency.formatChart(plan.minor / 100),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: red,
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

class _PlanEditor extends ConsumerStatefulWidget {
  final SubscriptionPlan? plan;
  final DateTime? nextDue;
  const _PlanEditor({this.plan, this.nextDue});

  @override
  ConsumerState<_PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends ConsumerState<_PlanEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name);
  late final _amount = TextEditingController(
    text: widget.plan == null
        ? ''
        : (widget.plan!.minor / 100).toStringAsFixed(2),
  );
  late final _id = widget.plan?.id ?? const Uuid().v4();
  late DateTime _due = widget.nextDue ?? DateTime.now();
  late String _currency =
      widget.plan?.currencyCode ?? ref.read(preferencesProvider).currency.code;
  late int _frequency = widget.plan?.intervalMonths ?? 1;
  late int _lead = widget.plan == null ? 3 : widget.plan!.reminderDays ?? -1;
  late int _minute = widget.plan?.reminderMinutes ?? 9 * 60;
  late bool _active = widget.plan?.active ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final previous = widget.plan;
    try {
      await ref
          .read(subscriptionStoreProvider)
          .save(
            SubscriptionPlan(
              id: _id,
              name: _name.text.trim(),
              minor: (double.parse(_amount.text.trim()) * 100).round(),
              currencyCode: _currency,
              intervalMonths: _frequency,
              anchorDay:
                  previous != null &&
                      previous.intervalMonths == _frequency &&
                      subscriptionDay(_due) == subscriptionDay(widget.nextDue!)
                  ? previous.anchorDay
                  : subscriptionDay(_due),
              reminderDays: _lead < 0 ? null : _lead,
              reminderMinutes: _minute,
              active: _active,
              merchantAliases: previous?.merchantAliases ?? '[]',
            ),
          );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the subscription.';
        });
      }
    }
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    isDense: true,
    labelStyle: TextStyle(fontSize: 12, color: context.appColors.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    constraints: const BoxConstraints(minHeight: 42),
  );

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60);
    final editing = widget.plan != null;
    final fields = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          TextFormField(
            controller: _name,
            enabled: !_saving,
            maxLength: 60,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: _input('Subscription name')
                .copyWith(hintText: 'Spotify', counterText: ''),
            validator: (value) =>
                value!.trim().isEmpty ? 'Enter a subscription name' : null,
          ),
          TextFormField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: _input('Expected amount ($_currency)'),
            validator: validateSubscriptionAmount,
          ),
          Row(
            spacing: 10,
            children: [
              Expanded(
                child: AppDropdown<String>(
                  value: _currency,
                  label: 'Currency',
                  enabled: !editing && !_saving,
                  options: [
                    for (final item in AppCurrency.values)
                      AppDropdownOption(item.code, item.code),
                  ],
                  onChanged: (value) => setState(() => _currency = value),
                ),
              ),
              Expanded(
                child: AppDropdown<int>(
                  value: _frequency,
                  label: 'Billing frequency',
                  enabled: !_saving,
                  options: [
                    for (final item in _frequencies.entries)
                      AppDropdownOption(item.key, item.value),
                  ],
                  onChanged: (value) => setState(() => _frequency = value),
                ),
              ),
            ],
          ),
          subscriptionPickerRow(
            context,
            'Next renewal date and time',
            '${DateFormat('d MMM yyyy').format(_due)} · ${time.format(context)}',
            Icons.calendar_month_outlined,
            _saving
                ? null
                : () async {
                    final date = await showDialog<DateTime>(
                      context: context,
                      builder: (_) => ModernDatePicker(
                        initialDate: DateTime(
                          _due.year,
                          _due.month,
                          _due.day,
                          _minute ~/ 60,
                          _minute % 60,
                        ),
                        includeTime: true,
                        firstDate: DateTime(
                          DateTime.now().year,
                          DateTime.now().month,
                        ),
                      ),
                    );
                    if (mounted && date != null) {
                      setState(() {
                        _due = date;
                        _minute = date.hour * 60 + date.minute;
                      });
                    }
                  },
            compact: true,
          ),
          AppDropdown<int>(
            value: _lead,
            label: 'Renewal reminder',
            enabled: !_saving,
            options: [
              const AppDropdownOption(-1, 'Off'),
              const AppDropdownOption(0, 'On the day'),
              const AppDropdownOption(1, '1 day before'),
              for (var day = 2; day <= 7; day++)
                AppDropdownOption(day, '$day days before'),
            ],
            onChanged: (value) => setState(() => _lead = value),
          ),
          if (editing)
            SwitchListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Active Subscription',
                style: TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: red)),
        ],
      ),
    );
    final colors = context.appColors;
    final close = _saving ? null : () => Navigator.pop(context);
    return PopScope(
      canPop: !_saving,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 380,
            maxHeight: MediaQuery.sizeOf(context).height * .82,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.autorenew_rounded,
                        size: 20,
                        color: green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        editing ? 'Edit Subscription' : 'Add Subscription',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: fields,
                  ),
                ),
                const SizedBox(height: 10),
                DialogActionRow(
                  onSecondary: close,
                  onPrimary: _saving ? null : _save,
                  primaryLabel: Text(
                    _saving ? 'Saving…' : 'Save subscription',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
