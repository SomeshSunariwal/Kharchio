import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/expense_store.dart';
import '../../core/preferences.dart';
import '../../core/theme.dart';
import '../../core/theme_settings.dart';
import '../../services/ai/model_download_manager.dart';
import '../../services/ai/model_download_store.dart';
import '../../services/ai/model_manager.dart';
import '../../services/ai/model_validator.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/destructive_confirmation.dart';
import '../../shared/preference_dropdown_row.dart';
import '../../shared/widgets.dart';
import 'model_check_dialog.dart';
import 'user_profile_card.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
  bool resettingExpenses = false;

  Future<void> _resetExpenses() async {
    if (resettingExpenses) return;
    setState(() => resettingExpenses = true);
    try {
      final confirmed = await confirmDestructiveAction(
        context,
        title: 'Reset all expense data?',
        message: 'This permanently deletes all recorded expenses. Categories, settings and downloaded models will be kept. This cannot be undone.',
        confirmLabel: 'Reset All',
      );
      if (confirmed != true || !mounted) return;
      await ref.read(expensesProvider.notifier).reset();
      if (mounted) notice(context, 'All expense data has been cleared.');
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not reset expense data. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => resettingExpenses = false);
    }
  }

  static const _speechProcessingOptions = [
    AppDropdownOption(
      ProcessingMode.s23Ultra,
      'S23 Ultra',
      icon: Icons.phone_android_outlined,
    ),
    ..._processingOptions,
  ];
  static const _processingOptions = [
    AppDropdownOption(
      ProcessingMode.npu,
      'NPU',
      icon: Icons.auto_awesome_outlined,
    ),
    AppDropdownOption(ProcessingMode.gpu, 'GPU', icon: Icons.memory_outlined),
    AppDropdownOption(
      ProcessingMode.cpu,
      'CPU',
      icon: Icons.developer_board_outlined,
    ),
  ];

  Future<void> _setProcessing(
    ProcessingMode mode, {
    required bool speech,
  }) async {
    try {
      final settings = ref.read(preferencesProvider.notifier);
      if (speech) {
        await settings.setSpeechProcessing(mode);
      } else {
        await settings.setExpenseProcessing(mode);
      }
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not save processing mode. Please try again.');
      }
    }
  }

  Future<void> _setSpeechLanguage(String language) async {
    try {
      await ref.read(preferencesProvider.notifier).setSpeechLanguage(language);
    } catch (_) {
      if (mounted) {
        notice(
          context,
          'Could not save the speech language. Please try again.',
        );
      }
    }
  }

  Future<void> _setCurrency(AppCurrency currency) async {
    try {
      await ref.read(preferencesProvider.notifier).setCurrency(currency);
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not save the currency. Please try again.');
      }
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    try {
      await ref.read(themeModeProvider.notifier).select(mode);
    } catch (_) {
      if (mounted) {
        notice(context, 'Could not save the theme. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(modelDownloadsProvider);
    final current = downloads.value;
    final inventory = current?.inventory;
    final controlsEnabled =
        !downloads.isLoading &&
        !downloads.hasError &&
        inventory?.anyReady == true &&
        current?.active == null;
    final preferences = ref.watch(preferencesProvider);
    return SafeArea(
      child: FixedHeaderPage(
        header: const Text(
          'Profile & Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            const UserProfileCard(),
            const SizedBox(height: 16),
            const Text(
              'Preferences',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Column(
                children: [
                  PreferenceDropdownRow<ThemeMode>(
                    value: ref.watch(themeModeProvider),
                    label: 'Theme',
                    icon: Icons.palette_outlined,
                    options: const [
                      AppDropdownOption(
                        ThemeMode.system,
                        'System (default)',
                        icon: Icons.brightness_auto_outlined,
                      ),
                      AppDropdownOption(
                        ThemeMode.dark,
                        'Dark',
                        icon: Icons.dark_mode_outlined,
                      ),
                      AppDropdownOption(
                        ThemeMode.light,
                        'Light',
                        icon: Icons.light_mode_outlined,
                      ),
                    ],
                    onChanged: _setTheme,
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  PreferenceDropdownRow<String>(
                    value: ref.watch(preferencesProvider).speechLanguage,
                    label: 'Speech',
                    icon: Icons.translate,
                    options: const [
                      AppDropdownOption(
                        'auto',
                        'Automatic',
                        icon: Icons.translate,
                      ),
                      AppDropdownOption('en', 'English', icon: Icons.translate),
                      AppDropdownOption(
                        'hinglish',
                        'Hinglish',
                        icon: Icons.translate,
                      ),
                    ],
                    onChanged: _setSpeechLanguage,
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  PreferenceDropdownRow<AppCurrency>(
                    value: ref.watch(preferencesProvider).currency,
                    label: 'Currency',
                    icon: Icons.payments_outlined,
                    options: const [
                      AppDropdownOption(
                        AppCurrency.inr,
                        'Rupees (INR)',
                        icon: Icons.currency_rupee,
                      ),
                      AppDropdownOption(
                        AppCurrency.usd,
                        'Dollar (USD)',
                        icon: Icons.attach_money,
                      ),
                    ],
                    onChanged: _setCurrency,
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      minTileHeight: 54,
                      minVerticalPadding: 0,
                      minLeadingWidth: 18,
                      horizontalTitleGap: 8,
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                        color: green,
                      ),
                      visualDensity: VisualDensity.standard,
                      title: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Budget Planner',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Set monthly spending budgets',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appColors.muted,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => context.push('/budget-planner'),
                    ),
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.standard,
                      minTileHeight: 54,
                      minVerticalPadding: 0,
                      minLeadingWidth: 18,
                      horizontalTitleGap: 8,
                      leading: const Icon(
                        Icons.category_outlined,
                        size: 18,
                        color: green,
                      ),
                      title: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Categories',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Manage expense categories',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appColors.muted,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => context.push('/categories'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline AI',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Column(
                children: [
                  if (downloads.isLoading) const LinearProgressIndicator(),
                  if (downloads.hasError)
                    Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Could not read model storage.',
                          style: TextStyle(color: red, fontSize: 12),
                        ),
                        trailing: TextButton(
                          onPressed: () =>
                              ref.invalidate(modelDownloadsProvider),
                          child: const Text('Retry'),
                        ),
                      ),
                    ),
                  _downloadModel(
                    ModelGroup.speechGpu,
                    Icons.graphic_eq,
                    'Speech Model for GPU',
                    'Whisper Small · GPU / CPU',
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  _downloadModel(
                    ModelGroup.speechNpu,
                    Icons.memory_outlined,
                    'Speech Model for NPU',
                    'Snapdragon Optimized Model',
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  _downloadModel(
                    ModelGroup.qwen,
                    Icons.auto_awesome_outlined,
                    'Qwen Model for NPU',
                    'Qwen3 · 0.6B · Expense extraction',
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  PreferenceDropdownRow<ProcessingMode>(
                    matchModelRows: true,
                    enabled: controlsEnabled && inventory?.speechReady == true,
                    value: ref.watch(preferencesProvider).speechProcessing,
                    label: 'Speech Processing',
                    description: inventory?.speechIssue(
                      preferences.speechProcessing.nativeValue,
                    ),
                    descriptionError: true,
                    icon: Icons.graphic_eq,
                    options: _speechProcessingOptions,
                    onChanged: (mode) => _setProcessing(mode, speech: true),
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  PreferenceDropdownRow<ProcessingMode>(
                    matchModelRows: true,
                    enabled:
                        controlsEnabled &&
                        inventory?.ready.contains('qwen') == true,
                    value: ref.watch(preferencesProvider).expenseProcessing,
                    label: 'Expense AI Processing',
                    description: inventory?.expenseIssue,
                    descriptionError: true,
                    icon: Icons.memory_outlined,
                    options: _processingOptions,
                    onChanged: (mode) => _setProcessing(mode, speech: false),
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  _model(
                    OfflineModelKind.whisper,
                    Icons.graphic_eq,
                    'Whisper Small',
                    'English & Hinglish · Offline',
                  ),
                  Divider(height: 1, color: context.appColors.line),
                  _model(
                    OfflineModelKind.qwen,
                    Icons.auto_awesome_outlined,
                    'Qwen',
                    'Qwen3 · 0.6B · On-device expense extraction',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Data Share',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  dense: true,
                  minTileHeight: 64,
                  minLeadingWidth: 18,
                  horizontalTitleGap: 10,
                  leading: const Icon(
                    Icons.share_outlined,
                    size: 20,
                    color: green,
                  ),
                  title: const Text(
                    'Share App Data with Others',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Send expenses over a local connection',
                    style: TextStyle(
                      fontSize: 10,
                      color: context.appColors.muted,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.push('/data-share'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Danger Zone',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: red,
              ),
            ),
            const SizedBox(height: 8),
            SurfaceCard(
              color: Color.alphaBlend(
                red.withValues(alpha: 0.08),
                context.appColors.surface,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: _modelActionRow(
                Icons.delete_forever_outlined,
                'Reset Data',
                'Delete all recorded expenses',
                actionLabel: resettingExpenses ? 'Resetting…' : 'Reset All',
                destructive: true,
                iconColor: red,
                onPressed: resettingExpenses ? null : _resetExpenses,
                disabledMessage: 'Resetting expense data…',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Information',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20, color: green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'About',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Version 0.1.0',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.lock_outline, size: 15, color: green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Offline-first · No login or cloud storage',
                    style: TextStyle(
                      color: context.appColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _model(
    OfflineModelKind kind,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final downloads = ref.watch(modelDownloadsProvider).value;
    final inventory = downloads?.inventory;
    final mode = ref.watch(preferencesProvider).speechProcessing.nativeValue;
    final issue = inventory == null
        ? 'Checking downloaded models…'
        : kind == OfflineModelKind.whisper
        ? inventory.speechIssue(mode)
        : inventory.expenseIssue;
    return _modelActionRow(
      icon,
      title,
      issue ?? subtitle,
      subtitleError: issue != null && inventory != null,
      actionLabel: 'Check',
      onPressed: issue != null || downloads?.active != null
          ? null
          : () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => ModelCheckDialog(
                kind: kind,
                processingMode:
                    (kind == OfflineModelKind.whisper
                            ? ref.read(preferencesProvider).speechProcessing
                            : ref.read(preferencesProvider).expenseProcessing)
                        .nativeValue,
                speechLanguage: ref.read(preferencesProvider).speechLanguage,
                loadModels: () {
                  return ref
                      .read(offlineModelsProvider.notifier)
                      .requireAvailable(
                        speechMode: kind == OfflineModelKind.whisper
                            ? ref
                                  .read(preferencesProvider)
                                  .speechProcessing
                                  .nativeValue
                            : null,
                        expense: kind == OfflineModelKind.qwen,
                      );
                },
              ),
            ),
    );
  }

  Widget _downloadModel(
    ModelGroup group,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final current = ref.watch(modelDownloadsProvider).value;
    final ready = current?.inventory.groupReady(group) == true;
    final active = current?.active == group;
    final failed = current?.errorGroup == group;
    final deleting = active && current?.phase == 'Deleting';
    final buttonLabel = deleting
        ? 'Deleting…'
        : active
        ? 'Pause'
        : ready
        ? 'Delete'
        : failed
        ? (current!.paused ? 'Resume' : 'Retry')
        : 'Download';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _modelActionRow(
          icon,
          title,
          subtitle,
          ready: ready && !active,
          destructive: ready && !active,
          actionLabel: buttonLabel,
          onDelete:
              !ready &&
                  current?.inventory.hasData(group) == true &&
                  current?.active == null
              ? () => _deleteModel(group, title)
              : null,
          onPressed:
              current == null || deleting || (current.active != null && !active)
              ? null
              : () {
                  final manager = ref.read(modelDownloadsProvider.notifier);
                  if (active) {
                    manager.pause();
                  } else if (ready) {
                    _deleteModel(group, title);
                  } else {
                    manager.download(group);
                  }
                },
        ),
        if (active && !deleting) ...[
          LinearProgressIndicator(
            value: current!.total > 0 ? current.received / current.total : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${current.phase} · ${current.total > 0 ? (current.received * 100 / current.total).floor() : 0}% · ${(current.received / 1048576).toStringAsFixed(0)} / ${(current.total / 1048576).toStringAsFixed(0)} MB',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.appColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  current.phase != 'Downloading' || current.bytesPerSecond <= 0
                      ? '—'
                      : current.bytesPerSecond >= 1048576
                      ? '${(current.bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s'
                      : '${(current.bytesPerSecond / 1024).toStringAsFixed(0)} KB/s',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.appColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (failed && current?.error != null) _modelIssue(current!.error!),
      ],
    );
  }

  Future<void> _deleteModel(ModelGroup group, String title) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Delete $title?',
      message: switch (group) {
        ModelGroup.speechGpu => 'This removes GPU/CPU speech weights. NPU speech models will be kept.',
        ModelGroup.speechNpu => 'This removes both NPU variants and their compiled cache. GPU/CPU speech weights will be kept.',
        ModelGroup.qwen =>
          'Expense AI will be unavailable until you download Qwen again.',
      },
    );
    if (confirmed == true && mounted) {
      await ref.read(modelDownloadsProvider.notifier).delete(group);
    }
  }

  Widget _modelIssue(String issue) => Padding(
    padding: const EdgeInsets.only(left: 28, bottom: 10),
    child: Text(
      issue,
      style: const TextStyle(fontSize: 11, color: red, height: 1.4),
    ),
  );

  ButtonStyle _actionButtonStyle({bool destructive = false}) =>
      OutlinedButton.styleFrom(
        foregroundColor: destructive ? Colors.white : null,
        backgroundColor: destructive ? red : null,
        minimumSize: const Size(56, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: BorderSide(
          color: destructive ? red : context.appColors.line,
          width: 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(
          fontSize: 11,
          fontWeight: destructive ? FontWeight.w700 : FontWeight.w500,
        ),
      );

  Widget _modelActionRow(
    IconData icon,
    String title,
    String subtitle, {
    required String actionLabel,
    required VoidCallback? onPressed,
    bool ready = false,
    bool destructive = false,
    Color iconColor = green,
    bool subtitleError = false,
    String? disabledMessage,
    VoidCallback? onDelete,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 74),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: subtitleError ? red : context.appColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (ready) ...[
            const Text(
              'Ready',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: green,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Tooltip(
            message: onPressed == null
                ? disabledMessage ?? 'Download the required model first, or wait for the current operation.'
                : '$actionLabel $title',
            child: OutlinedButton(
              style: _actionButtonStyle(destructive: destructive),
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onDelete,
              style: _actionButtonStyle(destructive: true),
              child: const Text('Delete'),
            ),
          ],
        ],
      ),
    ),
  );
}
