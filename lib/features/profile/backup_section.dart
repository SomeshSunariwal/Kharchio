import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/expense_store.dart';
import '../../core/monthly_budgets.dart';
import '../../core/theme.dart';
import '../../database/local_store.dart';
import '../../services/backup/expense_backup.dart';
import '../../shared/app_confirmation.dart';
import '../../shared/app_notification.dart';
import '../../shared/widgets.dart';

class BackupSection extends ConsumerStatefulWidget {
  const BackupSection({super.key});
  @override
  ConsumerState<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<BackupSection> {
  String? working;

  Future<void> _run(String action, Future<void> Function() work) async {
    if (working != null) return;
    setState(() => working = action);
    try {
      await work();
    } catch (error) {
      if (mounted) {
        notice(
          context,
          error is FormatException
              ? error.message
              : 'Could not ${action.toLowerCase()} data. Please try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => working = null);
    }
  }

  Future<void> _export() => _run('Export', () async {
    final bytes = await ExpenseBackupRepository(ref.read(localStoreProvider))
        .export();
    if (!mounted) return;
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final saved = await FilePicker.saveFile(
      fileName: 'Kharchio-$stamp.json.gz',
      bytes: bytes,
      mimeType: 'application/gzip',
      dialogTitle: 'Export expense backup',
    );
    if (mounted && saved != null) notice(context, 'Expense backup exported.');
  });

  Future<void> _import() => _run('Import', () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import Kharchio backup',
    );
    if (file == null || !mounted) return;
    final backup = await ExpenseBackup.read(file.readAsByteStream());
    if (!mounted) return;
    final repository = ExpenseBackupRepository(ref.read(localStoreProvider));
    final possible = await repository.possibleDuplicates(backup);
    if (!mounted) return;
    final confirmed = await showAppConfirmation(
      context,
      title: 'Import expense data?',
      message:
          '${backup.expenses.length} expense/refund records and '
          '${backup.limits.length} monthly limits.\n\n'
          'Records with an existing ID will be skipped. Monthly limits in the backup '
          'will replace limits for the same month and currency. Other data is kept.'
          '${possible == 0 ? '' : '\n\n$possible records have matching details but different IDs. '
                    'These may be separate purchases and will also be imported.'}',
      confirmLabel: 'Import',
      icon: Icons.file_download_outlined,
    );
    if (!confirmed || !mounted) return;
    final providers = ProviderScope.containerOf(context, listen: false);
    final update = appNotificationUpdater(context);
    update('Importing expenses and monthly limits…', progress: 0);
    try {
      final result = await repository.merge(
        backup,
        onProgress: (value) {
          update(
            value == 1
                ? 'Import complete'
                : 'Importing expenses and monthly limits…',
            progress: value,
          );
        },
      );
      update(
        'Imported ${result.added} records and ${backup.limits.length} monthly limits. '
        'Skipped ${result.skipped} existing records.',
        progress: 1,
      );
      // Expenses and categories watch Drift; budgets use an explicit load.
      providers.invalidate(monthlyBudgetsProvider);
      await providers.read(expensesProvider.notifier).refresh();
    } catch (_) {
      if (!mounted) {
        update('Could not import data. Please try again.', isError: true);
      }
      rethrow;
    }
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Data Backup',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      SurfaceCard(
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _row(
              Icons.file_upload_outlined,
              'Export Data',
              'Expenses and monthly limits · Compressed backup',
              _export,
              busy: working == 'Export',
            ),
            Divider(
              height: 1,
              indent: 10,
              endIndent: 10,
              color: context.appColors.line,
            ),
            _row(
              Icons.file_download_outlined,
              'Import Data',
              'Merge expenses and restore monthly limits',
              _import,
              busy: working == 'Import',
            ),
          ],
        ),
      ),
    ],
  );

  Widget _row(
    IconData icon,
    String title,
    String description,
    VoidCallback action, {
    required bool busy,
  }) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      dense: true,
      minTileHeight: settingsRowMinHeight,
      minVerticalPadding: 0,
      minLeadingWidth: 18,
      horizontalTitleGap: 10,
      enabled: working == null,
      leading: Icon(icon, size: 20, color: green),
      title: SettingsRowLabel(title, description),
      trailing: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '$title in progress',
              ),
            )
          : const Icon(Icons.chevron_right, size: 18),
      onTap: action,
    ),
  );
}
