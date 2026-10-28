package com.expense.kharchio.widgets.spending;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;

/** Native donut matching the dashboard: slice percentages and a central total. */
final class SpendingPie {
    static Bitmap draw(SpendingData data, int size, int surface, int muted, int ink) {
        Bitmap bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        float center = size / 2f, radius = size * .3525f;
        RectF bounds = new RectF(center-radius, center-radius, center+radius, center+radius);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(size * .235f);
        if (data.total <= 0) {
            paint.setColor(muted); paint.setAlpha(35);
            canvas.drawOval(bounds, paint);
            paint.setAlpha(255);
        } else {
            float angle = -90;
            long[] values = new long[data.categories.size()];
            for (int i = 0; i < values.length; i++) values[i] = data.categories.get(i).minor;
            int[] percentages = SpendingPercentages.allocate(values);
            for (int i = 0; i < data.categories.size(); i++) {
                SpendingData.Category category = data.categories.get(i);
                float sweep = (float) (category.minor * 360.0 / data.total);
                float gap = data.categories.size() > 1 ? Math.min(.8f, sweep * .12f) : 0;
                paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(size * .235f);
                paint.setColor(category.color);
                canvas.drawArc(bounds, angle + gap / 2, sweep - gap, false, paint);
                if (category.minor * 100.0 / data.total >= 5) {
                    double middle = Math.toRadians(angle + sweep / 2);
                    paint.setStyle(Paint.Style.FILL);
                    paint.setColor(luminance(category.color) > .45 ? Color.rgb(11,22,56) : Color.WHITE);
                    paint.setTextAlign(Paint.Align.CENTER); paint.setTypeface(Typeface.DEFAULT_BOLD);
                    paint.setTextSize(size * .057f);
                    float x = center + (float)Math.cos(middle) * radius;
                    float y = center + (float)Math.sin(middle) * radius - (paint.ascent()+paint.descent())/2f;
                    canvas.drawText(percentages[i] + "%", x, y, paint);
                }
                angle += sweep;
            }
        }
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(surface);
        canvas.drawCircle(center, center, size * .233f, paint);
        paint.setTextAlign(Paint.Align.CENTER);
        paint.setColor(ink); paint.setTypeface(Typeface.DEFAULT);
        paint.setTextSize(size * .058f);
        text(canvas, paint, data.symbol(), center, center-size*.10f);
        paint.setTypeface(Typeface.DEFAULT_BOLD); paint.setTextSize(size*.095f);
        String total = data.chartTotal();
        float maxWidth = size*.40f;
        if (paint.measureText(total) > maxWidth) paint.setTextSize(paint.getTextSize()*maxWidth/paint.measureText(total));
        text(canvas, paint, total, center, center+size*.012f);
        paint.setTypeface(Typeface.DEFAULT); paint.setTextSize(size*.058f); paint.setColor(muted);
        text(canvas, paint, "Total", center, center+size*.12f);
        return bitmap;
    }
    private static void text(Canvas canvas, Paint paint, String value, float x, float y) {
        canvas.drawText(value, x, y-(paint.ascent()+paint.descent())/2f, paint);
    }
    private static double linear(int channel) {
        double value = channel / 255.0;
        return value <= .04045 ? value / 12.92 : Math.pow((value+.055)/1.055, 2.4);
    }
    private static double luminance(int color) {
        return .2126*linear(Color.red(color)) + .7152*linear(Color.green(color)) + .0722*linear(Color.blue(color));
    }
}
