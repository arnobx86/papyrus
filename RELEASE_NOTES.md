# Release Notes - v1.0.707

## 🚀 New Features

- **Daily Business Report**: A comprehensive new dashboard feature that provides a complete financial snapshot (দিনের হিসাব) for any selected date.
  - Track total Sales, Purchases, and cash flow in one place.
  - View cumulative **Final Cash Balance** at the end of each day.
  - See "Today's Net" performance (Profit/Deficit) at a glance.
  - Support for floating-point (decimal) values for precise accounting.
  - Instant data updates when switching dates.

## 🛠️ Key Fixes & Improvements

- **Fixed Double Stock Deduction**: Resolved a critical issue where editing a sale caused stock to be deducted twice. Updated RLS security policies to ensure old items are correctly removed before new ones are added.
- **Accurate Dashboard Metrics**: Today's Cash, Expense, and Sales stats now use actual transaction dates rather than database timestamps, ensuring accuracy even for back-dated entries.
- **Smart Transaction Ordering**: The Ay-Bay transaction list is now intelligently sorted by actual transaction date (most recent first).
- **Ledger-Transaction Sync**: Improved bidirectional synchronization between person ledgers and the cash book (Ay-Bay).
- **Time-Stamp Collision Fix**: Fixed a bug where multiple transactions on the same day could cause sorting or data integrity issues due to identical timestamps.

---

# Release Notes - v1.0.706

## 🚀 Key Improvements

- **Multi-Arch Distribution**: Added support for ARM64, ARMv7, and x86_64 binaries.
- **Smart Updates**: In-app update system now detects device architecture.
- **SKU Search**: Search products by SKU or Name in Sales and Purchase screens.

## 🛠️ Performance & Monitoring

- **Realtime Optimization**: Consolidated database listeners to reduce server load by 75%.
- **Sentry Integration**: Global error tracking & crash reporting enabled.
- **Improved Security**: Moved admin dashboard to secure `/sudo` route.

## 🎨 Branding

- **Logo Sync**: Wordmark and Favicon standardized across platform.
- **UI Tweaks**: Added SKU visibility in product lists.

---

## 🩹 Hotfix & Maintenance (v1.0.706)

- **Invoice Clarity**: The "Invoiced By" field on PDF exports now correctly displays the name of the team member who created the invoice, rather than defaulting to the logged-in user.
- **Provider Stability**: Solved a system-wide crash loop ("Looking up a deactivated widget's ancestor is unsafe") by safely evaluating `DataRefreshNotifier` states during screen disposal.
- **Update System Polish**:
  - Throttled update prompts: The app update dialog now snoozes for 24 hours, preventing repetitive popups throughout the day.
  - Updated version check logic to be vastly more reliable so it won't prompt you to update to versions you already have.
  - Fixed an issue causing the "Update Now" download button to fail on Android 11+ devices.
  - Added a manual "Check for Updates" button to the Settings screen.
- **Accurate Branding**: The application version displayed in Settings is now dynamically bound directly to the app package (v1.0.706).

---
*Papyrus: Grow your business today.* 🌿📱
