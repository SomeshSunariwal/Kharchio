package com.somesh.kharchio.widgets.subscriptions;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.util.Log;
import java.io.File;
import java.math.BigDecimal;
import java.text.NumberFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Currency;
import java.util.GregorianCalendar;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TimeZone;
import java.util.concurrent.TimeUnit;

final class SubscriptionWidgetData {
    static final class Row {
        final String id, name, amount;
        final int dueDay, daysLate;

        Row(Plan plan, int dueDay, int today) {
            id = plan.id;
            name = plan.name;
            NumberFormat format = NumberFormat.getCurrencyInstance(
                    "USD".equals(plan.currency) ? Locale.US : Locale.forLanguageTag("en-IN"));
            format.setCurrency(Currency.getInstance(plan.currency));
            format.setMinimumFractionDigits(plan.minor % 100 == 0 ? 0 : 2);
            amount = format.format(BigDecimal.valueOf(plan.minor, 2));
            this.dueDay = dueDay;
            daysLate = daysAfterDue(dueDay, today);
        }
    }

    private static final class Plan {
        final String id, name, currency;
        final long minor;
        final int anchor, interval;
        final Set<Integer> settled = new HashSet<>();

        Plan(Cursor row) {
            id = row.getString(0);
            name = row.getString(1);
            minor = row.getLong(2);
            currency = row.getString(3);
            anchor = row.getInt(4);
            interval = row.getInt(5);
        }
    }

    final Calendar today;
    final List<Row> rows;
    final boolean available;

    private SubscriptionWidgetData(Calendar today, List<Row> rows, boolean available) {
        this.today = today;
        this.rows = rows;
        this.available = available;
    }

    static SubscriptionWidgetData read(Context context) {
        Calendar today = new GregorianCalendar();
        int todayKey = dayKey(today);
        File file = new File(context.getDir("flutter", Context.MODE_PRIVATE), "kharchio.sqlite");
        if (!file.isFile()) return new SubscriptionWidgetData(today, Collections.emptyList(), false);
        String sql = "SELECT p.id, p.name, p.minor, p.currency_code, p.anchor_day, p.interval_months, r.due_day "
                + "FROM subscription_plans p LEFT JOIN subscription_renewals r ON r.plan_id = p.id "
                + "AND r.due_day >= p.anchor_day AND (r.expense_id IS NOT NULL OR r.skipped = 1) "
                + "WHERE p.active = 1 AND p.anchor_day <= ?";
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(file.getAbsolutePath(), null,
                SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS);
             Cursor cursor = db.rawQuery(sql, new String[] {Integer.toString(todayKey / 100 * 100 + 31)})) {
            Map<String, Plan> plans = new LinkedHashMap<>();
            while (cursor.moveToNext()) {
                String id = cursor.getString(0);
                Plan plan = plans.get(id);
                if (plan == null) {
                    plan = new Plan(cursor);
                    plans.put(id, plan);
                }
                if (!cursor.isNull(6)) plan.settled.add(cursor.getInt(6));
            }
            List<Row> rows = new ArrayList<>();
            for (Plan plan : plans.values()) {
                int due = visibleDueDay(plan.anchor, plan.interval, plan.settled, todayKey);
                if (due != 0) rows.add(new Row(plan, due, todayKey));
            }
            rows.sort(Comparator.comparingInt((Row row) -> row.dueDay)
                    .thenComparing(row -> row.name, String.CASE_INSENSITIVE_ORDER));
            return new SubscriptionWidgetData(today, rows, true);
        } catch (Exception error) {
            Log.w("KharchioWidgets", "Subscription widget could not read the ledger", error);
            return new SubscriptionWidgetData(today, Collections.emptyList(), false);
        }
    }

    static int visibleDueDay(int anchorDay, int interval, Set<Integer> settled, int today) {
        Calendar due = civilDate(anchorDay);
        int day = anchorDay;
        while (day / 100 <= today / 100) {
            if (!settled.contains(day)) return day;
            due.set(Calendar.DAY_OF_MONTH, 1);
            due.add(Calendar.MONTH, interval);
            due.set(Calendar.DAY_OF_MONTH, Math.min(anchorDay % 100, due.getActualMaximum(Calendar.DAY_OF_MONTH)));
            day = dayKey(due);
        }
        return 0;
    }

    static int daysAfterDue(int dueDay, int today) {
        return (int) TimeUnit.MILLISECONDS.toDays(
                civilDate(today).getTimeInMillis() - civilDate(dueDay).getTimeInMillis());
    }

    private static Calendar civilDate(int day) {
        Calendar date = new GregorianCalendar(TimeZone.getTimeZone("UTC"));
        date.clear();
        date.set(day / 10000, day / 100 % 100 - 1, day % 100);
        return date;
    }

    private static int dayKey(Calendar date) {
        return date.get(Calendar.YEAR) * 10000
                + (date.get(Calendar.MONTH) + 1) * 100 + date.get(Calendar.DAY_OF_MONTH);
    }
}
