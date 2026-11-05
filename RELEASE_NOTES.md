# Kharchio 0.1.3

Use your own online AI provider for voice expenses, and back up your expenses and monthly limits in a compressed file.

## Online AI providers

- Choose **On Device** or **Online** in Preferences.
- Add your own **Gemini, OpenAI, Claude or OpenRouter** API key. Test Connection validates the setup and shows a green **Ready** status when successful.
- Choose speech and expense-extraction models separately. **Auto** keeps the model pair that passed testing, avoiding repeated model discovery during recording.
- Both model dropdowns show **Auto → free models → paid models**, with coloured labels and the active model name below each setting.
- Gemini and OpenAI support live transcription; compatible OpenRouter audio models transcribe short chunks. Claude uses local Whisper for speech, followed by online expense extraction. OpenRouter can also use local Whisper when online speech is unavailable.

Free labels indicate model eligibility; actual access, quotas and charges depend on your provider account. Download Whisper before using a provider that needs local speech.

## Recording improvements

- Added a shared recording component for every online speech provider, including future providers.
- Filters silence-only audio before sending it, while retaining a short lead-in and brief pauses to protect word beginnings and endings.
- Uses short speech chunks for live updates, with shared pause, resume and final-audio handling.
- Improved handling of delayed transcription responses without changing the selected model automatically.
- Online **Automatic** and **Hinglish** output preserve the spoken language and script. **English** produces an English final transcript and expense cards. Local Whisper retains its existing English-output behaviour.

## Export and import

- Open **Profile & Settings → Data Backup** to export or import a compressed **`.json.gz`** backup.
- Back up expense and refund records, category names and monthly limits—including limits for months without expenses.
- API keys, preferences, profile names/photos, icons and downloaded models are excluded.
- Import merges records while preserving their IDs and skipping IDs already present. Backed-up monthly limits replace limits for the same month and currency; unrelated data is kept.
- Similar records with different IDs are flagged as possible duplicates and remain separate purchases.
- Imports validate the backup before merging and roll back completely if a database write fails. Progress and completion percentage appear in the existing bottom notification bar.

## Interface improvements

- Loading indicators now appear only on the active Export or Import action.
- More compact Share, Reset Data, About and backup rows.
- Full-width pressed highlights across settings and transaction lists. Middle rows have square highlights; outer rows follow the card's rounded corners.

Existing expenses, monthly limits and downloaded models are preserved when updating the app.

---

# Kharchio 0.1.1

Share expenses with a nearby phone and explore your spending with new Analysis charts.

## Share expenses with another device

- Open **Profile & Settings → Data Share → Share App Data with Others**.
- Create a local network or join a nearby device using a six-digit PIN. No internet connection or account is needed.
- Set a friendly device name so the other person can recognise your phone.
- Either paired phone can send its expenses, with one transfer running at a time.
- Review a short confirmation before sharing. Expenses are added without replacing or deleting the receiving phone's existing data. Expenses already shared are skipped, and the sender's data stays unchanged.
- See transfer progress and the completion percentage on both phones, including how many expenses were added or skipped.
- Transfers use an encrypted connection. Budgets, profile details, settings and downloaded AI models stay on their own device.

Keep the sharing screen open on both phones. Android may ask you to approve the device connection by tapping **Connect**.

## New Analysis line charts

- Swipe between the category donut and a spending line chart. The Dashboard keeps its existing donut chart.
- View spending across months in the yearly view, days in the monthly view, and hours in the daily view.
- Follow a smooth, thin blue line with a fading gradient and an animated entrance.
- Use the chart's horizontal indicators to switch views. Both charts keep a consistent card height while swiping.
- See a dashed budget reference when a budget is set and falls within the chart's displayed amount range.

## Visual improvements

- Improved donut label placement and connecting lines to reduce overlap.
- Kept the Device Name card steady when starting a sharing session.
- Simplified transfer messages and matched the confirmation's Cancel action to the app's dialog style.

Existing expenses and budgets are preserved when updating the app.
