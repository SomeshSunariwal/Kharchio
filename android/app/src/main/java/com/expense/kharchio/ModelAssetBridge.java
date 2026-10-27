package com.expense.kharchio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.Build;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.json.JSONArray;
import org.json.JSONObject;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.FlutterInjector;
import io.flutter.plugin.common.MethodChannel;

/** Installs bundled model assets without blocking Android's UI thread. */
final class ModelAssetBridge {
    private final MethodChannel channel;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private volatile boolean closed;

    ModelAssetBridge(Context context, FlutterEngine engine) {
        channel = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "com.expense.kharchio/models");
        channel.setMethodCallHandler((call, result) -> {
            if (!"installBundled".equals(call.method)) {
                result.notImplemented();
                return;
            }
            worker.execute(() -> {
                try {
                    File folder = new File(context.getFilesDir(), "offline_models");
                    if (!folder.isDirectory() && !folder.mkdirs())
                        throw new Exception("Cannot create model directory");
                    // Cache compiled GPU programs privately, avoiding shader recompilation
                    // on every app launch. This stores no audio or transcription data.
                    File kernels = new File(context.getCacheDir(), "ai-kernels");
                    if (kernels.isDirectory() || kernels.mkdirs()) {
                        try {
                            android.system.Os.setenv("GGML_OPENCL_KERNEL_CACHE_DIR", kernels.getAbsolutePath(), true);
                        } catch (android.system.ErrnoException error) {
                            android.util.Log.w("KharchioAI", "GPU kernel cache unavailable", error);
                        }
                    }
                    Map<String, String> paths = new HashMap<>();
                    // FastRPC loads DSP kernels from the installed native library folder.
                    android.system.Os.setenv("ADSP_LIBRARY_PATH",
                            context.getApplicationInfo().nativeLibraryDir
                                    + ";/vendor/dsp/cdsp;/vendor/lib/rfsa/adsp;/system/lib/rfsa/adsp;/dsp",
                            true);
                    for (String obsolete : new String[] { "ggml-base.bin", "ggml-base.bin.partial" }) {
                        File old = new File(folder, obsolete);
                        if (old.isFile() && !old.delete())
                            android.util.Log.w("KharchioAI", "Could not remove obsolete Base model");
                    }
                    String[][] models = { { "whisper", "ggml-small-q5_1.bin" }, { "qwen", "Qwen3-0.6B-Q8_0.gguf" } };
                    long[] expectedBytes = { 190085487L, 639446688L };
                    for (int index = 0; index < models.length; index++) {
                        String[] model = models[index];
                        File target = new File(folder, model[1]);
                        if (!target.isFile() || target.length() != expectedBytes[index]) {
                            File partial = new File(folder, model[1] + ".partial");
                            String asset = FlutterInjector.instance().flutterLoader()
                                    .getLookupKeyForAsset("models/" + model[0] + "/" + model[1]);
                            try (InputStream input = context.getAssets().open(asset);
                                    FileOutputStream output = new FileOutputStream(partial)) {
                                byte[] buffer = new byte[256 * 1024];
                                int count;
                                while ((count = input.read(buffer)) != -1)
                                    output.write(buffer, 0, count);
                                output.getFD().sync();
                            } catch (Exception error) {
                                partial.delete();
                                throw error;
                            }
                            if (partial.length() != expectedBytes[index]) {
                                partial.delete();
                                throw new Exception("Bundled model is incomplete");
                            }
                            if (!partial.renameTo(target)) {
                                partial.delete();
                                throw new Exception("Cannot install model");
                            }
                        }
                        paths.put(model[0], target.getAbsolutePath());
                    }
                    installWhisperQnn(context, folder);
                    main.post(() -> {
                        if (!closed)
                            result.success(paths);
                    });
                } catch (Exception error) {
                    main.post(() -> {
                        if (!closed)
                            result.error("MODEL_INSTALL", error.getMessage(), null);
                    });
                }
            });
        });
    }

    private static void installWhisperQnn(Context context, File folder) {
        installWhisperPackage(context, folder, "whisper-qnn-generic", "generic");
        if (Build.VERSION.SDK_INT >= 31 && Build.SOC_MODEL.toUpperCase(java.util.Locale.ROOT).contains("SM8550")) {
            installWhisperPackage(context, folder, "whisper-qnn-sm8550", "SM8550");
        }
    }

    private static void installWhisperPackage(Context context, File folder, String packageName, String soc) {
        File targetFolder = new File(folder, packageName);
        try {
            String assetFolder = packageName + "/";
            String manifestAsset = assetFolder + "manifest.json";
            JSONObject manifest;
            try (InputStream input = context.getAssets().open(manifestAsset)) {
                java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
                byte[] chunk = new byte[4096];
                int size;
                while ((size = input.read(chunk)) != -1)
                    bytes.write(chunk, 0, size);
                manifest = new JSONObject(new String(bytes.toByteArray(), StandardCharsets.UTF_8));
            }
            if (!soc.equals(manifest.getString("soc")))
                throw new Exception("Wrong Whisper QNN chipset");
            if (!targetFolder.isDirectory() && !targetFolder.mkdirs())
                throw new Exception("Cannot create Whisper QNN directory");
            if ("generic".equals(soc))
                new File(targetFolder, "revision.txt").delete();
            JSONArray files = manifest.getJSONArray("files");
            for (int i = 0; i < files.length(); i++) {
                JSONObject entry = files.getJSONObject(i);
                String assetName = entry.getString("name");
                String prefix = "generic".equals(soc) ? "whisper-generic-" : "whisper-s23-";
                String extension = "generic".equals(soc) ? ".dlc" : ".bin";
                if (!(assetName.equals(prefix + "encoder" + extension)
                        || assetName.equals(prefix + "decoder" + extension)))
                    throw new Exception("Invalid Whisper QNN filename");
                // Keep installed names stable so existing model copies/caches are reused.
                String name = assetName.substring(prefix.length());
                File target = new File(targetFolder, name);
                // A checksum sidecar identifies the installed model release.
                File stamp = new File(targetFolder, name + ".sha256");
                String expected = entry.getString("sha256");
                if (target.isFile() && target.length() == entry.getLong("bytes") && stamp.isFile() &&
                        expected.equals(
                                new String(java.nio.file.Files.readAllBytes(stamp.toPath()), StandardCharsets.UTF_8)))
                    continue;
                File partial = new File(targetFolder, name + ".partial");
                MessageDigest digest = MessageDigest.getInstance("SHA-256");
                String asset = assetFolder + assetName;
                try (InputStream input = context.getAssets().open(asset);
                        FileOutputStream output = new FileOutputStream(partial)) {
                    byte[] buffer = new byte[256 * 1024];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        output.write(buffer, 0, count);
                        digest.update(buffer, 0, count);
                    }
                    output.getFD().sync();
                } catch (Exception error) {
                    partial.delete();
                    throw error;
                }
                StringBuilder actual = new StringBuilder();
                for (byte b : digest.digest())
                    actual.append(String.format(java.util.Locale.ROOT, "%02x", b & 0xff));
                if (partial.length() != entry.getLong("bytes") || !expected.equals(actual.toString())) {
                    partial.delete();
                    throw new Exception("Whisper QNN checksum mismatch");
                }
                if (!partial.renameTo(target)) {
                    partial.delete();
                    throw new Exception("Cannot install Whisper QNN model");
                }
                java.nio.file.Files.write(stamp.toPath(), expected.getBytes(StandardCharsets.UTF_8));
            }
            if ("generic".equals(soc)) {
                String revision = manifest.getString("revision");
                if (!revision.matches("[a-f0-9]{64}"))
                    throw new Exception("Invalid Whisper DLC revision");
                java.nio.file.Files.write(new File(targetFolder, "revision.txt").toPath(),
                        revision.getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception error) {
            android.util.Log.w("KharchioAI", packageName + " assets unavailable; OpenCL/CPU fallback will be used",
                    error);
        }
    }

    void close() {
        closed = true;
        channel.setMethodCallHandler(null);
        worker.shutdown();
    }
}
