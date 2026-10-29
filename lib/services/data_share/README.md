# Local expense sharing

Settings -> Data Share -> Share App Data with Others opens the sharing screen.
Create Network advertises a Wi-Fi Direct group and a random six-digit PIN. Join
Network discovers Kharchio services without requiring a shared router or internet.
Android may also show its own Wi-Fi Direct connection approval dialog.

Keep the sharing screen open on both phones. Tap a network, enter the six PIN
boxes, and connect. Either paired device can press Transfer Data after confirming its impact. Both phones
show a pinned progress bar and percentage, based on expenses committed by the
receiver and acknowledged to the sender. End Session / Leave Network, navigation
away, engine disposal, or a lost connection closes the local sharing session.

## Data rules

- Only expenses and category metadata needed by them are sent. Profile files,
  settings, budgets, model weights and audio are not shared.
- Expense IDs are preserved. Existing IDs are skipped, including when their
  contents differ; local edits are never overwritten. Similar purchases with
  different IDs remain separate expenses.
- Missing categories are created. Existing categories match by case-insensitive
  name and retain their local colour/icon. Missing month rows get an unset budget
  of -1; existing monthly budgets remain unchanged.
- Each batch is validated and saved in one SQLite transaction. An interrupted
  transfer can leave previously acknowledged batches saved; retrying safely skips
  them. The receiver can start a separate transfer back after the current transfer finishes.

## Implementation

- `expense_transfer_repository.dart`: validates payloads and merges SQLite rows.
- `data_share_controller.dart`: transfer in either direction, bounded batches, acknowledgements,
  progress and ordered incoming imports.
- `local_share_platform.dart`: injectable native channel boundary.
- `lib/features/data_share/`: themed screen and six-box PIN modal.
- `android/app/src/main/java/com/expense/kharchio/sharing/LocalShareBridge.java`:
  Wi-Fi Direct DNS-SD, runtime Nearby devices/local-network permissions, secure
  sockets, framing, pairing and connection cleanup.

The transport uses TLS with an app-private Android Keystore P-256 ECDSA key. Clients pin the
certificate fingerprint advertised by the chosen local host. The PIN is checked
inside that encrypted connection; it is never included in discovery records.
Five incorrect PIN attempts lock further pairing until the creator starts a new
session. Frames are bounded to 2 MiB, normal batches to 50 expenses / about 256 KiB,
and acknowledgements are sent only after SQLite commits.

Tests use independent SQLite databases and linked platform fakes to verify
merging in both directions, progress, duplicate retries, month/category integrity, PIN paste
and retry, and confirmation and paired-device controls. Nearby discovery and pairing were also verified between two Android 17 emulator
instances using Emulator 37.2: host creation, DNS-SD discovery, the six-box PIN
modal, Android connection approval, certificate-pinned TLS and Connected state.
The installed emulator demo stops at pairing; no real expense transfer was
initiated there. Test on two physical Wi-Fi Direct-capable phones as well before
release. Use Android 13+ Nearby devices permission;
older Android versions also require location permission/services. Apps targeting
Android 17 additionally request local-network access.

Discovery uses an all-record DNS-SD query so the host TXT details arrive along
with its PTR record. Hosts keep peer discovery active while waiting. Keystore
ECDSA keys allow the pre-hashed NONEwithECDSA operation used by Conscrypt for
TLS transcript signing; no unencrypted transport fallback is provided.

Device names are generated once as friendly random names and stored in Android app-private SharedPreferences. The Device Name row allows a custom name (1–40 characters) before starting a session. Both discovery and pairing use that name instead of the hardware model. End the active session before renaming; expense transfers do not include this preference.

Either paired device can send expenses after confirming the transfer impact. Transfers run one direction at a time; the native begin/ack handshake rejects concurrent transfers before any expense batches are sent. Pairing roles control network creation only, not transfer direction.
