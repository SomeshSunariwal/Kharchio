package com.somesh.kharchio.widgets.subscriptions;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.widget.RemoteViews;
import com.somesh.kharchio.MainActivity;
import com.somesh.kharchio.R;
import com.somesh.kharchio.SubscriptionReminderReceiver;
import com.somesh.kharchio.widgets.WidgetActionBridge;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class SubscriptionWidget extends AppWidgetProvider {
    private static final String REFRESH = "com.somesh.kharchio.widgets.REFRESH_SUBSCRIPTIONS";
    private static final ExecutorService WORKER = Executors.newSingleThreadExecutor();

    public static void requestRefresh(Context context) {
        ComponentName provider = new ComponentName(context, SubscriptionWidget.class);
        if (AppWidgetManager.getInstance(context).getAppWidgetIds(provider).length != 0) {
            context.sendBroadcast(new Intent(context, SubscriptionWidget.class).setAction(REFRESH));
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (REFRESH.equals(action) || Intent.ACTION_TIMEZONE_CHANGED.equals(action)
                || Intent.ACTION_TIME_CHANGED.equals(action)) {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            onUpdate(context, manager, manager.getAppWidgetIds(new ComponentName(context, SubscriptionWidget.class)));
        } else {
            super.onReceive(context, intent);
        }
    }

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        if (ids.length == 0) return;
        PendingResult pending = goAsync();
        Context app = context.getApplicationContext();
        WORKER.execute(() -> {
            try {
                SubscriptionWidgetData data = SubscriptionWidgetData.read(app);
                for (int id : ids) update(app, manager, id, data);
            } catch (Exception error) {
                Log.w("KharchioWidgets", "Subscription widget refresh failed", error);
            } finally {
                pending.finish();
            }
        });
    }

    private static void update(Context context, AppWidgetManager manager, int id, SubscriptionWidgetData data) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_subscriptions);
        SimpleDateFormat month = new SimpleDateFormat("MMM yyyy", Locale.getDefault());
        month.setCalendar((Calendar) data.today.clone());
        views.setTextViewText(R.id.widget_subscriptions_month, month.format(data.today.getTime()));
        views.setTextViewText(R.id.widget_subscriptions_empty, context.getString(data.available
                ? R.string.widget_subscriptions_empty : R.string.widget_subscriptions_setup));
        views.setEmptyView(R.id.widget_subscriptions_rows, R.id.widget_subscriptions_empty);
        if (Build.VERSION.SDK_INT >= 31) {
            RemoteViews.RemoteCollectionItems.Builder items = new RemoteViews.RemoteCollectionItems.Builder()
                    .setViewTypeCount(1);
            for (int index = 0; index < data.rows.size(); index++) {
                items.addItem(index, row(context, data.rows.get(index)));
            }
            views.setRemoteAdapter(R.id.widget_subscriptions_rows, items.build());
        } else {
            Intent adapter = new Intent(context, SubscriptionWidgetService.class)
                    .setData(Uri.parse("kharchio-widget://subscriptions/" + id))
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id);
            views.setRemoteAdapter(R.id.widget_subscriptions_rows, adapter);
        }
        Intent openPlanner = new Intent(context, MainActivity.class).setAction(Intent.ACTION_MAIN)
                .putExtra(WidgetActionBridge.EXTRA_ACTION, "subscriptions")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        PendingIntent planner = PendingIntent.getActivity(context, 530, openPlanner,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_subscriptions_header, planner);
        views.setOnClickPendingIntent(R.id.widget_subscriptions_empty, planner);
        Intent openRenewal = SubscriptionReminderReceiver.openRenewalIntent(context);
        PendingIntent renewal = PendingIntent.getActivity(context, 531, openRenewal,
                PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0));
        views.setPendingIntentTemplate(R.id.widget_subscriptions_rows, renewal);
        manager.updateAppWidget(id, views);
        if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(id, R.id.widget_subscriptions_rows);
    }

    static RemoteViews row(Context context, SubscriptionWidgetData.Row payment) {
        RemoteViews row = new RemoteViews(context.getPackageName(), R.layout.widget_subscriptions_row);
        int days = Math.abs(payment.daysLate);
        String remaining = days == 0 ? context.getString(R.string.widget_subscriptions_today)
                : context.getResources().getQuantityString(R.plurals.widget_subscriptions_days, days,
                        payment.daysLate > 0 ? "+" : "−", days);
        row.setTextViewText(R.id.widget_subscriptions_name, payment.name);
        row.setTextViewText(R.id.widget_subscriptions_amount, payment.amount);
        row.setTextViewText(R.id.widget_subscriptions_days, remaining);
        row.setTextColor(R.id.widget_subscriptions_days, context.getColor(payment.daysLate > 0
                ? R.color.widget_quick_record_ink : R.color.widget_quick_ink));
        row.setOnClickFillInIntent(R.id.widget_subscriptions_row, new Intent()
                .putExtra("planId", payment.id).putExtra("dueDay", payment.dueDay));
        return row;
    }
}
