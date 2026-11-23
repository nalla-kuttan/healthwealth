# Volume — Workout Volume & PR Heatmap

Zero-entry iOS 17+ app that reads `HKWorkout` history from Apple Health and renders a 52-week
volume heatmap with automatic PR badges, muscle-group recovery, and Home/Lock Screen widgets.
All analysis runs on-device.

## Layout

| Path | What |
| --- | --- |
| `Packages/VolumeKit/Sources/VolumeCore` | HealthKit-free engines: heatmap levels, PR detection, recovery decay, streaks, widget snapshot, demo data |
| `Packages/VolumeKit/Sources/VolumeUI` | Shared SwiftUI: heatmap cells, readiness bars, widget layouts |
| `App/` | SwiftUI app, `HealthSyncService` (auth, anchored backfill, observer + background delivery), `WorkoutMapper` |
| `Widgets/` | WidgetKit extension: `systemMedium`, `systemLarge`, `accessoryRectangular` |
| `project.yml` | XcodeGen spec (HealthKit, background delivery and App Group entitlements) |

## Run

```bash
xcodegen generate && open VolumeHeatmap.xcodeproj
```

```bash
cd Packages/VolumeKit && swift test
```

Launch arguments (Debug): `-demoData` loads a deterministic sample year (the simulator has no
workouts); `-widgetGallery` renders the widget layouts in-app at real widget sizes.

To run on a device, set `DEVELOPMENT_TEAM` and replace the `com.example` bundle IDs and
`group.com.example.volumeheatmap` (also in `SharedStore.appGroupID`).

## Interpretation choices

- **Levels 1–4** score each day as the mean of `energy / p75(energy)` and `duration / p75(duration)`
  over the trailing 90 days (falls back to all history with < 5 active days). Cut-offs: < 0.5, < 0.8,
  < 1.1, ≥ 1.1. A logged workout is never level 0, even if its app recorded no energy.
- **PRs** need a previous best in the same activity + metric; the first effort only sets the
  baseline, so a fresh 365-day backfill doesn't flood the grid. Runs compete in the longest standard
  band they cover (a 10.3 km run is a 10K effort). Minimum improvement 0.1 %.
- **TRIMP** is Edwards-style from duration × the zone of the session's *average* HR (per-sample
  zones would need a heart-rate query per workout). Max HR is estimated from observed workouts.
- **Recovery** strain per segment = muscle weight × session intensity (TRIMP, else kcal, else
  duration, relative to a solid hour) × 0.6; τ is 24–36 h per muscle group; 96 h window.
- **Read denial is invisible** to apps in HealthKit, so a denied user sees the empty-year state with
  a "Check Health access" link; the dedicated access screen covers unavailable devices and failed
  authorization requests.
- **watchOS** isn't built yet; the Lock Screen widget covers the glanceable case on iPhone.
