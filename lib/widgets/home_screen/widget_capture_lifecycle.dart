/// One active quick capture per app activity. Tokens prevent an old route's
/// disposal from clearing a newly opened capture during route replacement.
class HomeWidgetCapture {
  static Object? _active;
  static bool get isActive => _active != null;
  static void begin(Object token) => _active = token;
  static void finish(Object token) {
    if (identical(_active, token)) _active = null;
  }
}
