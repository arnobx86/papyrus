# Changelog

All notable changes to this project will be documented in this file.

## [1.2.1] - 2026-05-11

### Added
- **Email Validation**: Added account existence checks before sending OTPs for both Signup and Forgot Password flows.
- **Custom OTP Recovery**: Switched Forgot Password flow from link-based recovery to 6-digit OTP verification for better mobile consistency.

### Fixed
- **Auth Stability**: Resolved "Looking up a deactivated widget's ancestor" error during the password reset process.
- **Memory Management**: Fixed potential memory leaks in Auth screens by properly disposing text controllers.

## [1.2.0] - 2026-05-07

### Added
- **Monthly Navigation**: Added an interactive month selector to the Aybay screen.
- **Monthly Analytics**: Enabled period-specific data calculation for income, expenses, and transactions in monthly views.
- **Release Notes**: Integrated a detailed release notes document for version tracking.

### Fixed
- **Navigation Stability**: Overhauled the router architecture to fix the "Failed assertion: _elements.contains(element)" error when switching shops.
- **State Leakage**: Implemented a "Fresh Start" strategy using `ValueKey` to ensure the widget tree is fully re-initialized upon shop selection.
- **Date Constraints**: Fixed a security vulnerability that allowed future-date selection; all date pickers are now restricted to current and past dates.

### Changed
- **Dashboard UI**: Removed the redundant Home icon from the dashboard header for a cleaner look.
- **AppBar Layout**: Refined the spacing and prominence of the store name in the main navigation bar.
- **Navigation Logic**: Replaced global navigator keys with a keyed-shell approach for better lifecycle management.

---

## [1.1.0] - 2026-05-02

### Added
- Professional Daily Report PDF export functionality.
- Real-time wallet balance synchronization.
- Role-based permission system for employees.

### Changed
- Optimized transaction naming logic to include invoice numbers and person names.
- Updated UI to use more premium typography and spacing.

---

## [1.0.0] - Initial Release
- Initial stable release of the Papyrus Business Management platform.
