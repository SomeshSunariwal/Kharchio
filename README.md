# Kharchio

## Overview

Kharchio is a personal expense tracker for recording spending, exploring category breakdowns, and reviewing yearly, monthly, and daily expenses. Its compact interface supports light and dark themes and works without a login or backend.

Expenses, categories, and preferences are stored locally in SQLite through Drift. New installs start with an empty ledger and default categories. Whisper and Qwen models are downloaded once from Settings and then process speech offline. Audio stays in memory; transcripts and extraction summaries are temporary and are never saved to the database.

To set up everything locally, follow [BUILD.md](BUILD.md).

## Screenshots

<table>
  <tr>
    <td width="33%"><img src="assets/images/1.%20Dashabord.png" alt="Dashboard" width="100%" /></td>
    <td width="33%"><img src="assets/images/2.%20Analysis.png" alt="Analysis" width="100%" /></td>
    <td width="33%"><img src="assets/images/3.%20Analysis%20Graph.png" alt="Analysis graph" width="100%" /></td>
  </tr>
  <tr>
    <td width="33%"><img src="assets/images/4.%20Monthly%20Analysis.png" alt="Monthly analysis" width="100%" /></td>
    <td width="33%"><img src="assets/images/5.%20Daily%20Expense%20Analysis.png" alt="Daily expense analysis" width="100%" /></td>
    <td width="33%"><img src="assets/images/6.%20Profile%20and%20Setting%20Section.png" alt="Profile and settings" width="100%" /></td>
  </tr>
  <tr>
    <td width="33%"><img src="assets/images/7.%20AI%20Support.png" alt="AI support" width="100%" /></td>
    <td width="33%"><img src="assets/images/8.%20Data%20Sharing.png" alt="Data sharing" width="100%" /></td>
    <td width="33%"><img src="assets/images/9.%20Dashboard%20Dark.png" alt="Dashboard in dark mode" width="100%" /></td>
  </tr>
</table>

## Functionality

### Dashboard

- Opens to the device's current month and refreshes when the app resumes.
- Shows total spending, previous-month comparison, category breakdown, and searchable transactions.
- Displays a category donut with labels, amounts, percentages, and connecting lines.
- Collapses the donut into a horizontal percentage bar while scrolling, keeping the spending summary visible.
- Filters transactions by tapping a pie slice or bar segment, highlighting the selection and dimming other categories. Tap again or use the clear control to reset.
- Keeps the transaction heading fixed after collapse, with rows scrolling inside a container connected to bottom navigation.

### Add and Edit Expenses

- Create multiple editable cards with separate title, optional description, category, and amount fields.
- Select an expense date through a compact calendar.
- Validate positive amounts with up to two decimal places; format completed amount entries to two decimals.
- Add, edit, or delete expenses and immediately update Dashboard and Analysis.
- Keep the add-card, recording, and save actions visible below the scrolling cards.

### Analysis

- Select a year from 2026 to 2046.
- Drill from a 3 × 4 month grid into a daily calendar, then a date's transaction list.
- Slide only the results container when moving forward or back.
- Swipe left from the donut to a blue spending line with a fading area gradient and a rising entrance animation. Dashboard keeps its donut chart.
- Plot months in year view, days in month view, and all 24 hours in day view. Empty time buckets show zero spending; amounts follow the selected currency and category filter.
- Switch chart pages with swipe gestures or the expanding horizontal line indicators. Motion respects the device’s reduced-motion setting.
- Use the same collapsible chart, category filtering, highlighting, and scrolling transaction container as Dashboard.
- Edit transactions or add expenses with the floating button.

### Preferences and Categories

- Set a local profile photo and edit the display name inline. The default is Budget Tracker with the app logo; profile details live in private files, separate from SQLite.
- Choose System (default), Dark, or Light appearance.
- Select Automatic, English, or Hinglish speech language.
- Choose INR or USD display currency; existing amounts are not exchanged or converted.
- Add categories with a name and a colored icon from the shared icon collection.
- Remove categories and reassign their expenses to a remaining category; retain at least one category.
- Save theme, language, currency, and category preferences locally.
- Choose On Device or Online AI processing. On Device keeps the existing downloaded Whisper/Qwen workflow.
- Reset all expense records from Settings → Danger Zone; categories, settings, and downloaded models are kept.

