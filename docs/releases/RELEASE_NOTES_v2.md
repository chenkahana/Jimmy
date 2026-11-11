# Jimmy Version 2 Release Notes

Jimmy 2.0 focuses on stability across the entire app. The update was completed in five phases:

1. **Widget Isolation** – Moved the lock-screen widget to its own extension and enabled App Groups for safe data sharing.
2. **Automated Testing** – Added extensive unit tests, UI tests, and continuous integration.
3. **Error Handling** – Implemented retry logic, offline caching, and OSLog-based crash logging.
4. **Performance Tuning** – Fixed memory leaks and strengthened on-disk storage to prevent corruption.
5. **Final Polish** – Reviewed instrumentation, stabilized tests, and updated all documentation.

Additional improvements:
- Added OSLog instrumentation for the episode cache and file storage systems.

With these improvements the project is ready for daily use and further extensions.
