# MotionLog

An iOS app that continuously collects accelerometer data, persists it to Core Data, and exports it as a CSV file via the native share sheet.

Built for the Twosense iOS Coding Challenge.

---

## Requirements

- Xcode 16 or later
- iOS 17+ device or simulator
- Swift 5.10+

---

## Build & Run

1. Open `Motionlog/Motionlog.xcodeproj` in Xcode.
2. Select a simulator or a connected device running iOS 17+.
3. Press **⌘R** to build and run.

> **Note:** The accelerometer is not available in the iOS Simulator. The app will build and run on the Simulator, but no readings will be collected — the `isAvailable` guard in `AccelerometerService` returns `false` and collection is skipped gracefully. Run on a physical device to see live data.

---

## Running the Tests

Press **⌘U** in Xcode, or run from the command line:

```bash
xcodebuild test \
  -project Motionlog/Motionlog.xcodeproj \
  -scheme Motionlog \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

All tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). There is no UITest target.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                            │
│                                                             │
│   DashboardView  ◄──────────►  DashboardViewModel          │
│   (SwiftUI)                    (@Observable, @MainActor)   │
└──────────────────────────┬──────────────────────────────────┘
                           │ calls
┌──────────────────────────▼──────────────────────────────────┐
│                      Service Layer                          │
│                                                             │
│   AccelerometerService     StorageManager    CSVExportService│
│   (actor)                  (actor)           (struct)       │
└────────────┬───────────────────┬────────────────────────────┘
             │                   │
┌────────────▼───────────────────▼────────────────────────────┐
│                   Platform Layer                            │
│                                                             │
│   CMMotionManager    NSPersistentContainer    BGTaskScheduler│
└─────────────────────────────────────────────────────────────┘

Background path:
BGTaskScheduler ──► BackgroundTaskScheduler ──► AccelerometerService
                                            └──► StorageManager
```

### Key components

**`AccelerometerService` (actor)** — Wraps `CMMotionManager` behind a `MotionManagerProtocol` so the actor can be fully unit-tested without hardware. Exposes `start(interval:onReading:)` for foreground streaming and `collectBurst(duration:)` for background windows. Both use `Date()` at sample time for correct wall-clock timestamps (`CMLogItem.timestamp` is uptime-relative, not a calendar date).

**`StorageManager` (actor)** — Owns the Core Data stack. Uses `NSBatchInsertRequest` for efficient bulk saves during background bursts, and `NSFetchRequest` with an optional timestamp predicate for date-range queries. Returns `SensorReading` value types (not `NSManagedObject`) so results are safe to pass across actor boundaries.

**`CSVExportService` (struct)** — Pure, stateless value type. `generateCSV(from:)` builds the CSV string; `exportToFile(readings:)` writes it to a uniquely named temp file and returns the URL for the share sheet.

**`BackgroundTaskScheduler`** — Registers and handles `BGAppRefreshTask`. On each background wake it immediately re-schedules the next refresh (so no window is ever missed), collects a 20-second burst via `AccelerometerService`, and saves the results via `StorageManager`. The expiration handler cancels the inner `Task` cleanly if iOS cuts the window short.

**`DashboardViewModel` (@Observable, @MainActor)** — Bridges the service layer to the view. Foreground collection runs as a `for await` loop over an `AsyncStream`, which avoids capturing `self` in a `@Sendable` closure and keeps all state updates on the main actor. `exportData()` fetches since `lastExportTime`, guards the empty case with an alert, writes the CSV, and persists `lastExportTime` to `UserDefaults`.

---

## Sampling Frequency & Storage

| Setting | Value | Rationale |
|---------|-------|-----------|
| Foreground interval | 100 ms (10 Hz) | Sufficient for activity detection; ~36 000 readings/hour |
| Background burst duration | 20 s | Stays within the typical 30 s iOS background window |
| Background refresh interval | 15 min (earliest) | Balances data density against battery consumption |
| Storage format | Core Data (`AccelerometerReading` entity) | Native, queryable by date range, no dependencies |
| CSV timestamp | ISO 8601 with fractional seconds, UTC | Unambiguous, parseable by any downstream tool |
| CSV precision | 6 decimal places | Matches `CMAccelerometerData` double precision output |

---

## Background Collection

iOS does not permit continuous accelerometer access when the app is backgrounded. MotionLog handles this honestly with `BGAppRefreshTask`:

