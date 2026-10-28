package com.expense.kharchio.widgets.spending;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.util.Log;
import android.widget.RemoteViews;
import com.expense.kharchio.MainActivity;
import com.expense.kharchio.R;
import java.text.SimpleDateFormat;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Current-month spending: pie left, scrollable category amounts right. */
public final class SpendingWidget extends AppWidgetProvider {
    private static final String REFRESH = "com.expense.kharchio.widgets.REFRESH_SPENDING";
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();
    public static void requestRefresh(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, SpendingWidget.class));
        if (ids.length > 0) context.sendBroadcast(new Intent(context, SpendingWidget.class).setAction(REFRESH));
    }
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (REFRESH.equals(action) || AppWidgetManager.ACTION_APPWIDGET_UPDATE.equals(action)
                || AppWidgetManager.ACTION_APPWIDGET_OPTIONS_CHANGED.equals(action)) {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] requested = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS);
            int id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID);
            final int[] ids = requested != null ? requested : id != AppWidgetManager.INVALID_APPWIDGET_ID
                ? new int[] {id} : manager.getAppWidgetIds(new ComponentName(context, SpendingWidget.class));
            final PendingResult pending = goAsync();
            final Context app = context.getApplicationContext();
            WORKER.execute(() -> {
                try {
                    SpendingData data = SpendingData.read(app);
                    for (int widgetId : ids) update(app, manager, widgetId, data);
                } catch (Exception error) {
                    Log.w("KharchioWidgets", "Spending widget refresh failed", error);
                } finally { pending.finish(); }
            });
        } else { super.onReceive(context, intent); }
    }
    private static void update(Context context, AppWidgetManager manager, int id, SpendingData data) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_spending_chart);
        views.setTextViewText(R.id.widget_spending_title, new SimpleDateFormat("MMM yyyy", Locale.getDefault()).format(data.month.getTime()));
        Bundle options = manager.getAppWidgetOptions(id);
        int width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 280);
        int height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160);
        float density = context.getResources().getDisplayMetrics().density;
        int size = Math.max(160, Math.min(600, Math.round(Math.max(64, Math.min(160, Math.min(height-44, width*.43f))) * density)));
        views.setImageViewBitmap(R.id.widget_spending_pie, SpendingPie.draw(data, size,
            context.getColor(R.color.widget_quick_surface), context.getColor(R.color.widget_quick_muted), context.getColor(R.color.widget_quick_ink)));
        views.setContentDescription(R.id.widget_spending_pie, data.total > 0 ? context.getString(R.string.widget_spending_pie_description) : context.getString(R.string.widget_spending_empty));
        views.setTextViewText(R.id.widget_spending_empty, context.getString(data.available ? R.string.widget_spending_empty : R.string.widget_spending_open_app));
        views.setEmptyView(R.id.widget_spending_legend, R.id.widget_spending_empty);
        if (Build.VERSION.SDK_INT >= 31) {
            RemoteViews.RemoteCollectionItems.Builder items = new RemoteViews.RemoteCollectionItems.Builder().setHasStableIds(true).setViewTypeCount(1);
            for (SpendingData.Category category : data.categories) {
                items.addItem(category.id.hashCode(), row(context, data, category));
            }
            views.setRemoteAdapter(R.id.widget_spending_legend, items.build());
        } else {
            Intent adapter = new Intent(context, SpendingLegendService.class)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .setData(Uri.parse("kharchio-widget://spending/"+id));
            views.setRemoteAdapter(R.id.widget_spending_legend, adapter);
        }
        Intent open = new Intent(context, MainActivity.class).setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        views.setOnClickPendingIntent(R.id.widget_spending_header, PendingIntent.getActivity(context, 500, open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        manager.updateAppWidget(id, views);
        if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(id, R.id.widget_spending_legend);
    }
    static RemoteViews row(Context context, SpendingData data, SpendingData.Category category) {
        RemoteViews row = new RemoteViews(context.getPackageName(), R.layout.widget_spending_legend_row);
        row.setTextViewText(R.id.widget_spending_category, category.name);
        row.setTextViewText(R.id.widget_spending_amount, data.amount(category.minor));
        row.setTextColor(R.id.widget_spending_dot, category.color);
        row.setContentDescription(R.id.widget_spending_category, category.name+", "+data.amount(category.minor));
        return row;
    }
}

