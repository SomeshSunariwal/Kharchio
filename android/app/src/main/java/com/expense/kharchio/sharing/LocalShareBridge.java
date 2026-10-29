package com.expense.kharchio.sharing;

import android.Manifest;
import android.app.Activity;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.wifi.WifiManager;
import android.net.wifi.WpsInfo;
import android.net.wifi.p2p.*;
import android.net.wifi.p2p.nsd.*;
import android.os.*;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Log;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONObject;
import javax.net.ssl.*;
import javax.security.auth.x500.X500Principal;
import java.io.*;
import java.math.BigInteger;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.ECGenParameterSpec;
import java.security.cert.X509Certificate;
import java.util.*;
import java.util.concurrent.*;

/** Wi-Fi Direct discovery plus certificate-pinned TLS. No cloud or shared files. */
public final class LocalShareBridge implements AutoCloseable {
    private static final String BASE = "com.expense.kharchio/local_share";
    private static final int PERMISSIONS = 7242, MAX_FRAME = 2 * 1024 * 1024;
    private final Activity activity;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService workers = Executors.newCachedThreadPool();
    private final MethodChannel methods;
    private final EventChannel events;
    private final WifiP2pManager manager;
    private WifiP2pManager.Channel channel;
    private EventChannel.EventSink sink;
    private final Map<String, Peer> peers = new LinkedHashMap<>();
    private volatile int generation;
    private volatile boolean stopped = true;
    private volatile String role = "none", status = "idle", pin = "", networkName = "";
    private volatile String deviceName;
    private volatile String transferDirection = "idle";
    private volatile SSLServerSocket server;
    private volatile SSLSocket peer;
    private volatile CompletableFuture<JSONObject> acknowledgement;
    private volatile String acknowledgementId = "";
    private boolean registered, serverStarting, connecting;
    private int failedPins;
    private String fingerprint = "", joinAddress = "", ownerIp;
    private Peer joining;
    private String joiningPin;
    private MethodChannel.Result pendingJoin, permissionResult;
    private Runnable permittedOperation;
    private WifiP2pDnsSdServiceRequest discoveryRequest;
    private WifiP2pDnsSdServiceInfo advertisement;

