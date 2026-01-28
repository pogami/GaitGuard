GaitGuardAI 🛡️
Real-time gait monitoring and haptic rescue for Parkinson's patients.

Overview
GaitGuardAI is a native watchOS application designed to detect "freezing of gait" (FOG) in Parkinson’s patients. By leveraging high-frequency motion data, the app provides immediate haptic feedback to help "break" the freeze and restore natural movement.

Key Technical Features
50Hz Motion Analysis: Processes real-time accelerometer and gyroscope data from the Apple Watch to identify stuttering gait patterns.

Haptic Rescue System: Triggers specific haptic patterns (.directionUp) to provide sensory cues for the wearer.

Native watchOS Integration: Built using SwiftUI and CoreMotion for low-latency performance on the wrist.

Development Challenges Overcome
Beta Tooling & Deployment: Successfully navigated hardware-software versioning conflicts (watchOS 26.3 Beta) by manually managing Developer Disk Images and Xcode system resources.

Sensor Precision: Optimized data collection rates to balance battery life with the high sensitivity required for tremor detection.
