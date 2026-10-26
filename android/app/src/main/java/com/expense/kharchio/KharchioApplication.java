package com.expense.kharchio;

import android.app.Application;
import android.content.SharedPreferences;

/** Process-level startup for the Android app, written entirely in Java. */
public final class KharchioApplication extends Application {
    private SharedPreferences settings;

    @Override
    public void onCreate() {
        super.onCreate();
        settings = getSharedPreferences("kharchio_settings", MODE_PRIVATE);
    }

    public SharedPreferences getSettings() {
        return settings;
    }
}
