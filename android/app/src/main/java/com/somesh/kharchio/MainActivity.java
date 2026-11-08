package com.somesh.kharchio;

import android.content.SharedPreferences;
import android.content.Intent;
import android.content.ComponentName;
import android.app.NotificationManager;
import android.os.Build;
import android.provider.Settings;
import com.somesh.kharchio.sharing.LocalShareBridge;
import com.somesh.kharchio.widgets.WidgetActionBridge;
import java.util.HashMap;
import java.util.Map;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Launcher activity: starts Dart main() and connects native Android services. */
public class MainActivity extends FlutterActivity {
    private static final String SETTINGS_CHANNEL = "com.somesh.kharchio/settings";
    private static final String PAYMENTS_CHANNEL = "com.somesh.kharchio/payment_notifications";
    private static final int PAYMENT_ALERT_PERMISSION = 4912;
    private static final String THEME_KEY = "appearance.themeMode";
    private MethodChannel settingsChannel;
    private MethodChannel paymentsChannel;
    private final java.util.function.Consumer<String> foregroundPayment = id -> {
        if (paymentsChannel != null) paymentsChannel.invokeMethod("paymentDetected", id);
    };
    private ModelAssetBridge modelAssets;
    private WidgetActionBridge widgetActions;
    private LocalShareBridge localShare;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        widgetActions = new WidgetActionBridge(this, flutterEngine);
        localShare = new LocalShareBridge(this, flutterEngine);
        modelAssets = new ModelAssetBridge(getApplicationContext(), flutterEngine);
        SharedPreferences settings = ((KharchioApplication) getApplication()).getSettings();
        settingsChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), SETTINGS_CHANNEL);
        paymentsChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), PAYMENTS_CHANNEL);
        paymentsChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "hasAccess":
                    NotificationManager manager = getSystemService(NotificationManager.class);
                    if (Build.VERSION.SDK_INT >= 27) {
                        result.success(manager.isNotificationListenerAccessGranted(
                                new ComponentName(this, PaymentNotificationListener.class)));
                    } else {
                        String enabled = Settings.Secure.getString(getContentResolver(),
                                "enabled_notification_listeners");
                        result.success(enabled != null && enabled.contains(
                                new ComponentName(this, PaymentNotificationListener.class).flattenToString()));
                    }
                    break;
                case "openAccessSettings":
                    startActivity(new Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS));
                    result.success(null);
                    break;
                case "hasAlertPermission":
                    result.success(getSystemService(NotificationManager.class).areNotificationsEnabled());
                    break;
                case "enableAlerts":
                    if (Build.VERSION.SDK_INT >= 33 && !shouldShowRequestPermissionRationale(
                            android.Manifest.permission.POST_NOTIFICATIONS)
                            && getPreferences(MODE_PRIVATE).getBoolean("requestedPaymentAlerts", false)) {
                        startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
                    } else if (Build.VERSION.SDK_INT >= 33) {
                        getPreferences(MODE_PRIVATE).edit().putBoolean("requestedPaymentAlerts", true).apply();
                        requestPermissions(new String[]{android.Manifest.permission.POST_NOTIFICATIONS},
                                PAYMENT_ALERT_PERMISSION);
                    } else {
                        Intent settingsIntent = Build.VERSION.SDK_INT >= 26
                                ? new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName())
                                : new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    android.net.Uri.fromParts("package", getPackageName(), null));
                        startActivity(settingsIntent);
                    }
                    result.success(null);
                    break;
                case "consumeReviewTap":
                    Intent intent = getIntent();
                    String action = intent == null ? null : intent.getAction();
                    String prefix = PaymentNotificationListener.ACTION_PREFIX;
                    if (action != null && action.startsWith(prefix)) {
                        intent.setAction(Intent.ACTION_MAIN);
                        result.success(action.substring(prefix.length()));
                    } else {
                        result.success(null);
                    }
                    break;
                case "pending":
                    result.success(PaymentNotificationListener.pending(this).toString());
                    break;
                case "clearPending":
                    result.success(PaymentNotificationListener.clearPending(this));
                    break;
                case "resolve":
                    String id = call.argument("id");
                    String outcome = call.argument("outcome");
                    if (id != null && ("saved".equals(outcome) || "dismissed".equals(outcome)
                            || "rejected".equals(outcome))) {
                        PaymentNotificationListener.resolve(this, id, outcome);
                    }
                    result.success(null);
                    break;
                default: result.notImplemented();
            }
        });
        settingsChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getSettings":
                    Map<String, String> preferences = new HashMap<>();
                    preferences.put("themeMode", settings.getString(THEME_KEY, "system"));
                    preferences.put("currency", settings.getString("preferences.currency", "INR"));
                    preferences.put("speechLanguage", settings.getString("preferences.speechLanguage", "auto"));
                    preferences.put("categories", settings.getString("preferences.categories", "[]"));
                    result.success(preferences);
                    break;
                case "setPreference":
                    String key = call.argument("key");
                    String value = call.argument("value");
                    boolean validCurrency = "currency".equals(key)
                            && ("INR".equals(value) || "USD".equals(value));
                    boolean validLanguage = "speechLanguage".equals(key)
                            && ("auto".equals(value) || "hi".equals(value)
                            || "en".equals(value) || "hinglish".equals(value));
                    boolean validCategories = false;
                    if ("categories".equals(key) && value != null && value.length() <= 65536) {
                        try {
                            org.json.JSONArray items = new org.json.JSONObject(value).getJSONArray("items");
                            validCategories = items.length() > 0;
                        } catch (org.json.JSONException ignored) {
                            // Reject malformed category metadata.
                        }
                    }
                    if (!validCurrency && !validLanguage && !validCategories) {
                        result.error("INVALID_PREFERENCE", "Unsupported preference value.", null);
                        return;
                    }
                    settings.edit().putString("preferences." + key, value).apply();
                    result.success(null);
                    break;
                case "getThemeMode":
                    result.success(settings.getString(THEME_KEY, "system"));
                    break;
                case "setThemeMode":
                    String mode = call.argument("value");
                    if (!"system".equals(mode) && !"dark".equals(mode) && !"light".equals(mode)) {
                        result.error("INVALID_THEME", "Choose system, dark, or light.", null);
                        return;
                    }
                    settings.edit().putString(THEME_KEY, mode).apply();
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        PaymentNotificationListener.foregroundReview = foregroundPayment;
    }

    @Override
    protected void onPause() {
        if (PaymentNotificationListener.foregroundReview == foregroundPayment) {
            PaymentNotificationListener.foregroundReview = null;
        }
        super.onPause();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grants) {
        if (localShare != null && localShare.onPermissions(requestCode, grants)) return;
        super.onRequestPermissionsResult(requestCode, permissions, grants);
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (widgetActions != null) widgetActions.onNewIntent(intent);
        if (paymentsChannel != null) paymentsChannel.invokeMethod("reviewTapped", null);
    }

    @Override
    public void cleanUpFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        if (localShare != null) { localShare.close(); localShare = null; }
        if (widgetActions != null) { widgetActions.close(); widgetActions = null; }
        if (modelAssets != null) { modelAssets.close(); modelAssets = null; }
        if (settingsChannel != null) {
            settingsChannel.setMethodCallHandler(null);
            settingsChannel = null;
        }
        if (paymentsChannel != null) {
            paymentsChannel.setMethodCallHandler(null);
            paymentsChannel = null;
        }
        super.cleanUpFlutterEngine(flutterEngine);
    }
}
