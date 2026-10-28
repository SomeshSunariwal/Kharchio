package com.expense.kharchio.widgets.spending;

import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.util.Log;
import java.io.File;
import java.math.BigDecimal;
import java.text.NumberFormat;
import java.util.Locale;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.List;

/** Read-only access to the same ledger used by Flutter; never creates/migrates it. */
final class SpendingData {
    static final class Category {
        final String id, name;
        final int color;
        final long minor;
        Category(String id, String name, int color, long minor) {
            this.id = id; this.name = name; this.color = color; this.minor = minor;
        }
    }
    final List<Category> categories;
    final long total;
    final Calendar month;
    final boolean available;
    private final String currency;
    private final NumberFormat amounts;
    SpendingData(List<Category> categories, long total, Calendar month, boolean available, String currency) {
        this.categories = Collections.unmodifiableList(categories);
        this.total = total; this.month = month; this.available = available;
        amounts = NumberFormat.getNumberInstance("USD".equals(currency) ? Locale.US : Locale.forLanguageTag("en-IN"));
        amounts.setMinimumFractionDigits(2);
        amounts.setMaximumFractionDigits(2);
        this.currency = currency;
    }
    static SpendingData read(Context context) {
        Calendar month = Calendar.getInstance();
        File file = new File(context.getDir("flutter", Context.MODE_PRIVATE), "kharchio.sqlite");
        if (!file.isFile()) return new SpendingData(new ArrayList<>(), 0, month, false, "INR");
        try (SQLiteDatabase db = SQLiteDatabase.openDatabase(file.getAbsolutePath(), null,
                SQLiteDatabase.OPEN_READONLY | SQLiteDatabase.NO_LOCALIZED_COLLATORS)) {
            String currency = "INR";
            try (Cursor settings = db.rawQuery("SELECT value FROM app_settings WHERE key = 'default_currency'", null)) {
                if (settings.moveToFirst() && "USD".equals(settings.getString(0))) currency = "USD";
            }
            List<Category> categories = new ArrayList<>();
            long total = 0;
            String sql = "SELECT c.id, c.name, c.color_value, SUM(e.minor) AS spent "
                + "FROM expenses e JOIN categories c ON c.id = e.category_id "
                + "JOIN monthly_budgets m ON m.id = e.month_id "
                + "WHERE m.year = ? AND m.month = ? AND e.currency_code = ? "
                + "GROUP BY c.id, c.name, c.color_value HAVING spent > 0 ORDER BY spent DESC, c.name";
            String[] args = { Integer.toString(month.get(Calendar.YEAR)), Integer.toString(month.get(Calendar.MONTH) + 1), currency };
            try (Cursor rows = db.rawQuery(sql, args)) {
                while (rows.moveToNext()) {
                    long amount = rows.getLong(3);
                    categories.add(new Category(rows.getString(0), rows.getString(1), (int) rows.getLong(2), amount));
                    total += amount;
                }
            }
            return new SpendingData(categories, total, month, true, currency);
        } catch (Exception error) {
            Log.w("KharchioWidgets", "Spending widget could not read the ledger", error);
            return new SpendingData(new ArrayList<>(), 0, month, false, "INR");
        }
    }
    String symbol() { return "USD".equals(currency) ? "$" : "\u20b9"; }
    String chartTotal() {
        NumberFormat format = (NumberFormat) amounts.clone();
        format.setMinimumFractionDigits(0);
        return format.format(BigDecimal.valueOf(total, 2));
    }
    String amount(long minor) {
        return ("USD".equals(currency) ? "$ " : "₹ ") + amounts.format(BigDecimal.valueOf(minor, 2));
    }
}
