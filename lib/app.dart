import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/theme_settings.dart';
import 'core/preferences.dart';
import 'core/categories.dart';
import 'features/profile/categories_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/expenses/add_expense_screen.dart';
import 'features/analysis/analysis_screen.dart';
import 'features/profile/profile_screen.dart';
import 'shared/directional_tab_view.dart';
import 'shared/active_text_navigation.dart';

final _router = GoRouter(
  routes: [
    StatefulShellRoute(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      navigatorContainerBuilder: (context, navigationShell, children) =>
          DirectionalTabView(
            index: navigationShell.currentIndex,
            children: children,
          ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/analysis',
              builder: (_, _) => const AnalysisScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/add',
      builder: (_, state) => AddExpenseScreen(expense: state.extra),
    ),
    GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
  ],
);

class KharchioApp extends ConsumerWidget {
  const KharchioApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Kharchio',
    debugShowCheckedModeBanner: false,
    theme: appTheme(),
    darkTheme: appTheme(brightness: Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: context.appColors.background,
              ),
      child: CategoriesScope(
        categories: ref.watch(categoriesProvider),
        child: CurrencyScope(
          currency: ref.watch(preferencesProvider).currency,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
    routerConfig: _router,
  );
}

class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: navigationShell,
      ),
    ),
    bottomNavigationBar: ActiveTextNavigation(
      selectedIndex: navigationShell.currentIndex,
      onSelected: (index) {
        if (index != navigationShell.currentIndex) {
          navigationShell.goBranch(index);
        }
      },
    ),
  );
}
