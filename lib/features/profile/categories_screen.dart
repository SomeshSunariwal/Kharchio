import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/categories.dart';
import '../../core/preview_data.dart';
import '../../core/theme.dart';

import '../../shared/widgets.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> removeCategory(
    BuildContext context,
    WidgetRef ref,
    ExpenseCategory category,
  ) async {
    final remaining = ref
        .read(categoriesProvider)
        .where((c) => c.name != category.name)
        .toList();
    if (remaining.isEmpty) return;
    final fallback =
        remaining.where((c) => c.name == 'Others').firstOrNull ??
        remaining.first;
    final count = ref
        .read(expensesProvider)
        .where((e) => e.category == category.name)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${category.name}?'),
        content: Text(
          count == 0
              ? 'Remove this category from expense selections?'
              : '$count expenses will move to ${fallback.name}. Their amounts and dates will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              backgroundColor: red,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final categoryStore = ref.read(categoriesProvider.notifier);
    try {
      await categoryStore.remove(category.name);
    } catch (_) {
      if (context.mounted) {
        notice(context, 'Could not remove the category. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Categories',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        'Choose categories when adding expenses. Your dashboard and analysis use the same categories.',
                        style: TextStyle(
                          color: context.appColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SurfaceCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < categories.length; i++) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    CategoryIcon(categories[i].name, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        categories[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Remove ${categories[i].name}',
                                      style: IconButton.styleFrom(
                                        backgroundColor: red,
                                        foregroundColor: Colors.white,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: categories.length <= 1
                                          ? null
                                          : () => removeCategory(
                                              context,
                                              ref,
                                              categories[i],
                                            ),
                                      icon: const Icon(
                                        Icons.remove_rounded,
                                        size: 19,
                                      ),
                                      color: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                              if (i < categories.length - 1)
                                Divider(
                                  height: 1,
                                  color: context.appColors.line,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const _AddCategoryDialog(),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Category'),
                    ),
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

class _AddCategoryDialog extends ConsumerStatefulWidget {
  const _AddCategoryDialog();
  @override
  ConsumerState<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<_AddCategoryDialog> {
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  String iconKey = 'others';
  bool saving = false;
  String? error;
  static const palette = [
    0xFF00AE87,
    0xFF365CFF,
    0xFFFFAB00,
    0xFFFF3891,
    0xFF8D51FF,
    0xFF009DC4,
    0xFFDB6D38,
    0xFF9BA7B7,
  ];
  int iconColor(String key) =>
      defaultCategories
          .where((category) => category.iconKey == key)
          .firstOrNull
          ?.colorValue ??
      palette[categoryIconOptions.keys.toList().indexOf(key) % palette.length];
  int get categoryColor => iconColor(iconKey);
  String get iconLabel => '${iconKey[0].toUpperCase()}${iconKey.substring(1)}';

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(categoriesProvider.notifier)
          .add(ExpenseCategory(name.text.trim(), categoryColor, iconKey));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save the category. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: context.appColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Color(categoryColor).withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      categoryIconOptions[iconKey],
                      size: 23,
                      color: Color(categoryColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Category',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Make it easy to recognise',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: name,
                          enabled: !saving,
                          maxLength: 30,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(fontSize: 14),
                          decoration: const InputDecoration(
                            labelText: 'Category name',
                            hintText: 'e.g. Personal care',
                            counterText: '',
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Enter a category name';
                            if (ref
                                .read(categoriesProvider)
                                .any(
                                  (c) =>
                                      c.name.toLowerCase() ==
                                      text.toLowerCase(),
                                )) {
                              return 'This category already exists';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Choose an icon',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              iconLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.appColors.muted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (context, constraints) => GridView.count(
                            crossAxisCount: constraints.maxWidth < 300 ? 5 : 6,
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              for (final entry in categoryIconOptions.entries)
                                Semantics(
                                  label:
                                      '${entry.key[0].toUpperCase()}${entry.key.substring(1)} icon',
                                  selected: entry.key == iconKey,
                                  button: true,
                                  child: Tooltip(
                                    message:
                                        '${entry.key[0].toUpperCase()}${entry.key.substring(1)}',
                                    child: Material(
                                      color: entry.key == iconKey
                                          ? Color(iconColor(entry.key))
                                                .withValues(alpha: .13)
                                          : context.appColors.field,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: entry.key == iconKey
                                              ? Color(iconColor(entry.key))
                                              : context.appColors.line,
                                          width: entry.key == iconKey ? 1.5 : 1,
                                        ),
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: saving
                                            ? null
                                            : () => setState(
                                                () => iconKey = entry.key,
                                              ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              entry.value,
                                              size: 23,
                                              color: Color(
                                                iconColor(entry.key),
                                              ),
                                            ),
                                            if (entry.key == iconKey)
                                              Positioned(
                                                right: 3,
                                                top: 3,
                                                child: Icon(
                                                  Icons.check_circle,
                                                  size: 10,
                                                  color: Color(
                                                    iconColor(entry.key),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              error!,
                              style: const TextStyle(fontSize: 12, color: red),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        side: BorderSide(color: context.appColors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: context.appColors.ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving ? null : save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add, size: 18),
                      label: Text(
                        saving ? 'Saving…' : 'Add Category',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
