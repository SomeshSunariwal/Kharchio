package com.somesh.kharchio;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;
import android.service.notification.NotificationListenerService;
import android.service.notification.StatusBarNotification;
import androidx.core.app.NotificationCompat;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.Consumer;
import java.util.regex.Pattern;

/** Captures likely payments without starting Flutter or running AI. */
public class PaymentNotificationListener extends NotificationListenerService {
    private static final String PREFS = "payment_notification_drafts";
    private static final String QUEUE = "pending";
    private static final String REVIEWED = "reviewed";
    private static final String CHANNEL = "payment_review";
    static final String ACTION_PREFIX = "com.somesh.kharchio.REVIEW_PAYMENT.";
    private static final long MAX_AGE = 7 * 24 * 60 * 60 * 1000L;
    private static final Pattern AMOUNT = Pattern.compile("(?:[₹$]|\\b(?:INR|USD|Rs\\.?))\\s*\\d", Pattern.CASE_INSENSITIVE);
    private static final Pattern SPEND = Pattern.compile(
            "\\b(?:spent|debited|paid|payment (?:of|done|successful)|sent|transferred|purchase|charged)\\b",
            Pattern.CASE_INSENSITIVE);
    private static final Pattern EXCLUDE = Pattern.compile(
            "\\b(?:credited|received|refund(?:ed)?|reversal|reversed|cashback|failed|declined|unsuccessful|pending|otp|one.time password|collect request|payment request|request(?:ed)? (?:for|to|money)|pay now)\\b",
            Pattern.CASE_INSENSITIVE);
    static Consumer<String> foregroundReview;

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static JSONArray read(SharedPreferences prefs, String key) {
        try {
            return new JSONArray(prefs.getString(key, "[]"));
        } catch (JSONException ignored) {
            return new JSONArray();
        }
    }

    static JSONArray pending(Context context) {
        SharedPreferences prefs = preferences(context);
        JSONArray queue = read(prefs, QUEUE);
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        boolean changed = false;
        for (int i = queue.length() - 1; i >= 0; i--) {
            JSONObject item = queue.optJSONObject(i);
            if (item == null || System.currentTimeMillis() - item.optLong("postedAt") > MAX_AGE) {
                if (item != null) manager.cancel(item.optString("id"), 1);
                queue.remove(i);
                changed = true;
            }
        }
        if (changed) prefs.edit().putString(QUEUE, queue.toString()).apply();
        return queue;
    }

    static void resolve(Context context, String id, String outcome) {
        resolveMatching(context, id, outcome);
    }

    static int clearPending(Context context) {
        return resolveMatching(context, null, "dismissed");
    }

    private static int resolveMatching(Context context, String id, String outcome) {
        SharedPreferences prefs = preferences(context);
        JSONArray queue = pending(context);
        JSONArray remaining = new JSONArray();
        JSONArray reviewed = read(prefs, REVIEWED);
        List<String> resolved = new ArrayList<>();
        for (int i = 0; i < queue.length(); i++) {
            JSONObject item = queue.optJSONObject(i);
            String itemId = item.optString("id");
            if (id != null && !id.equals(itemId)) {
                remaining.put(item);
                continue;
            }
            reviewed.put(outcome + ":" + fingerprint(itemId));
            resolved.add(itemId);
        }
        if (resolved.isEmpty()) return 0;
        while (reviewed.length() > 128) reviewed.remove(0);
        prefs.edit().putString(QUEUE, remaining.toString())
                .putString(REVIEWED, reviewed.toString()).apply();
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        for (String itemId : resolved) manager.cancel(itemId, 1);
        return resolved.size();
    }

    private static String fingerprint(String value) {
        try {
            byte[] bytes = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            return android.util.Base64.encodeToString(bytes,
                    android.util.Base64.URL_SAFE | android.util.Base64.NO_PADDING | android.util.Base64.NO_WRAP);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException(error);
        }
    }

    @Override
    public void onNotificationPosted(StatusBarNotification notification) {
        Notification source = notification.getNotification();
        if (getPackageName().equals(notification.getPackageName())
                || (source.flags & Notification.FLAG_GROUP_SUMMARY) != 0) return;
        Bundle extras = source.extras;
        if (extras == null) return;
        long messageTime = source.when > 0 ? source.when : notification.getPostTime();
        CharSequence body = null;
        NotificationCompat.MessagingStyle conversation =
                NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(source);
        if (conversation != null) {
            List<NotificationCompat.MessagingStyle.Message> messages = conversation.getMessages();
            if (!messages.isEmpty()) {
                NotificationCompat.MessagingStyle.Message latest = messages.get(messages.size() - 1);
                body = latest.getText();
                if (latest.getTimestamp() > 0) messageTime = latest.getTimestamp();
            }
        }
        if (body == null) body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT);
        if (body == null) body = extras.getCharSequence(Notification.EXTRA_TEXT);
        if (body == null) return;
        String text = body.toString().trim();
        if (conversation == null && !SPEND.matcher(text).find()) {
            CharSequence title = extras.getCharSequence(Notification.EXTRA_TITLE);
            if (title != null && SPEND.matcher(title).find()) text = title + " " + text;
        }
        if (text.length() > 2000 || !AMOUNT.matcher(text).find()
                || !SPEND.matcher(text).find() || EXCLUDE.matcher(text).find()) return;
        SharedPreferences prefs = preferences(this);
        JSONArray queue = pending(this);
        String id = fingerprint(notification.getKey() + "\n" + messageTime + "\n" + text);
        for (int i = 0; i < queue.length(); i++) {
            if (id.equals(queue.optJSONObject(i).optString("id"))) return;
        }
        JSONArray reviewed = read(prefs, REVIEWED);
        String suffix = ":" + fingerprint(id);
        for (int i = 0; i < reviewed.length(); i++) {
            if (reviewed.optString(i).endsWith(suffix)) return;
        }
        try {
            queue.put(new JSONObject().put("id", id).put("text", text)
                    .put("source", notification.getPackageName())
                    .put("postedAt", notification.getPostTime()));
            NotificationManager manager = getSystemService(NotificationManager.class);
            while (queue.length() > 30) {
                JSONObject expired = (JSONObject) queue.remove(0);
                manager.cancel(expired.optString("id"), 1);
            }
            prefs.edit().putString(QUEUE, queue.toString()).apply();
            if (foregroundReview != null) foregroundReview.accept(id);
            else showReview(manager, id);
        } catch (JSONException ignored) {
            // Leave the existing queue intact if the new item cannot be encoded.
        }
    }

    private void showReview(NotificationManager manager, String id) {
        if (!manager.areNotificationsEnabled()) return;
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(
                android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) return;
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL, "Payment reviews", NotificationManager.IMPORTANCE_DEFAULT);
            channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
            manager.createNotificationChannel(channel);
            builder = new Notification.Builder(this, CHANNEL);
        } else {
            builder = new Notification.Builder(this);
        }
        Intent intent = new Intent(this, MainActivity.class)
                .setAction(ACTION_PREFIX + id)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent tap = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE);
        manager.notify(id, 1, builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Possible expense detected")
                .setContentText("Tap to review in Kharchio")
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true).setContentIntent(tap).build());
    }
}
