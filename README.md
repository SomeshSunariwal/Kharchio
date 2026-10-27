# Kharchio

## Overview

Kharchio is a personal expense tracker for recording spending, exploring category breakdowns, and reviewing yearly, monthly, and daily expenses. Its compact interface supports light and dark themes and works without a login or backend.

Expenses, categories, and preferences are stored locally in SQLite through Drift. The same demo transactions are seeded once on first setup and survive restarts. Bundled Whisper and Qwen models process speech offline. Audio stays in memory; transcripts and extraction summaries are temporary and are never saved to the database.

## Functionality

Development references: [code map](docs/ai/CODE_MAP.md), [AI setup](docs/ai/SETUP.md), [responsiveness checks](docs/PERFORMANCE.md).

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

- Select a year from 2026 to 2040.
- Drill from a 3 × 4 month grid into a daily calendar, then a date's transaction list.
- Slide only the results container when moving forward or back.
- Use the same collapsible chart, category filtering, highlighting, and scrolling transaction container as Dashboard.
- Edit transactions or add expenses with the floating button.

### Preferences and Categories

- Choose System (default), Dark, or Light appearance.
- Select Automatic, English, or Hinglish speech language.
- Choose INR or USD display currency; existing amounts are not exchanged or converted.
- Add categories with a name and a colored icon from the shared icon collection.
- Remove categories and reassign their expenses to a remaining category; retain at least one category.
- Save theme, language, currency, and category preferences locally.

### Amount Display

- Totals and transaction amounts use two decimal places.
- Month cards show full amounts without decimals.
- INR uses Indian digit grouping; USD uses international grouping.
- Calendar values show whole amounts through 99,999, then currency-specific lakh/crore or million notation.
- Donut labels avoid fixed trailing decimals. The center separates the currency sign, amount, and Total label, abbreviating larger amounts.

### Offline Voice Expenses

- Capture English or Hinglish speech with pause/resume controls and a 90-second limit using bundled multilingual Whisper Small.
- Compare S23 Ultra's precompiled QNN model with the generic Qualcomm NPU option, which compiles portable DLCs locally and caches them. Both use OpenCL, then CPU fallback. GPU/CPU retain Q5_1 weights; Qwen is unchanged. See [AI setup](docs/ai/SETUP.md) and the [code map](docs/ai/CODE_MAP.md).
- Update a disabled, read-only transcript box during recording using local Whisper inference.
- Pausing stops microphone capture while Whisper finishes all buffered speech; resuming continues the same recording.
- On Stop, finish transcription and use Qwen3-0.6B to produce a grammar-constrained JSON array. Each item contains title, description, numeric amount, and a category from the app's current category enum.
- Validate model output and show a summary list of expenses for review.
- Create editable Add Expense cards only when Create Expense Cards is pressed. Saving the cards writes the final expenses to SQLite.
- Keep audio, transcript, and summary out of the database; clear temporary audio buffers after processing or cancellation.
- Show actual offline model readiness in Profile.

### Local Data

- Store categories, expenses, and app settings in three SQLite tables.
- Store amounts as integer minor currency units, such as paise or cents, with no recording/source column.
- Preserve expense date separately from record creation/update timestamps.
- Update related screens through Drift streams and retain the same mock data without re-seeding on restart.
### Navigation

- Dashboard, Analysis, and Profile tabs use existing app icons and display the active tab's name beside its icon.
- Shared animated dropdowns and directional tab transitions follow the selected theme and respect reduced-motion preferences.
