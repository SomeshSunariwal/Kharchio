package com.expense.kharchio.widgets.spending;

import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

/** Collection adapter fallback for Android versions before RemoteCollectionItems. */
public final class SpendingLegendService extends RemoteViewsService {
    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new Factory(getApplicationContext());
    }
    private static final class Factory implements RemoteViewsFactory {
        private final Context context;
        private SpendingData data;
        Factory(Context context) { this.context = context; }
        public void onCreate() { data = SpendingData.read(context); }
        public void onDataSetChanged() { data = SpendingData.read(context); }
        public void onDestroy() { data = null; }
        public int getCount() { return data == null ? 0 : data.categories.size(); }
        public RemoteViews getViewAt(int position) {
            return position >= 0 && position < getCount() ? SpendingWidget.row(context, data, data.categories.get(position)) : null;
        }
        public RemoteViews getLoadingView() { return null; }
        public int getViewTypeCount() { return 1; }
        public long getItemId(int position) { return data.categories.get(position).id.hashCode(); }
        public boolean hasStableIds() { return true; }
    }
}

