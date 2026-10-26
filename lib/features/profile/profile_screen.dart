import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/theme_settings.dart';
import '../../core/preferences.dart';
import '../../shared/app_dropdown.dart';
import '../../shared/preference_dropdown_row.dart';
import '../../shared/widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
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
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
      children: [
        const Text(
          'Profile & Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
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
                  AppDropdownOption('auto', 'Automatic', icon: Icons.translate),
                  AppDropdownOption('hi', 'Hindi', icon: Icons.translate),
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
                Icons.graphic_eq,
                'Whisper.cpp',
                'Hindi, English & Hinglish',
              ),
              Divider(height: 1, color: context.appColors.line),
              _model(
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
                style: TextStyle(color: context.appColors.muted, fontSize: 11),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Kharchio',
              applicationIcon: const AppIcon(size: 48),
              applicationVersion: '1.0.0 · UI review',
              applicationLegalese: 'com.expense.kharchio',
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'This review build uses sample data and temporary expense storage. SQLite and offline AI integration are pending.',
                  ),
                ),
              ],
            ),
            child: const Text('About Kharchio', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    ),
  );

  Widget _model(IconData icon, String title, String subtitle) => Padding(
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: context.appColors.noticeBackground,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'Pending',
            style: TextStyle(
              color: context.appColors.noticeForeground,
              fontSize: 9,
            ),
          ),
        ),
      ],
    ),
  );
}
