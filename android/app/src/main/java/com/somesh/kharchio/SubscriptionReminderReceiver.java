package com.somesh.kharchio;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import java.util.Calendar;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public final class SubscriptionReminderReceiver extends BroadcastReceiver {
    static final String OPEN = "com.somesh.kharchio.OPEN_SUBSCRIPTION";
    private static final String ALARM = "com.somesh.kharchio.SUBSCRIPTION_ALARM";
    private static final String CHANNEL = "subscription_renewals";
    private static final long DELIVERY_WINDOW = 12 * 60 * 60 * 1000L;

    public static Intent openRenewalIntent(Context context) {
        return new Intent(context, MainActivity.class).setAction(OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(CHANNEL, Context.MODE_PRIVATE);
    }

    static void replace(Context context, String schedule) throws JSONException {
        SharedPreferences prefs = preferences(context);
        JSONArray previous = new JSONArray(prefs.getString("schedule", "[]"));
        Map<String, Long> scheduled = new HashMap<>();
        for (int i = 0; i < previous.length(); i++) {
            JSONObject reminder = previous.getJSONObject(i);
            scheduled.put(reminder.getString("id"), time(reminder));
        }
        long now = System.currentTimeMillis();
        JSONArray incoming = new JSONArray(schedule);
        JSONArray reminders = new JSONArray();
        for (int i = 0; i < incoming.length(); i++) {
            JSONObject reminder = incoming.getJSONObject(i);
            long when = time(reminder);
            // Only previously scheduled alarms can be delivered after their target time.
            if (when > now || scheduled.getOrDefault(reminder.getString("id"), 0L) == when) {
                reminders.put(reminder);
            }
        }
        Set<String> fired = new HashSet<>(prefs.getStringSet("fired", Collections.emptySet()));
        Calendar cutoff = Calendar.getInstance();
        cutoff.add(Calendar.YEAR, -1);
        int oldest = cutoff.get(Calendar.YEAR) * 10000
                + (cutoff.get(Calendar.MONTH) + 1) * 100 + cutoff.get(Calendar.DAY_OF_MONTH);
        fired.removeIf(id -> {
            String[] parts = id.split(":");
            return parts.length != 3 || Integer.parseInt(parts[1]) < oldest;
        });
        scheduleNext(context, reminders, fired);
        prefs.edit().putString("schedule", reminders.toString()).putStringSet("fired", fired).apply();
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        SharedPreferences prefs = preferences(context);
        try {
            JSONArray reminders = new JSONArray(prefs.getString("schedule", "[]"));
            Set<String> fired = new HashSet<>(prefs.getStringSet("fired", Collections.emptySet()));
            if (scheduleNext(context, reminders, fired)) {
                prefs.edit().putStringSet("fired", fired).apply();
            }
        } catch (JSONException error) {
            android.util.Log.w(CHANNEL, "Could not load subscription reminders", error);
        }
    }

    private static long time(JSONObject reminder) throws JSONException {
        Calendar date = Calendar.getInstance();
        date.clear();
        date.set(reminder.getInt("year"), reminder.getInt("month") - 1,
                reminder.getInt("day"), reminder.getInt("hour"), reminder.getInt("minute"));
        return date.getTimeInMillis();
    }

    private static boolean scheduleNext(Context context, JSONArray reminders,
                                        Set<String> fired) throws JSONException {
        long now = System.currentTimeMillis();
        long next = Long.MAX_VALUE;
        boolean delivered = false;
        for (int i = 0; i < reminders.length(); i++) {
            JSONObject reminder = reminders.getJSONObject(i);
            if (fired.contains(reminder.getString("id"))) continue;
            long when = time(reminder);
            if (when > now) {
                next = Math.min(next, when);
            } else if (now - when < DELIVERY_WINDOW) {
                fired.add(reminder.getString("id"));
                show(context, reminder);
                delivered = true;
            }
        }
        Intent alarm = new Intent(context, SubscriptionReminderReceiver.class).setAction(ALARM);
        PendingIntent pending = PendingIntent.getBroadcast(context, 0, alarm,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        AlarmManager manager = context.getSystemService(AlarmManager.class);
        if (next == Long.MAX_VALUE) {
            manager.cancel(pending);
        } else if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()) {
            try {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending);
            } catch (SecurityException denied) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending);
            }
        } else {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending);
        }
        return delivered;
    }

    private static void show(Context context, JSONObject reminder) throws JSONException {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (!manager.areNotificationsEnabled()) return;
        Notification.Builder notification;
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(new NotificationChannel(
                    CHANNEL, "Subscription reminders", NotificationManager.IMPORTANCE_DEFAULT));
            notification = new Notification.Builder(context, CHANNEL);
        } else {
            notification = new Notification.Builder(context);
        }
        String id = reminder.getString("id");
        Intent open = openRenewalIntent(context)
                .setData(Uri.fromParts("kharchio-subscription", id, null))
                .putExtra("planId", reminder.getString("planId"))
                .putExtra("dueDay", reminder.getInt("dueDay"));
        PendingIntent content = PendingIntent.getActivity(context, 0, open,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        String message = reminder.getString("message");
        manager.notify(id, 1, notification.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Subscription reminder").setContentText(message)
                .setStyle(new Notification.BigTextStyle().bigText(message))
                .setContentIntent(content).setAutoCancel(true).build());
    }
}