### Amount Display

- Totals and transaction amounts use two decimal places.
- Month cards show full amounts without decimals.
- INR uses Indian digit grouping; USD uses international grouping.
- Calendar values show whole amounts through 99,999, then currency-specific lakh/crore or million notation.
- Donut labels avoid fixed trailing decimals. The center separates the currency sign, amount, and Total label, abbreviating larger amounts.

### Offline Voice Expenses

- Capture English or Hinglish speech with pause/resume controls and a 90-second limit using downloaded multilingual Whisper Small.
- Compare S23 Ultra's precompiled QNN model with the generic Qualcomm NPU option, which compiles portable DLCs locally and caches them. NPU downloads are independent of GPU weights; OpenCL/CPU fallback is available when GPU speech weights are also downloaded. See [AI build setup](BUILD.md).
- Update a disabled, read-only transcript box during recording using local Whisper inference.
- Pausing stops microphone capture while Whisper finishes all buffered speech; resuming continues the same recording.
- On Stop, finish transcription and use Qwen3-0.6B to produce a grammar-constrained JSON array. Each item contains title, description, numeric amount, and a category from the app's current category enum.
- Validate model output and show a summary list of expenses for review.
- Create editable Add Expense cards only when Create Expense Cards is pressed. Saving the cards writes the final expenses to SQLite.
- Keep audio, transcript, and summary out of the database; clear temporary audio buffers after processing or cancellation.
- Show actual offline model readiness in Profile.
- Download models with progress, pause/resume, file-size and checksum verification; ready models show a delete action. Processing checks require the files for the selected backend.

### Online Voice Expenses

