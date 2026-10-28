package com.expense.kharchio.widgets;

import android.app.Activity;
import android.content.Intent;
import android.widget.Toast;
import com.expense.kharchio.R;
import com.expense.kharchio.widgets.manualexpense.ExpenseEntryActivity;
import com.expense.kharchio.widgets.spending.SpendingWidget;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Shared cold/warm launch dispatch for home-screen widgets. No database access. */
public final class WidgetActionBridge {
    public static final String CHANNEL = "com.expense.kharchio/home_widgets";
    public static final String EXTRA_ACTION = "kharchio.widget.action";
    private final MethodChannel channel;
    private Map<String, String> pending;
    private boolean listening;

    public WidgetActionBridge(Activity activity, FlutterEngine engine) {
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        capture(activity.getIntent());
        channel.setMethodCallHandler((call, result) -> {
            if ("consumeLaunchAction".equals(call.method)) {
                listening = true;
                Map<String, String> action = pending;
                pending = null;
                result.success(action);
            } else if ("refreshSpendingWidget".equals(call.method)) {
                SpendingWidget.requestRefresh(activity.getApplicationContext());
                result.success(null);
            } else if ("closeEntry".equals(call.method) && activity instanceof ExpenseEntryActivity) {
                if (Boolean.TRUE.equals(call.argument("saved"))) {
                    Toast.makeText(activity, R.string.widget_form_saved, Toast.LENGTH_SHORT).show();
                }
                result.success(null);
                activity.finishAndRemoveTask();
            } else { result.notImplemented(); }
        });
    }

    private void capture(Intent intent) {
        if (intent == null) return;
        String action = intent.getStringExtra(EXTRA_ACTION);
        intent.removeExtra(EXTRA_ACTION); // Configuration changes must not replay it.
        if (!"add".equals(action) && !"record".equals(action)) return;
        pending = new HashMap<>();
        pending.put("action", action);
        pending.put("id", UUID.randomUUID().toString());
    }

    public void onNewIntent(Intent intent) {
        capture(intent);
        if (listening && pending != null) {
            Map<String, String> action = pending;
            pending = null;
            channel.invokeMethod("launchAction", action);
        }
    }

    public void close() {
        listening = false;
        channel.setMethodCallHandler(null);
    }
}
