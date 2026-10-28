package com.expense.kharchio.widgets.manualexpense;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.widget.RemoteViews;
import com.expense.kharchio.R;

/** Compact 2-by-1 Add Expense button opening the quick-entry popup. */
public final class ExpenseFormWidget extends AppWidgetProvider {
    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        for (int id : ids) {
            RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_expense_form);
            views.setOnClickPendingIntent(R.id.widget_form_add, ExpenseEntryActivity.pendingIntent(context, "title"));
            manager.updateAppWidget(id, views);
        }
    }
}

