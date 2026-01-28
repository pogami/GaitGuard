# GaitGuardAI

GaitGuardAI is a **watchOS app** that monitors motion on an Apple Watch and provides **rhythmic haptic cueing** to help during **gait initiation** and **turning**, where *freezing of gait* can occur.

> This project is intended as a **cueing aid / prototype**. It is **not** a medical device and should be tested **with supervision** before being relied on for safety-critical situations.

## What it does

- **Automatic cueing**:
  - **Start assist**: detects *attempts to start walking* that don’t turn into steps and plays a short metronome-like haptic cue.
  - **Turn assist**: detects sustained turning motion without stepping and plays a slower cue to encourage controlled, staged turns.
- **Rhythmic haptics**: metronome-style pulses for a few seconds (different rhythm for start vs turn).
- **Cooldown**: prevents rapid re-triggering (reduces haptic “spam”).
- **On-watch stats**: shows **assists today** and **last assist time**.
- **Clean watch UI**: single-screen design that fits smaller watches (e.g., Apple Watch SE).

## Who it’s for

This was built with real-world use in mind for someone who:
- has a foot that “sticks” when **starting to walk**
- struggles to **turn** without assistance
- may sometimes **speed up / lean forward** (festination)

## How detection works (high level)

The app runs a lightweight, on-device state machine driven by **Core Motion**:

- **Sensors**:
  - `CMDeviceMotion` (using `.xArbitraryZVertical`)
  - `userAcceleration` (gravity-removed movement)
  - `rotationRate` (especially yaw for turning)
- **Sampling**: ~**50Hz**
- **Step cadence proxy**:
  - detects peaks in acceleration magnitude over a rolling window to estimate cadence in Hz
- **Initiation assist logic** (simplified):
  - if we see a small “attempt” movement after stillness **but cadence stays low for ~1–2s**, cue “Start”
- **Turn assist logic** (simplified):
  - if we see sustained yaw rotation **but cadence stays low**, cue “Turn”

Important: thresholds are intentionally simple, and are designed to be **tunable** via Sensitivity.

## Wrist & wear guidance

- Designed for **right wrist** use (as requested).
- For best results:
  - wear the watch **snug** (sensor signal is much worse when the watch is loose)
  - start with short, supervised sessions to build trust

## Running on Apple Watch

1. Open `GaitGuardAI/GaitGuardAI.xcodeproj` in Xcode.
2. Select the scheme: **`GaitGuardAI Watch App`**
3. Select a run destination:
   - a Watch Simulator, or
   - your paired physical Apple Watch
4. Press **Run (⌘R)**.

### If the app doesn’t appear on your watch

- In Xcode, ensure you are running **`GaitGuardAI Watch App`** (not only the iPhone target).
- On iPhone: open the **Watch** app → find GaitGuardAI → install / enable “Show App on Apple Watch”.
- If icons or installs are stale: delete the app from the watch, **Clean Build Folder**, then run again.

## Safety notes (please read)

- **Turning difficulty can be a high fall-risk situation.** Use this as a cueing aid, not a replacement for supervision.
- If freezing/turning issues are severe, consider involving a clinician and a **neuro/PT**. Rhythmic cueing works best when paired with taught strategies (staged turns, weight shift, “big step”).
- The app does not (yet) detect falls or call emergency contacts.

## Project structure

- `GaitGuardAI/GaitGuardAI Watch App/ContentView.swift`: watch UI
- `GaitGuardAI/GaitGuardAI Watch App/MotionDetector.swift`: motion ingest, state machine, cueing + stats
- `GaitGuardAI/SessionManager.swift`: `WKExtendedRuntimeSession` management

## Tuning

Open **Settings** in the watch app and adjust **Sensitivity**:
- Higher sensitivity: cues sooner (more false positives)
- Lower sensitivity: fewer cues (may miss subtle freezes)

## Roadmap ideas

- **Calibration mode** (30–60 seconds baseline walk) to personalize thresholds
- **iPhone companion** dashboard via WatchConnectivity (timeline + trends)
- Better cadence/turn modeling (frequency features, per-axis energy, personalization)

## License

Add a license if you plan to share or accept contributions.
