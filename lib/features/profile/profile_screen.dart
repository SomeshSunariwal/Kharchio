import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/theme_settings.dart';
import '../../core/preferences.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/preference_dropdown_row.dart';
import '../../shared/widgets.dart';
import '../../services/ai/model_manager.dart';
import '../../services/ai/model_validator.dart';
import 'model_check_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
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
  Widget build(BuildContext context) => SafeArea(
    child: FixedHeaderPage(
      header: const Text(
        'Profile & Settings',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          SurfaceCard(
            color: context.appColors.tint,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const AppIcon(size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your personal ledger',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kharchio · Spend mindfully',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                PreferenceDropdownRow<ProcessingMode>(
                  value: ref.watch(preferencesProvider).speechProcessing,
                  label: 'Speech processing',
                  icon: Icons.graphic_eq,
                  options: _speechProcessingOptions,
                  onChanged: (mode) => _setProcessing(mode, speech: true),
                ),
                Divider(height: 1, color: context.appColors.line),
                PreferenceDropdownRow<ProcessingMode>(
                  value: ref.watch(preferencesProvider).expenseProcessing,
                  label: 'Expense AI processing',
                  icon: Icons.memory_outlined,
                  options: _processingOptions,
                  onChanged: (mode) => _setProcessing(mode, speech: false),
                ),
                Divider(height: 1, color: context.appColors.line),
                ListTile(
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
                      const Text('Categories', style: TextStyle(fontSize: 12)),
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
                  'Qwen3 · 0.6B',
                  'On-device expense extraction',
                ),
              ],
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
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
              onPressed: () => showAboutDialog(
                context: context,
                applicationName: 'Kharchio',
                applicationIcon: const AppIcon(size: 48),
                applicationVersion: '1.0.0',
                applicationLegalese: 'com.expense.kharchio',
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Expenses and preferences are stored locally in SQLite. Whisper and Qwen process recordings on this device. Audio and temporary summaries are never saved.',
                    ),
                  ),
                ],
              ),
              child: const Text(
                'About Kharchio',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _model(
    OfflineModelKind kind,
    IconData icon,
    String title,
    String subtitle,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
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
                style: TextStyle(fontSize: 10, color: context.appColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(56, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            side: BorderSide(color: context.appColors.line, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontSize: 11),
          ),
          onPressed: () => showDialog<void>(
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
                if (ref.read(offlineModelsProvider).hasError) {
                  ref.invalidate(offlineModelsProvider);
                }
                return ref.read(offlineModelsProvider.future);
              },
            ),
          ),
          child: const Text('Check'),
        ),
      ],
    ),
  );
}
