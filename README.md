# Throw Lab (native)

Hands-free softball timing and coaching feedback for Android (iPhone later).

- Phone on a tripod, press **Start**. The app listens for the glove pop at home and the catch at the base (or bat contact and the ball hitting the net), times the rep from the sound, and speaks the result.
- Coach sets each athlete's **targets** and **coaching cues**; every rep is checked against them.
- **Athlete mode** gives the athlete a simple screen for working alone.

## Getting the app
Every push to `main` builds an APK in GitHub Actions. Open the repo's **Releases** on your phone, tap the newest `ThrowLab-build-N.apk`, and install it.
All builds use the same signing key (`ci/debug.keystore`, a debug-only key), so new builds install over old ones.

## Build notes
The `android/` folder is generated on every CI run by `flutter create`, then adjusted by `ci/patch_android.py` (microphone permission, text-to-speech, min SDK 24). The full build log of the latest run is pushed to the `ci-logs` branch.
