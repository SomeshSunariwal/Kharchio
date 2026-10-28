# Kharchio home-screen widgets

This folder owns Flutter entry points, quick-capture UI, and capture persistence.
Native Android widget code and resources live in `android/app/src/main/widgets/`.
Widgets available: **Kharchio Quick Expense** (two actions), **Kharchio Add Expense** (a compact 2 by 1 button), and **Kharchio Spending Pie** (a 4 by 2 donut chart).

## Try it

1. Install the Android APK and open Kharchio once.
2. Long-press an empty area of the Android home screen, choose Widgets, and add
   **Kharchio Quick Expense**. Its initial grid size is 4 by 1, with a compact
   96 dp content height. The launcher controls the exact grid/cell dimensions.
   Existing widget placements retain their launcher size; resize or re-add the
   widget to apply the new default size.
3. Add Expense opens a small translucent form above the launcher, not the main
   app dashboard. Add Expense validates and writes to SQLite with the current
   date/time, then closes the popup and shows a confirmation toast.
4. Record Expense opens a compact recorder and starts after microphone permission
   and the selected speech model plus Qwen are available. Tap Stop to transcribe,
   extract and save automatically. There is no separate Create Cards or Save step.
5. The voice completion screen offers Undo, View expenses and Done. Undo atomically
   deletes only this capture's expense IDs. It remains available until you leave
   the capture screen or the process exits.

Missing models show the existing error UI and a button to open Offline AI settings.
Manual entry does not require models. Recording pauses when the app leaves the
foreground; closing the recorder cancels its jobs and releases the microphone.
The regular in-app recorder retains its review/create-cards workflow.

## Add Expense widget

Add **Kharchio Add Expense** from the widget picker. This second widget is a
compact 2 by 1 green Add Expense button. Tapping it opens the popup with the title
field focused. The popup contains the real fields and current category/currency
choices. Closing or tapping outside cancels without saving. Duplicate Add taps
cannot create duplicate expenses. Existing launcher placements may need to be
resized or re-added to apply the new default dimensions.

`ExpenseEntryActivity` runs in a separate, translucent task excluded from Recents.
It shares the existing Flutter entry point and SQLite repository, but displays
only the popup. Closing it returns to the previous home screen. No overlay
permission is requested. Since separate Flutter engines use separate Drift
connections, the main app refreshes its expenses when it resumes.

## Spending Pie widget

Add **Kharchio Spending Pie** from the widget picker. Its default size is 4 by 2:
donut with slice percentages and total spending in its centre on the left, scrollable category names and amounts on the right.
It uses the current device month, the selected app currency, and actual expense
amounts. Unused categories are omitted. Tiny slices are listed on the right but
omit in-pie labels to avoid overlap. Whole percentages use largest-remainder
rounding so their numeric shares total 100. An empty month shows a neutral donut,
a zero total and an empty-state message.

Native code is isolated under `widgets/spending/`. It opens the existing SQLite
ledger read-only on a worker thread and uses the persisted month links. It does
not start Flutter or load AI models just to update the widget. Updates are
requested when expenses, categories or currency change, explicitly before the
popup closes, on resize, and on the widget's periodic refresh. Android 12+ uses
RemoteCollectionItems; older Android uses a RemoteViewsService for the legend.

The widget picker preview is illustrative; installed widgets use real ledger data.

## Structure

- `widget_action_host.dart`: consumes cold-start actions and listens for warm
  actions from Android. Validates action IDs, ignores duplicate deliveries and
  preserves an active capture. Completed captures can be replaced by a new tap.
- `widget_capture_lifecycle.dart`: tracks an active capture with ownership tokens.
- `quick_expense_screen.dart`: shared manual/voice capture and completion/Undo UI.
- `manual_entry/expense_entry_popup.dart`: the compact current-time entry form.
- `widget_data_refresh_host.dart`: reloads expenses when the main app resumes.
- `quick_expense_batch.dart`: idempotent, atomic saving through LocalStore, fresh
  UUIDs, and batch-specific Undo. Normal month links and budget updates apply.
- `android/app/src/main/widgets/java/.../widgets/WidgetActionBridge.java`:
  method-channel handoff; pending cold actions survive Dart/database startup.
- `android/app/src/main/widgets/java/.../widgets/quickexpense/QuickExpenseWidget.java`:
  native RemoteViews provider with direct immutable activity PendingIntents.
- `android/app/src/main/widgets/res/`: prefixed layouts, drawables, strings,
  light/dark colors and widget-provider metadata.

MainActivity, AndroidManifest, Gradle source sets and app.dart contain only the
registration/handoff hooks. The existing expense form has an optional save
callback; the recorder has an optional extraction callback for quick saving.

## Adding another widget

Create a provider under a new `widgets/<widgetname>` Java package and prefix all
its resources with `widget_<widgetname>_`. Register it in AndroidManifest.xml.
Add its allowed action to WidgetActionBridge and widgetActionRoute, then implement
its Flutter screen under a sibling widget folder. Keep persistence through
LocalStore for writes. Display-only native widgets may read the existing SQLite
ledger using a read-only connection, as Spending Pie does.
Widget receivers should launch activities directly for capture actions.

## Verification

`test/widgets/` covers cold/warm dispatch, repeated taps, capture replacement,
manual and extracted-expense saving, month links, description preservation,
transaction rollback, idempotency and Undo without deleting unrelated expenses.
Popup tests cover current-time saving, cancellation and independent SQLite connections.
Screen voice tests inject extracted results; native microphone/model performance
must also be checked on the target phone with downloaded compatible models.