    private static final class Peer {
        final String address, name, fingerprint;
        final int port;
        long seen = System.currentTimeMillis();
        Peer(String address, String name, String fingerprint, int port) {
            this.address = address; this.name = name; this.fingerprint = fingerprint; this.port = port;
        }
    }
    public LocalShareBridge(Activity activity, FlutterEngine engine) {
        this.activity = activity;
        SharedPreferences preferences = activity.getSharedPreferences("local_share", Context.MODE_PRIVATE);
        deviceName = preferences.getString("device_name", "");
        if (deviceName.isEmpty()) {
            String[] colors = {"Amber", "Jade", "Coral", "Silver", "Indigo", "Golden"};
            String[] animals = {"Fox", "Otter", "Robin", "Panda", "Owl", "Dolphin"};
            SecureRandom random = new SecureRandom();
            deviceName = "Kharchio " + colors[random.nextInt(colors.length)] + " "
                + animals[random.nextInt(animals.length)] + " " + (100 + random.nextInt(900));
            preferences.edit().putString("device_name", deviceName).apply();
        }
        manager = (WifiP2pManager) activity.getSystemService(Context.WIFI_P2P_SERVICE);
        methods = new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), BASE);
        events = new EventChannel(engine.getDartExecutor().getBinaryMessenger(), BASE + "/events");
        methods.setMethodCallHandler((call, result) -> {
            try {
                switch (call.method) {
                    case "getDeviceName": result.success(deviceName); break;
                    case "setDeviceName":
                        if (!"none".equals(role)) throw new IOException("End the current session before changing the device name.");
                        String name = call.argument("name");
                        if (name == null || name.trim().isEmpty() || name.trim().length() > 40
                            || name.codePoints().anyMatch(Character::isISOControl))
                            throw new IOException("Enter a device name between 1 and 40 characters.");
                        deviceName = name.trim();
                        activity.getSharedPreferences("local_share", Context.MODE_PRIVATE).edit()
                            .putString("device_name", deviceName).apply();
                        result.success(deviceName); break;
                    case "host": authorize(result, () -> startHost(result)); break;
                    case "discover": authorize(result, () -> startDiscovery(result)); break;
                    case "join": join(call.argument("id"), call.argument("pin"), result); break;
                    case "beginTransfer": beginTransfer(((Number) call.argument("total")).intValue(), result); break;
                    case "sendBatch": sendBatch(call.argument("payload"), result); break;
                    case "acknowledge":
                        if (!"receiving".equals(transferDirection) || peer == null) throw new IOException("No active incoming transfer.");
                        sendAsync(json("type", "ack", "id", call.argument("id"),
                            "added", call.argument("added"), "skipped", call.argument("skipped"),
                            "error", call.argument("error")), result); break;
                    case "finishTransfer":
                        requireSender();
                        sendAsync(json("type", "complete", "added", call.argument("added"),
                            "skipped", call.argument("skipped")), result); break;
                    case "abortTransfer":
                        requireSender(); sendAsync(json("type", "abort"), result); break;
                    case "stop": stopSession(); result.success(null); break;
                    default: result.notImplemented();
                }
            } catch (Exception error) { result.error("SHARE_ERROR", message(error), null); }
        });
        events.setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object args, EventChannel.EventSink value) { sink = value; state(status, ""); publishPeers(); }
            @Override public void onCancel(Object args) { sink = null; }
        });
    }
    private static String message(Throwable error) {
        String value = error.getMessage();
        return value == null || value.isEmpty() ? "Local connection failed. Please try again." : value;
    }
    private static JSONObject json(Object... pairs) throws Exception {
        JSONObject data = new JSONObject();
        for (int i = 0; i < pairs.length; i += 2) data.put((String) pairs[i], pairs[i + 1] == null ? JSONObject.NULL : pairs[i + 1]);
        return data;
    }
    private void emit(Map<String, Object> data) {
        main.post(() -> { if (sink != null) sink.success(data); });
    }
    private void state(String next, String text) {
        status = next;
        Map<String, Object> data = new HashMap<>();
        data.put("type", "state"); data.put("role", role); data.put("status", next);
        data.put("message", text); data.put("pin", "host".equals(role) ? pin : ""); data.put("name", networkName);
        emit(data);
    }
    private void authorize(MethodChannel.Result result, Runnable action) throws Exception {
        if (manager == null || !activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)) {
            throw new IOException("Wi-Fi Direct is unavailable on this device. Use two supported Android phones.");
        }
        WifiManager wifi = (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi == null || !wifi.isWifiEnabled()) throw new IOException("Turn on Wi-Fi, then try again.");
        if (Build.VERSION.SDK_INT < 33) {
            LocationManager location = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);
            if (Build.VERSION.SDK_INT >= 28 && location != null && !location.isLocationEnabled()) {
                throw new IOException("Turn on Location for nearby Wi-Fi discovery on this Android version.");
            }
        }
        List<String> missing = new ArrayList<>();
        String nearby = Build.VERSION.SDK_INT >= 33 ? "android.permission.NEARBY_WIFI_DEVICES" : Manifest.permission.ACCESS_FINE_LOCATION;
        if (activity.checkSelfPermission(nearby) != PackageManager.PERMISSION_GRANTED) missing.add(nearby);
        if (Build.VERSION.SDK_INT >= 37 && activity.checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") != PackageManager.PERMISSION_GRANTED) missing.add("android.permission.ACCESS_LOCAL_NETWORK");
        if (!missing.isEmpty()) {
            if (permissionResult != null) throw new IOException("A permission request is already open.");
            permissionResult = result; permittedOperation = action;
            activity.requestPermissions(missing.toArray(new String[0]), PERMISSIONS);
        } else action.run();
    }
    public boolean onPermissions(int request, int[] grants) {
        if (request != PERMISSIONS) return false;
        MethodChannel.Result result = permissionResult;
        Runnable action = permittedOperation;
        permissionResult = null; permittedOperation = null;
        if (result == null) return true;
        boolean allowed = grants.length > 0;
        for (int grant : grants) allowed &= grant == PackageManager.PERMISSION_GRANTED;
        if (allowed && action != null) action.run();
        else result.error("PERMISSION_DENIED", "Allow Nearby devices access to create or join a local network.", null);
        return true;
    }
    private final BroadcastReceiver receiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (stopped) return;
            if (WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION.equals(intent.getAction()) &&
                    intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) == WifiP2pManager.WIFI_P2P_STATE_DISABLED) {
                stopSession(); state("error", "Wi-Fi was turned off. Turn it on and reconnect.");
            } else if (WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION.equals(intent.getAction())) {
                connectionInfo();
            }
        }
    };
    private void prepare(Runnable next) {
        stopSession(false);
        stopped = false;
        if (channel == null) channel = manager.initialize(activity, Looper.getMainLooper(), () -> {
            stopSession(); state("error", "Wi-Fi Direct disconnected. Please restart sharing.");
        });
        if (!registered) {
            IntentFilter filter = new IntentFilter(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION);
            filter.addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION);
            if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
            else activity.registerReceiver(receiver, filter);
            registered = true;
        }
        int epoch = generation;
        manager.removeGroup(channel, new WifiP2pManager.ActionListener() {
            @Override public void onSuccess() { if (epoch == generation && !stopped) next.run(); }
            @Override public void onFailure(int reason) { if (epoch == generation && !stopped) next.run(); }
        });
    }
    private WifiP2pManager.ActionListener action(Runnable success) {
        int epoch = generation;
        return new WifiP2pManager.ActionListener() {
            @Override public void onSuccess() { if (epoch == generation && !stopped) success.run(); }
            @Override public void onFailure(int reason) {
                if (epoch == generation && !stopped) {
                    String text = reason == WifiP2pManager.BUSY ? "Wi-Fi Direct is busy. Disconnect other Wi-Fi sharing sessions and retry." : "Wi-Fi Direct could not complete the request. Please try again.";
                    failJoin(text); state("error", text);
                }
            }
        };
    }
    private void startHost(MethodChannel.Result result) {
        prepare(() -> {
            role = "host";
            pin = String.format(Locale.US, "%06d", new SecureRandom().nextInt(1000000));
            networkName = deviceName;
            state("creating", "Creating local network...");
            manager.createGroup(channel, action(this::connectionInfo));
            int epoch = generation;
            main.postDelayed(() -> { if (epoch == generation && server == null && !stopped) {
                stopSession(); state("error", "Network creation timed out. Please try again.");
            }}, 45000);
        });
        result.success(null);
    }
    private void startDiscovery(MethodChannel.Result result) {
        prepare(() -> {
            role = "joiner"; state("searching", "Searching for nearby Kharchio networks...");
            manager.setDnsSdResponseListeners(channel, (name, type, device) -> {}, (domain, txt, device) -> {
                if (stopped || !"joiner".equals(role) || !domain.toLowerCase(Locale.US).contains("_kharchio._tcp")) return;
                try {
                    String cert = txt.get("cert"), name = txt.get("name");
                    int port = Integer.parseInt(txt.get("port"));
                    if (!"1".equals(txt.get("v")) || cert == null || !cert.matches("[0-9a-f]{64}") || name == null || port < 1 || port > 65535) return;
                    peers.put(device.deviceAddress, new Peer(device.deviceAddress, name, cert, port)); publishPeers();
                } catch (Exception ignored) { /* Ignore unrelated/malformed service records. */ }
            });
            // An all-record DNS-SD request returns the TXT metadata as well as PTR records.
            discoveryRequest = WifiP2pDnsSdServiceRequest.newInstance();
            manager.addServiceRequest(channel, discoveryRequest, action(() -> {
                manager.discoverServices(channel, action(() -> {})); scheduleDiscovery(generation);
            }));
        });
        result.success(null);
    }
    private void scheduleDiscovery(int epoch) {
        main.postDelayed(() -> {
            if (stopped || epoch != generation || !"joiner".equals(role) || peer != null || pendingJoin != null) return;
            peers.values().removeIf(value -> System.currentTimeMillis() - value.seen > 45000);
            publishPeers(); manager.discoverServices(channel, action(() -> {})); scheduleDiscovery(epoch);
        }, 12000);
    }
    private void publishPeers() {
        List<Map<String, Object>> list = new ArrayList<>();
        for (Peer item : peers.values()) {
            Map<String, Object> data = new HashMap<>(); data.put("id", item.address); data.put("name", item.name); list.add(data);
        }
        emit(networkEvent(list));
    }
    private Map<String, Object> networkEvent(List<Map<String, Object>> items) {
        Map<String, Object> data = new HashMap<>(); data.put("type", "networks"); data.put("items", items); return data;
    }
    private void connectionInfo() {
        if (stopped || channel == null) return;
        manager.requestConnectionInfo(channel, info -> {
            if (stopped) return;
            if (info.groupFormed && info.isGroupOwner && "host".equals(role) && !serverStarting && server == null) {
                serverStarting = true; hostServer(generation);
            } else if (info.groupFormed && !info.isGroupOwner && pendingJoin != null && !connecting) {
                ownerIp = info.groupOwnerAddress.getHostAddress(); connectTls(generation);
            } else if (!info.groupFormed) {
                ownerIp = null;
                if (peer != null) closePeer();
            }
        });
    }
    private SSLContext hostContext() throws Exception {
        String alias = "kharchio-local-share-ec-v1";
        KeyStore keys = KeyStore.getInstance("AndroidKeyStore"); keys.load(null);
        if (keys.containsAlias(alias)) {
            try { ((X509Certificate) keys.getCertificate(alias)).checkValidity(); }
            catch (Exception expired) { keys.deleteEntry(alias); }
        }
        if (!keys.containsAlias(alias)) {
            KeyPairGenerator generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
            generator.initialize(new KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                // Conscrypt supplies a pre-hashed TLS transcript to NONEwithECDSA.
                .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256,
                    KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                .setCertificateSubject(new X500Principal("CN=Kharchio local sharing"))
                .setCertificateSerialNumber(new BigInteger(128, new SecureRandom()))
                .setCertificateNotBefore(new Date(System.currentTimeMillis() - 86400000L))
                .setCertificateNotAfter(new Date(System.currentTimeMillis() + 315360000000L)).build());
            generator.generateKeyPair(); keys.load(null);
        }
        fingerprint = digest(keys.getCertificate(alias).getEncoded());
        KeyManagerFactory factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        factory.init(keys, new char[0]);
        SSLContext tls = SSLContext.getInstance("TLS"); tls.init(factory.getKeyManagers(), null, new SecureRandom()); return tls;
    }
    private void hostServer(int epoch) {
        workers.execute(() -> {
            SSLServerSocket local = null;
            try {
                local = (SSLServerSocket) hostContext().getServerSocketFactory().createServerSocket(0);
                if (epoch != generation || stopped) { local.close(); return; }
                server = local;
                int port = local.getLocalPort();
                main.post(() -> {
                    if (epoch != generation || stopped) return;
                    Map<String, String> txt = new HashMap<>(); txt.put("v", "1"); txt.put("port", Integer.toString(port));
                    txt.put("name", networkName); txt.put("cert", fingerprint);
                    advertisement = WifiP2pDnsSdServiceInfo.newInstance("Kharchio-" + UUID.randomUUID().toString().substring(0, 8), "_kharchio._tcp", txt);
                    manager.addLocalService(channel, advertisement, action(() -> {
                        state("ready", "Share the PIN with the joining device.");
                        hostDiscovery(epoch);
                    }));
                });
                while (!stopped && epoch == generation) {
                    SSLSocket incoming = (SSLSocket) local.accept();
                    workers.execute(() -> authenticateHost(incoming, epoch));
                }
            } catch (Exception error) {
                if (!stopped && epoch == generation) main.post(() -> { stopSession(); state("error", "Could not create the secure local connection. Please try again."); });
            } finally { closeSocket(local); }
        });
    }
    private void hostDiscovery(int epoch) {
        if (stopped || epoch != generation || !"host".equals(role) || peer != null) return;
        manager.discoverPeers(channel, new WifiP2pManager.ActionListener() {
            @Override public void onSuccess() {}
            @Override public void onFailure(int reason) { /* Retry while the host remains available. */ }
        });
        main.postDelayed(() -> hostDiscovery(epoch), 12000);
    }
    private void authenticateHost(SSLSocket socket, int epoch) {
        try {
            socket.setSoTimeout(15000); socket.startHandshake();
            JSONObject request = read(socket);
            synchronized (this) {
                if (stopped || epoch != generation) throw new IOException("Session ended.");
                if (peer != null) { write(socket, json("type", "error", "message", "This host already has a paired device.")); return; }
                if (failedPins >= 5) { write(socket, json("type", "error", "message", "Too many incorrect PINs. Ask the host to create a new network.")); return; }
                if (!"pair".equals(request.optString("type")) || !MessageDigest.isEqual(pin.getBytes(StandardCharsets.UTF_8), request.optString("pin").getBytes(StandardCharsets.UTF_8))) {
                    failedPins++; write(socket, json("type", "error", "message", "Incorrect PIN. Please try again.")); return;
                }
                write(socket, json("type", "paired", "name", networkName)); peer = socket;
            }
            socket.setSoTimeout(0);
            state("connected", "Connected to " + request.optString("name", "paired device"));
            readPeer(socket, epoch);
        } catch (Exception error) { Log.w("KharchioShare", "Host pairing failed", error); }
        finally { if (peer == socket) disconnected(socket, epoch); closeSocket(socket); }
    }
    private void join(String id, String code, MethodChannel.Result result) throws Exception {
        if (!"joiner".equals(role) || stopped) throw new IOException("Tap Join Network to search first.");
        if (pendingJoin != null || peer != null) throw new IOException("A device is already connecting or connected.");
        if (code == null || !code.matches("[0-9]{6}")) throw new IOException("Enter the six-digit PIN.");
        Peer target = peers.get(id);
        if (target == null) throw new IOException("This network is no longer available. Search again.");
        pendingJoin = result; joining = target; joiningPin = code; state("connecting", "Connecting to " + target.name + "...");
        int epoch = generation;
        main.postDelayed(() -> { if (epoch == generation && pendingJoin == result) {
            failJoin("Connection timed out. Keep both sharing screens open and try again.");
            manager.cancelConnect(channel, null);
        }}, 45000);
        if (ownerIp != null && id.equals(joinAddress)) { connectTls(epoch); return; }
        joinAddress = id;
        manager.removeGroup(channel, new WifiP2pManager.ActionListener() {
            private void connect() {
                if (stopped || epoch != generation || pendingJoin != result) return;
                WifiP2pConfig config = new WifiP2pConfig(); config.deviceAddress = id;
                config.wps.setup = WpsInfo.PBC; config.groupOwnerIntent = 0;
                manager.connect(channel, config, action(LocalShareBridge.this::connectionInfo));
            }
            @Override public void onSuccess() { connect(); }
            @Override public void onFailure(int reason) { connect(); }
        });
    }
    private void connectTls(int epoch) {
        if (connecting || pendingJoin == null || joining == null) return;
        connecting = true;
        Peer target = joining; String code = joiningPin; String address = ownerIp;
        workers.execute(() -> {
            SSLSocket socket = null;
            try {
                X509TrustManager trust = new X509TrustManager() {
                    @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                    @Override public void checkClientTrusted(X509Certificate[] chain, String auth) throws java.security.cert.CertificateException { throw new java.security.cert.CertificateException("Not supported"); }
                    @Override public void checkServerTrusted(X509Certificate[] chain, String auth) throws java.security.cert.CertificateException {
                        try {
                            if (chain.length == 0 || !target.fingerprint.equals(digest(chain[0].getEncoded()))) throw new GeneralSecurityException();
                            chain[0].checkValidity();
                        } catch (Exception error) { throw new java.security.cert.CertificateException("The host identity changed. Search again."); }
                    }
                };
                SSLContext tls = SSLContext.getInstance("TLS"); tls.init(null, new TrustManager[]{trust}, new SecureRandom());
                socket = (SSLSocket) tls.getSocketFactory().createSocket();
                socket.connect(new InetSocketAddress(address, target.port), 12000); socket.setSoTimeout(15000); socket.startHandshake();
                write(socket, json("type", "pair", "pin", code, "name", deviceName));
                JSONObject response = read(socket);
                if (!"paired".equals(response.optString("type"))) throw new IOException(response.optString("message", "Pairing failed."));
                if (stopped || epoch != generation || pendingJoin == null) throw new IOException("Session ended.");
                peer = socket; socket.setSoTimeout(0);
                main.post(() -> {
                    if (stopped || epoch != generation) return;
                    connecting = false; joiningPin = null; networkName = target.name;
                    MethodChannel.Result result = pendingJoin; pendingJoin = null;
                    state("connected", "Connected to " + target.name);
                    if (result != null) result.success(null);
                });
                readPeer(socket, epoch);
            } catch (Exception error) {
                Log.w("KharchioShare", "Client pairing failed", error);
                String text = message(error);
                main.post(() -> { if (epoch == generation && !stopped) { connecting = false; failJoin(text); } });
            } finally { if (peer == socket) disconnected(socket, epoch); closeSocket(socket); }
        });
    }
    private void failJoin(String text) {
        MethodChannel.Result result = pendingJoin; pendingJoin = null; joiningPin = null; connecting = false;
        if (result != null) result.error("PAIRING_FAILED", text, null);
        if (!stopped && "joiner".equals(role)) { state("searching", text); scheduleDiscovery(generation); }
    }
    private void readPeer(SSLSocket socket, int epoch) throws Exception {
        while (!stopped && epoch == generation && peer == socket) {
            JSONObject packet = read(socket);
            String type = packet.getString("type");
            if ("ack".equals(type)) {
                CompletableFuture<JSONObject> wait = acknowledgement;
                if (wait != null && acknowledgementId.equals(packet.optString("id"))) wait.complete(packet);
                continue;
            }
            Map<String, Object> data = new HashMap<>(); data.put("type", type);
            if ("begin".equals(type)) {
                int total = packet.getInt("total");
                boolean accepted;
                synchronized (this) {
                    accepted = total >= 0 && "idle".equals(transferDirection);
                    if (accepted) transferDirection = "receiving";
                }
                write(socket, json("type", "ack", "id", packet.getString("id"), "added", 0, "skipped", 0,
                    "error", accepted ? null : "Another transfer is in progress. Wait and retry."));
                if (!accepted) continue;
                data.put("total", total);
            } else {
                if (!"receiving".equals(transferDirection)) throw new IOException("No active incoming transfer.");
                if ("batch".equals(type)) { data.put("id", packet.getString("id")); data.put("payload", packet.getJSONObject("data").toString()); }
                else if ("complete".equals(type)) { data.put("added", packet.getInt("added")); data.put("skipped", packet.getInt("skipped")); transferDirection = "idle"; }
                else if ("abort".equals(type)) transferDirection = "idle";
                else throw new IOException("Unexpected transfer message.");
            }
            emit(data);
        }
    }
    private void requireConnected() throws IOException {
        if (peer == null || peer.isClosed() || !"connected".equals(status)) throw new IOException("Connect to a paired device first.");
    }
    private void requireSender() throws IOException {
        requireConnected();
        if (!"sending".equals(transferDirection)) throw new IOException("No active outgoing transfer.");
    }
    private void beginTransfer(int total, MethodChannel.Result result) throws Exception {
        requireConnected();
        if (total < 0) throw new IOException("Invalid expense count.");
        synchronized (this) {
            if (!"idle".equals(transferDirection)) throw new IOException("Another transfer is in progress. Wait and retry.");
            transferDirection = "sending";
        }
        String id = UUID.randomUUID().toString();
        CompletableFuture<JSONObject> wait = new CompletableFuture<>();
        acknowledgementId = id; acknowledgement = wait;
        SSLSocket current = peer;
        workers.execute(() -> {
            try {
                write(current, json("type", "begin", "id", id, "total", total));
                JSONObject response = wait.get(45, TimeUnit.SECONDS);
                if (!response.isNull("error") && !response.optString("error").isEmpty()) throw new IOException(response.getString("error"));
                if (acknowledgement == wait) { acknowledgement = null; acknowledgementId = ""; }
                main.post(() -> result.success(null));
            } catch (Exception error) {
                // Reconnect after a timeout: the remote may already have accepted the transfer.
                closeSocket(current);
                transferDirection = "idle";
                main.post(() -> result.error("TRANSFER_FAILED", message(error), null));
            } finally { if (acknowledgement == wait) { acknowledgement = null; acknowledgementId = ""; } }
        });
    }
    private void sendAsync(JSONObject packet, MethodChannel.Result result) {
        SSLSocket current = peer;
        workers.execute(() -> {
            try { if (current == null) throw new IOException("No paired device."); write(current, packet);
                if ("complete".equals(packet.optString("type")) || "abort".equals(packet.optString("type"))) transferDirection = "idle";
                main.post(() -> result.success(null)); }
            catch (Exception error) { main.post(() -> result.error("TRANSFER_FAILED", "Connection lost. Reconnect and retry the transfer.", null)); }
        });
    }
    private void sendBatch(String payload, MethodChannel.Result result) throws Exception {
        requireSender();
        if (payload == null || payload.getBytes(StandardCharsets.UTF_8).length > MAX_FRAME - 1024) throw new IOException("Transfer batch is too large.");
        if (acknowledgement != null) throw new IOException("A transfer batch is already pending.");
        String id = UUID.randomUUID().toString();
        JSONObject packet = json("type", "batch", "id", id, "data", new JSONObject(payload));
        CompletableFuture<JSONObject> wait = new CompletableFuture<>(); acknowledgement = wait; acknowledgementId = id;
        SSLSocket current = peer;
        workers.execute(() -> {
            try {
                write(current, packet);
                JSONObject response = wait.get(45, TimeUnit.SECONDS);
                if (!response.isNull("error") && !response.optString("error").isEmpty()) throw new IOException(response.getString("error"));
                Map<String, Object> counts = new HashMap<>(); counts.put("added", response.getInt("added")); counts.put("skipped", response.getInt("skipped"));
                if (acknowledgement == wait) { acknowledgement = null; acknowledgementId = ""; }
                main.post(() -> result.success(counts));
            } catch (Exception error) { main.post(() -> result.error("TRANSFER_FAILED", "The receiver could not save this batch. Reconnect and retry; existing expenses will be skipped.", null)); }
            finally { if (acknowledgement == wait) { acknowledgement = null; acknowledgementId = ""; } }
        });
    }
    private static JSONObject read(SSLSocket socket) throws Exception {
        DataInputStream input = new DataInputStream(socket.getInputStream());
        int length = input.readInt();
        if (length <= 0 || length > MAX_FRAME) throw new IOException("Invalid transfer size.");
        byte[] bytes = new byte[length]; input.readFully(bytes);
        return new JSONObject(new String(bytes, StandardCharsets.UTF_8));
    }
    private static void write(SSLSocket socket, JSONObject data) throws Exception {
        byte[] bytes = data.toString().getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_FRAME) throw new IOException("Transfer batch is too large.");
        synchronized (socket) {
            DataOutputStream output = new DataOutputStream(socket.getOutputStream()); output.writeInt(bytes.length); output.write(bytes); output.flush();
        }
    }
    private static String digest(byte[] data) throws Exception {
        byte[] hash = MessageDigest.getInstance("SHA-256").digest(data);
        StringBuilder text = new StringBuilder(); for (byte value : hash) text.append(String.format(Locale.US, "%02x", value & 255)); return text.toString();
    }
    private void disconnected(SSLSocket socket, int epoch) {
        main.post(() -> { if (peer == socket && epoch == generation && !stopped) {
            closePeer(); state("host".equals(role) ? "ready" : "searching", "Connection lost. Reconnect to transfer again.");
            if ("joiner".equals(role)) scheduleDiscovery(epoch);
        }});
    }
    private static void closeSocket(Closeable socket) { if (socket != null) try { socket.close(); } catch (Exception ignored) {} }
    private void closePeer() {
        transferDirection = "idle";
        SSLSocket old = peer; peer = null; closeSocket(old);
        CompletableFuture<JSONObject> wait = acknowledgement; acknowledgement = null; acknowledgementId = "";
        if (wait != null) wait.completeExceptionally(new IOException("Disconnected"));
    }
    private void stopSession() { stopSession(true); }
    private void stopSession(boolean removeGroup) {
        stopped = true; generation++;
        if (permissionResult != null) {
            permissionResult.error("CANCELLED", "Sharing session ended.", null);
            permissionResult = null; permittedOperation = null;
        }
        closePeer(); closeSocket(server); server = null; serverStarting = false;
        if (pendingJoin != null) { pendingJoin.error("CANCELLED", "Sharing session ended.", null); pendingJoin = null; }
        connecting = false; joining = null; joiningPin = null; ownerIp = null; joinAddress = "";
        pin = ""; networkName = ""; failedPins = 0; peers.clear();
        if (manager != null && channel != null) {
            try { manager.stopPeerDiscovery(channel, null); manager.cancelConnect(channel, null);
                manager.clearLocalServices(channel, null); manager.clearServiceRequests(channel, null); if (removeGroup) manager.removeGroup(channel, null);
            } catch (SecurityException ignored) { /* Permissions may have been revoked. */ }
        }
        if (registered) { activity.unregisterReceiver(receiver); registered = false; }
        role = "none"; state("idle", ""); publishPeers();
    }
    @Override public void close() {
        stopSession();
        if (permissionResult != null) { permissionResult.error("CANCELLED", "Sharing session ended.", null); permissionResult = null; permittedOperation = null; }
        methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null;
        if (channel != null && Build.VERSION.SDK_INT >= 27) channel.close();
        workers.shutdownNow();
    }
}
