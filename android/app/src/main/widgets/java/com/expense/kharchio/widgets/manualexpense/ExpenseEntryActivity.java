package com.expense.kharchio.widgets.manualexpense;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import com.expense.kharchio.MainActivity;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode;

/** A translucent capture window in its own task; the main app stays hidden. */
public final class ExpenseEntryActivity extends MainActivity {
    public static PendingIntent pendingIntent(Context context, String requestedField) {
        String field = requestedField;
        int code;
        switch (field) {
            case "description": code = 202; break;
            case "category": code = 203; break;
            case "amount": code = 204; break;
            default: field = "title"; code = 201;
        }
        Intent intent = new FlutterActivity.NewEngineIntentBuilder(ExpenseEntryActivity.class)
            .backgroundMode(BackgroundMode.transparent)
            .initialRoute("/widgets/entry?focus=" + field)
            .build(context);
        intent.setAction("com.expense.kharchio.widget.entry." + field);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(context, code, intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}

