package com.expense.kharchio;

import android.content.SharedPreferences;
import java.util.HashMap;
import java.util.Map;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Launcher activity: starts Dart main() and connects native Android services. */
public class MainActivity extends FlutterActivity {
    private static final String SETTINGS_CHANNEL = "com.expense.kharchio/settings";
    private static final String THEME_KEY = "appearance.themeMode";
    private MethodChannel settingsChannel;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        SharedPreferences settings = ((KharchioApplication) getApplication()).getSettings();
        settingsChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), SETTINGS_CHANNEL);
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
    public void cleanUpFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        if (settingsChannel != null) {
            settingsChannel.setMethodCallHandler(null);
            settingsChannel = null;
        }
        super.cleanUpFlutterEngine(flutterEngine);
    }
}
