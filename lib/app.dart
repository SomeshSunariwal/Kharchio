import 'package:flutter/material.dart';

import 'shared/app_notification.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/theme_settings.dart';
import 'core/preferences.dart';
import 'core/categories.dart';
import 'features/profile/categories_screen.dart';
import 'features/profile/budget_planner_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/expenses/add_expense_screen.dart';
import 'features/analysis/analysis_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/data_share/data_share_screen.dart';
import 'shared/directional_tab_view.dart';
import 'shared/active_text_navigation.dart';
import 'widgets/home_screen/widget_action_host.dart';
import 'widgets/home_screen/quick_expense_screen.dart';
import 'widgets/home_screen/manual_entry/expense_entry_popup.dart';
import 'widgets/home_screen/widget_data_refresh_host.dart';

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
    GoRoute(
      path: '/widgets/add',
      builder: (_, _) => const QuickExpenseScreen(record: false),
    ),
    GoRoute(
      path: '/widgets/entry',
      builder: (_, state) => ExpenseEntryPopup(
        focus: state.uri.queryParameters['focus'] ?? 'title',
      ),
    ),
    GoRoute(
      path: '/widgets/record',
      builder: (_, _) => const QuickExpenseScreen(record: true),
    ),
    GoRoute(path: '/data-share', builder: (_, _) => const DataShareScreen()),
    GoRoute(
      path: '/categories',
      pageBuilder: (context, state) {
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        return CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          reverseTransitionDuration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: const CategoriesScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              SlideTransition(
                position: animation.drive(
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeInOutCubic)),
                ),
                child: child,
              ),
        );
      },
    ),
    GoRoute(
      path: '/budget-planner',
      pageBuilder: (context, state) {
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        return CustomTransitionPage<void>(
          key: state.pageKey,
          transitionDuration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          reverseTransitionDuration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          child: const BudgetPlannerScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              SlideTransition(
                position: animation.drive(
                  Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeInOutCubic)),
                ),
                child: child,
              ),
        );
      },
    ),
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
          currency: ref.watch(preferencesProvider.select((p) => p.currency)),
          child: TooltipVisibility(
            visible: false,
            child: WidgetDataRefreshHost(
              child: HomeWidgetActionHost(
                router: _router,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
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
    body: AppNotificationHost(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: navigationShell,
        ),
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