- When the app moves to the background, it submits a `BGAppRefreshTaskRequest` with `earliestBeginDate` of 15 minutes from now.
- iOS wakes the app at some point after that — exact timing is at the system's discretion based on battery level, usage patterns, and device activity.
- During each wake window, the app collects a 20-second burst and persists it before the window closes.

**Trade-offs accepted:**
- There will be **gaps** in background data between wake-up events. This is a fundamental iOS constraint; it cannot be worked around without abusing location or audio background modes.
- iOS may **delay or skip** background tasks when battery is low, Low Power Mode is active, or the device is rarely used.
- Background App Refresh must be **enabled** on the device under *Settings → General → Background App Refresh → MotionLog*.
- `BGTaskScheduler` cannot be unit-tested without the live system scheduler; its integration behavior is verified by the Task 9 smoke test checklist.

---

## Project Structure

```
Motionlog/
├── App/
│   └── MotionlogApp.swift          Entry point; registers background tasks
├── Models/
│   ├── SensorReading.swift         Sendable value type used across actor boundaries
│   └── AccelerometerReading+CoreData.swift  NSManagedObject subclass (manual codegen)
├── Services/
│   ├── MotionManagerProtocol.swift  Protocol + CMMotionManagerAdapter (nonisolated)
│   ├── AccelerometerService.swift   Actor; foreground streaming + burst collection
│   ├── StorageManager.swift         Actor; Core Data stack, batch insert/fetch
│   └── CSVExportService.swift       Pure struct; CSV generation + temp file write
├── Dashboard/
│   ├── DashboardView.swift          SwiftUI view; sheet, alert, .task modifier
│   └── DashboardViewModel.swift     @Observable ViewModel; AsyncStream reading loop
├── Background/
│   └── BackgroundTaskScheduler.swift  BGAppRefreshTask registration + handler
└── Resources/
    ├── Motionlog.xcdatamodeld       Core Data model (AccelerometerReading entity)
    └── Info.plist                   NSMotionUsageDescription, BGTaskSchedulerPermittedIdentifiers

MotionlogTests/
├── AccelerometerReadingTests.swift  Core Data entity init + fetch request
├── StorageManagerTests.swift        Save, fetch, date range, delete (in-memory store)
├── AccelerometerServiceTests.swift  Start/stop, intervals, burst — MockMotionManager
└── DashboardViewModelTests.swift    State transitions, export — mock actors
```

---

## Testing Approach

All tests use **Swift Testing** (no XCTest). Each test file targets one layer:

- **`StorageManagerTests`** (11 tests) — uses an in-memory Core Data store so every test starts clean; covers batch insert, fetch-all, fetch-since, first/last date, delete.
- **`AccelerometerServiceTests`** (11 tests) — uses `MockMotionManager` (`@unchecked Sendable` + `NSLock`) so hardware is never required; covers availability, start/stop idempotency, interval setting, reading delivery, burst collection.
- **`CSVExportServiceTests`** (13 tests) — pure function; covers header, empty input, row count, ISO 8601 format, UTC suffix, 6 dp precision, negative values, column count, ordering, file creation.
- **`DashboardViewModelTests`** (13 tests) — uses `MockAccelerometerService` and `MockStorageManager` actors; covers UserDefaults restore, initial seed from storage, `isCollecting` lifecycle, reading delivery, save forwarding, no-data alert, export sheet/URL, UserDefaults persistence.

---

## Git History

```
fbf5db3 Fix timestamps showing Jan 2001 instead of current date
4102434 Task 8: DashboardView, ActivityView, and MotionlogApp cleanup
78fdfec Task 7: DashboardViewModel with service protocols and tests
e04d86c Task 6: BackgroundTaskScheduler + app wiring
2e486e8 Task 5: CSVExportService with ISO 8601 timestamps and 6dp precision
079a6f2 Fix actor isolation warnings in CMMotionManagerAdapter
50b391c Task 4: AccelerometerService with protocol-based motion manager
57f86ca Task 3: StorageManager actor + SensorReading value type
aeafb55 Fix: exclude Info.plist from auto-resource copying
82599a7 Task 2: Core Data model — AccelerometerReading entity
384533b Remove UITests target; switch unit tests to Swift Testing
3e8e27d Task 1: project setup — folder structure, bundle ID, Info.plist
c4d32e7 Initial Commit
```
