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
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Captures likely payments without starting Flutter or running AI. */
public class PaymentNotificationListener extends NotificationListenerService {
    private static final String PREFS = "payment_notification_drafts";
    private static final String QUEUE = "pending";
    private static final String REVIEWED = "reviewed";
    private static final String CHANNEL = "payment_review";
    private static final String ALERT_GROUP = "payment_reviews";
    private static final String GROUP_TAP = "@group";
    private static final int REVIEW_ALERT_ID = 1;
    private static final int REVIEW_SUMMARY_ID = 2;
    static final String ACTION_PREFIX = "com.somesh.kharchio.REVIEW_PAYMENT.";
    private static final long MAX_AGE = 7 * 24 * 60 * 60 * 1000L;
    private static final Pattern AMOUNT = Pattern.compile(
            "(₹|\\$|\\b(?:INR|USD|Rs\\.?))\\s*(\\d[\\d,]*(?:\\.\\d{1,2})?)(?![\\d,.]\\d|\\d)",
            Pattern.CASE_INSENSITIVE);
    // Match the timestamp format understood by the Dart payment parser.
    private static final Pattern PAYMENT_TIMESTAMP = Pattern.compile(
            "\\b\\d{4}-\\d{2}-\\d{2}[: T]\\d{2}:\\d{2}:\\d{2}\\b");
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
        Set<String> seenPayments = new HashSet<>();
        for (int i = 0; i < queue.length();) {
            JSONObject item = queue.optJSONObject(i);
            boolean expired = item == null
                    || System.currentTimeMillis() - item.optLong("postedAt") > MAX_AGE;
            String paymentId = expired ? null : paymentFingerprint(item.optString("text"));
            if (expired || (paymentId != null && !seenPayments.add(paymentId))) {
                if (item != null) manager.cancel(item.optString("id"), REVIEW_ALERT_ID);
                queue.remove(i);
                changed = true;
            } else {
                i++;
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
            String paymentId = paymentFingerprint(item.optString("text"));
            if (paymentId != null && !paymentId.equals(itemId)) {
                reviewed.put(outcome + ":" + fingerprint(paymentId));
            }
            resolved.add(itemId);
        }
        if (resolved.isEmpty()) return 0;
        while (reviewed.length() > 128) reviewed.remove(0);
        prefs.edit().putString(QUEUE, remaining.toString())
                .putString(REVIEWED, reviewed.toString()).apply();
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        for (String itemId : resolved) manager.cancel(itemId, REVIEW_ALERT_ID);
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

    private static String paymentFingerprint(String text) {
        Matcher timestamp = PAYMENT_TIMESTAMP.matcher(text);
        Matcher amount = AMOUNT.matcher(text);
        if (!timestamp.find() || !amount.find()) return null;
        String marker = amount.group(1);
        String currency = "USD".equalsIgnoreCase(marker) || "$".equals(marker) ? "USD" : "INR";
        String value = new BigDecimal(amount.group(2).replace(",", "")).stripTrailingZeros().toPlainString();
        String dateTime = timestamp.group();
        dateTime = dateTime.substring(0, 10) + " " + dateTime.substring(11);
        return fingerprint("payment\n" + currency + "\n" + value + "\n" + dateTime);
    }

    @Override
    public void onNotificationPosted(StatusBarNotification notification) {
        Notification source = notification.getNotification();
        if (getPackageName().equals(notification.getPackageName())) {
            if (isReviewAlert(notification)) refreshReviewSummary();
            return;
        }
        if ((source.flags & Notification.FLAG_GROUP_SUMMARY) != 0) return;
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
        String deliveryId = fingerprint(notification.getKey() + "\n" + messageTime + "\n" + text);
        String paymentId = paymentFingerprint(text);
        String id = paymentId == null ? deliveryId : paymentId;
        for (int i = 0; i < queue.length(); i++) {
            JSONObject item = queue.optJSONObject(i);
            if (id.equals(item.optString("id"))
                    || (paymentId != null && paymentId.equals(paymentFingerprint(item.optString("text"))))) return;
        }
        JSONArray reviewed = read(prefs, REVIEWED);
        String suffix = ":" + fingerprint(id);
        String deliverySuffix = id.equals(deliveryId) ? suffix : ":" + fingerprint(deliveryId);
        for (int i = 0; i < reviewed.length(); i++) {
            String entry = reviewed.optString(i);
            if (entry.endsWith(suffix) || entry.endsWith(deliverySuffix)) return;
        }
        try {
            queue.put(new JSONObject().put("id", id).put("text", text)
                    .put("source", notification.getPackageName())
                    .put("postedAt", notification.getPostTime()));
            NotificationManager manager = getSystemService(NotificationManager.class);
            while (queue.length() > 30) {
                JSONObject expired = (JSONObject) queue.remove(0);
                manager.cancel(expired.optString("id"), REVIEW_ALERT_ID);
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
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL, "Payment reviews", NotificationManager.IMPORTANCE_DEFAULT);
            channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
            manager.createNotificationChannel(channel);
        }
        manager.notify(id, REVIEW_ALERT_ID, reviewBuilder()
                .setContentTitle("Possible expense detected")
                .setContentText("Tap to review in Kharchio")
                .setAutoCancel(true)
                .setContentIntent(reviewTap(id))
                .addAction(0, "Review all", reviewTap(GROUP_TAP))
                .build());
    }

    @Override
    public void onListenerConnected() {
        refreshReviewSummary();
    }

    @Override
    public void onNotificationRemoved(StatusBarNotification notification) {
        if (getPackageName().equals(notification.getPackageName()) && isReviewAlert(notification)) {
            refreshReviewSummary();
        }
    }

    private static boolean isReviewAlert(StatusBarNotification notification) {
        return notification.getId() == REVIEW_ALERT_ID && notification.getTag() != null
                && ALERT_GROUP.equals(notification.getNotification().getGroup());
    }

    private void refreshReviewSummary() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        int count = 0;
        String lastId = null;
        boolean hasSummary = false;
        for (StatusBarNotification alert : manager.getActiveNotifications()) {
            if (isReviewAlert(alert)) {
                count++;
                lastId = alert.getTag();
            } else if (alert.getId() == REVIEW_SUMMARY_ID && alert.getTag() == null) {
                hasSummary = true;
            }
        }
        if (count == 0) {
            if (hasSummary) manager.cancel(REVIEW_SUMMARY_ID);
            return;
        }
        // Canceling a summary can also dismiss its children. If only one is left,
        // keep the existing summary and point it at that draft.
        if (count == 1 && !hasSummary) return;
        NotificationCompat.Builder summary = reviewBuilder()
                .setGroupSummary(true)
                .setContentTitle(count == 1 ? "Possible expense detected" : "Review detected expenses")
                .setContentText(count == 1 ? "Tap to review in Kharchio" : count + " expenses to review")
                .setContentIntent(reviewTap(count == 1 ? lastId : GROUP_TAP));
        if (count > 1) summary.addAction(0, "Review all", reviewTap(GROUP_TAP));
        manager.notify(REVIEW_SUMMARY_ID, summary.build());
    }

    private NotificationCompat.Builder reviewBuilder() {
        return new NotificationCompat.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setGroup(ALERT_GROUP)
                .setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_CHILDREN);
    }

    private PendingIntent reviewTap(String id) {
        Intent intent = new Intent(this, MainActivity.class)
                .setAction(ACTION_PREFIX + id)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE);
    }
}
