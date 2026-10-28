package com.expense.kharchio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import java.io.File;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Opens private model storage and configures native runtime paths. */
final class ModelAssetBridge {
    private final MethodChannel channel;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean closed;

    ModelAssetBridge(Context context, FlutterEngine engine) {
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "com.expense.kharchio/models");
        channel.setMethodCallHandler((call, result) -> {
            if (!"modelDirectory".equals(call.method)) {
                result.notImplemented();
                return;
            }
            worker.execute(() -> {
                try {
                    // Reuse previously installed models; Dart verifies their contents.
                    File folder = new File(context.getFilesDir(), "offline_models");
                    if (!folder.isDirectory() && !folder.mkdirs())
                        throw new Exception("Cannot create model directory");
                    File kernels = new File(context.getCacheDir(), "ai-kernels");
                    if (kernels.isDirectory() || kernels.mkdirs()) {
                        try {
                            android.system.Os.setenv("GGML_OPENCL_KERNEL_CACHE_DIR", kernels.getAbsolutePath(), true);
                        } catch (android.system.ErrnoException error) {
                            android.util.Log.w("KharchioAI", "GPU kernel cache unavailable", error);
                        }
                    }
                    android.system.Os.setenv("ADSP_LIBRARY_PATH",
                            context.getApplicationInfo().nativeLibraryDir
                                    + ";/vendor/dsp/cdsp;/vendor/lib/rfsa/adsp;/system/lib/rfsa/adsp;/dsp", true);
                    main.post(() -> {
                        if (!closed) result.success(folder.getAbsolutePath());
                    });
                } catch (Exception error) {
                    main.post(() -> {
                        if (!closed) result.error("MODEL_STORAGE", error.getMessage(), null);
                    });
                }
            });
        });
    }

    void close() {
        closed = true;
        channel.setMethodCallHandler(null);
        worker.shutdown();
    }
}