- Select Gemini, OpenAI, Claude, or OpenRouter in Settings → Online AI and add your own API key.
- Gemini and OpenAI use a persistent Live/Realtime speech connection. New microphone samples are sent once in small PCM chunks, and incoming transcript updates feed the existing read-only transcript box. Stop finalizes that transcript and makes one expense-extraction request; it never re-uploads the recording. OpenAI's stream is resampled from the shared 16 kHz capture to its required 24 kHz format.
- Gemini closes speech windows at a short silence or after two seconds of continuous audio, then waits for the provider's acknowledgement before sending the next window. This lets models that finalize transcription at activity boundaries update the UI before Stop without interrupting pending recognition. Test Connection requires a transcript update before Stop; Stop drains queued audio and waits for the final window.
- Pausing online speech leaves pending transcription attached to the same session. The pause control returns promptly, late responses can still update the transcript, and resumed audio waits for the prior boundary instead of being dropped. Stop waits for every pending boundary with a bounded final deadline. Gemini timestamp comparisons allow millisecond rounding, and silent activity-end acknowledgements do not require transcript text.
- Claude uses the existing on-device Whisper speech path and sends only the transcript to Claude for expense extraction. Download the local speech model before recording in Claude mode; Qwen is not required.
- OpenRouter discovers audio-input/text-output models for Speech Model and text-input/text-output models for Available Model. Auto tries compatible free models first, then a bounded paid fallback, and locks the pair that passes audio and expense validation. Pricing labels come from catalog metadata; free audio availability is not guaranteed. It transcribes short WAV chunks with the selected model through chat completions, displays results before Stop, and drains queued chunks before the final expense request. This is chunk transcription rather than a Realtime WebSocket.
- OpenRouter speech and expense checks are independent: if no online speech model is available or passes testing (including insufficient audio credits), a successful expense check saves on-device Whisper as the speech source. OpenRouter in this mode and Claude show a disabled Speech Model dropdown with a red “Using on-device Whisper” message; Available Model remains enabled. Download Whisper before recording in these hybrid modes. Retest the connection to detect newly available online speech.
- Test Connection discovers compatible models once, checks Live speech (Gemini/OpenAI) with a short bundled sample, and validates sample expenses/refunds. It saves the exact working pair securely and shows green Ready. The provider may charge for these test requests. Older batch-only model checks must be run once again to validate streaming.
- Auto resolves during testing, trying free-classified candidates before paid candidates for Gemini and OpenRouter. OpenAI and Claude use their compatible paid model priorities. The resolved pair is locked for subsequent recordings: no model-list requests or fallback-model probes during recording. Speech Model and Available Model dropdowns allow manual changes; only the changed component is tested before activation. Both rows show the active model name for Auto and manual selections.
- Model menus reserve three quarters of each row for an ellipsized name and one quarter for a green `[free]` or red `[paid]` label. A selected model replaces its label with a matching-color check. Free describes free-tier eligibility; project billing still determines charges.
- Temporary HTTP failures retry the same locked model with bounded backoff. Free-only emulator testing uses `--dart-define=GEMINI_FREE_TIER_ONLY=true`, which excludes paid-only Gemini models from both selection and requests.
- Expense extraction uses the current categories, currency and speech-output policy, with the same amount, category and refund validation as on-device processing.
- Online speech models detect input automatically: Automatic preserves the spoken language/script, English translates into English, and Hinglish preserves Hindi/English as spoken without forcing English into Hindi. Live online text stays on the fast recognition path; English output is formatted after Stop using the locked context model. Automatic/Hinglish require no formatting request. The preference description appears only in Online mode.
- Local Whisper retains its original English-output behavior for Automatic, English and Hinglish/Hindi, including when used by Claude or OpenRouter fallback. Automatic uses detected-language translation, English uses English transcription, and Hinglish/Hindi uses Hindi/mixed decoding with English translation. Offline Qwen review cards remain English. CPU/GPU and Snapdragon/NPU share this policy. Online hybrid modes show “Local Whisper: always English” in the preference description; the online context model receives that English transcript.
- Pause/resume, the 90-second recording limit, review cards, quick saving, and undo keep the existing workflow. Online mode requires internet and provider quota. Gemini, OpenAI, and OpenRouter with validated online speech do not require local model downloads; Claude and OpenRouter with local speech require Whisper. Provider errors during recording do not silently change the selected model or processing mode.
- Credentials stay out of SQLite and data sharing. Replacing or removing a key clears Ready. Old authentication-only tests must be run again to validate the full online pipeline.

### Local Expense Sharing

- Open Settings -> Data Share -> Share App Data with Others.
- Create a local Wi-Fi Direct network or discover and join a nearby host using a six-digit PIN.
- Either paired device can send expenses over an encrypted connection after reviewing a transfer confirmation; both devices show progress and percentage.
- Missing expenses and required categories are added. Matching expense IDs are skipped; the receiving device’s own expenses and budgets are preserved.
- See [sharing implementation and testing](lib/services/data_share/README.md).

### Local Data

- Store categories, expenses, and app settings in three SQLite tables.
- Store amounts as integer minor currency units, such as paise or cents, with no recording/source column.
- Preserve expense date separately from record creation/update timestamps.
- Update related screens through Drift streams and preserve saved expenses across restarts. Older demo transactions are removed automatically.

### Navigation

- Dashboard, Analysis, and Profile tabs use existing app icons and display the active tab's name beside its icon.
- Shared animated dropdowns and directional tab transitions follow the selected theme and respect reduced-motion preferences.

## Resources

GitHub projects behind the app's AI models and inference runtimes:

| Project                                                             | Used for                                                                  |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [OpenAI Whisper](https://github.com/openai/whisper)                 | Multilingual Whisper Small speech recognition.                            |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp)              | Native Whisper inference with OpenCL GPU and CPU fallback.                |
| [Qwen3](https://github.com/QwenLM/Qwen3)                            | Qwen3-0.6B, which extracts structured expenses from transcripts.          |
| [llama.cpp](https://github.com/ggml-org/llama.cpp)                  | Native Qwen inference, including the GGML Hexagon NPU backend.            |
| [Qualcomm AI Hub Models](https://github.com/qualcomm/ai-hub-models) | Qualcomm's Whisper graph adaptation used by the QNN/QAIRT export tooling. |
