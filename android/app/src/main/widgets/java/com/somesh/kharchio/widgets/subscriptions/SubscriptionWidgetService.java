package com.somesh.kharchio.widgets.subscriptions;

import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

public final class SubscriptionWidgetService extends RemoteViewsService {
    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        Context context = getApplicationContext();
        return new RemoteViewsFactory() {
            private SubscriptionWidgetData data;

            @Override public void onCreate() { }
            @Override public void onDataSetChanged() { data = SubscriptionWidgetData.read(context); }
            @Override public void onDestroy() { data = null; }
            @Override public int getCount() { return data == null ? 0 : data.rows.size(); }
            @Override public RemoteViews getViewAt(int position) {
                return position >= 0 && position < getCount()
                        ? SubscriptionWidget.row(context, data.rows.get(position)) : null;
            }
            @Override public RemoteViews getLoadingView() { return null; }
            @Override public int getViewTypeCount() { return 1; }
            @Override public long getItemId(int position) { return position; }
            @Override public boolean hasStableIds() { return false; }
        };
    }
}
