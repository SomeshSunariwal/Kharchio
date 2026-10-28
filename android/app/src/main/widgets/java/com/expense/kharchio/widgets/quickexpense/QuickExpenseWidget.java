package com.expense.kharchio.widgets.quickexpense;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import com.expense.kharchio.MainActivity;
import com.expense.kharchio.R;
import com.expense.kharchio.widgets.WidgetActionBridge;
import com.expense.kharchio.widgets.manualexpense.ExpenseEntryActivity;

/** Stateless launcher widget; Flutter owns recording, validation and SQLite. */
public final class QuickExpenseWidget extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_quick_expense);
            views.setOnClickPendingIntent(R.id.widget_quick_add, ExpenseEntryActivity.pendingIntent(context, "title"));
            views.setOnClickPendingIntent(R.id.widget_quick_record, action(context, "record", 101));
            manager.updateAppWidget(id, views);
        }
    }

    private static PendingIntent action(Context context, String action, int requestCode) {
        Intent intent = new Intent(context, MainActivity.class)
            .setAction("com.expense.kharchio.widget." + action)
            .putExtra(WidgetActionBridge.EXTRA_ACTION, action)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
