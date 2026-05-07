# Release Notes - v1.2.0

## 🚀 Stability & Navigation Overhaul

### 🏗️ "Fresh Start" Navigation Architecture
- **Resolved Critical Crashes**: Fixed the persistent "Failed assertion: _elements.contains(element)" error that occurred when switching between different shops.
- **State Isolation**: Implemented a dynamic router reconstruction strategy that fully unmounts and recreates the application widget tree during shop switches, ensuring zero state leakage between sessions.
- **Improved Lifecycle Management**: Removed global navigator keys in favor of a keyed root architecture for more reliable navigation transitions.

## 📅 Feature Enhancements

### 📊 Advanced Monthly Reporting
- **Interactive Month Selector**: Added a new monthly navigation system to the Aybay screen, allowing users to browse through historical months easily.
- **Period-Specific Analytics**: Monthly views now dynamically calculate and display income, expenses, and transactions for the specific selected month.

### 🔒 Data Integrity & Security
- **Future-Date Prevention**: Enforced a global policy across all date pickers (Sales, Purchases, Transactions, Reports, and Profile) to restrict selection to the current or past dates.
- **Security Audit**: Completed a codebase-wide audit to ensure no future-dated entries can be accidentally recorded.

## 🎨 UI/UX Refinements
- **Streamlined Dashboard**: Cleaned up the main header by removing the redundant Home icon, giving more prominence to the store name.
- **Premium Aesthetics**: Refined the AppBar layout for a cleaner, more professional interface.

---

# Release Notes - v1.1.0 (Previously 1.0.9)

## 🚀 Enhancements & Reporting Updates

### 📄 Professional Daily Report PDF
- **Streamlined Layout**: Optimized the Daily Report PDF for a cleaner, more professional appearance.
- **Simplified Labels**: Main transaction titles in the PDF are now concise (e.g., "Sale", "Purchase", "Received", "Payment"), while full details remain available in the app's interactive view.
- **Detailed Descriptions**: Synchronized the PDF with the app UI to include full transaction notes/descriptions under each entry, ensuring a comprehensive audit trail.
- **Symmetrical Design**: Improved A4 alignment for opening and closing balance boxes.

### 💰 Financial Accuracy
- **Smart Transaction Naming**: Improved the logic for identifying Sales, Purchases, and Person Ledger transactions. It now automatically pulls invoice numbers and person names using advanced pattern matching across multiple database fields.
- **Unified Logic**: Consolidated transaction naming across the entire app (Screen + PDF) to ensure data consistency.

---

# Release Notes - v1.0.8

## 🚀 New Features & Major Updates
...
