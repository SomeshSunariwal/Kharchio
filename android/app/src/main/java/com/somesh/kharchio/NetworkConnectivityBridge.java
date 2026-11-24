package com.somesh.kharchio;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;

final class NetworkConnectivityBridge implements EventChannel.StreamHandler {
    private final ConnectivityManager manager;
    private final EventChannel channel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private ConnectivityManager.NetworkCallback callback;

    NetworkConnectivityBridge(Context context, BinaryMessenger messenger) {
        manager = context.getSystemService(ConnectivityManager.class);
        channel = new EventChannel(messenger, "com.somesh.kharchio/network");
        channel.setStreamHandler(this);
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink sink) {
        callback = new ConnectivityManager.NetworkCallback() {
            private void publish() {
                mainHandler.post(() -> {
                    if (callback == this)
                        publishCurrentStatus(sink);
                });
            }

            @Override
            public void onCapabilitiesChanged(Network network, NetworkCapabilities capabilities) {
                publish();
            }

            @Override
            public void onLost(Network network) {
                publish();
            }
        };
        manager.registerDefaultNetworkCallback(callback);
        publishCurrentStatus(sink);
    }

    private void publishCurrentStatus(EventChannel.EventSink sink) {
        Network network = manager.getActiveNetwork();
        NetworkCapabilities capabilities = network == null ? null : manager.getNetworkCapabilities(network);
        sink.success(capabilities != null
                && capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
    }

    @Override
    public void onCancel(Object arguments) {
        if (callback != null) {
            manager.unregisterNetworkCallback(callback);
            callback = null;
        }
    }

    void close() {
        onCancel(null);
        channel.setStreamHandler(null);
    }
}
