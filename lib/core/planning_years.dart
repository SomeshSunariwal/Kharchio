/// Supported year range shared by analysis and monthly budget controls.
abstract final class PlanningYears {
  static const first = 2026;
  static const last = 2046;
  static final values = List<int>.unmodifiable([
    for (var year = first; year <= last; year++) year,
  ]);

  static bool contains(int year) => year >= first && year <= last;
  static int clamp(int year) => year.clamp(first, last);
}
