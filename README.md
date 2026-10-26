# Kharchio

## Overview

Kharchio is a personal expense tracker for recording spending, exploring category breakdowns, and reviewing yearly, monthly, and daily expenses. Its compact interface supports light and dark themes and works without a login or backend.

The current app uses temporary demo transactions and session-based expense storage. Settings and categories persist locally. The recording flow currently previews typed-text extraction; microphone recording, offline AI inference, and persistent expense storage are not yet connected.

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

- Select a year from 2026 to 2040.
- Drill from a 3 × 4 month grid into a daily calendar, then a date's transaction list.
- Slide only the results container when moving forward or back.
- Use the same collapsible chart, category filtering, highlighting, and scrolling transaction container as Dashboard.
- Edit transactions or add expenses with the floating button.

### Preferences and Categories

- Choose System (default), Dark, or Light appearance.
- Select Automatic, Hindi, English, or Hinglish speech language.
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

### Recording Preview

- Provides editable text, an animated waveform, pause/resume controls, timer, and processing/error states.
- Converts typed items such as `Milk 120, Lunch 450` into editable expense cards through a basic parser.
- Requires review and an explicit save before adding generated cards to the ledger.

### Navigation

- Dashboard, Analysis, and Profile tabs use existing app icons and display the active tab's name beside its icon.
- Shared animated dropdowns and directional tab transitions follow the selected theme and respect reduced-motion preferences.