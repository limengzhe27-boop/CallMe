# CallMe installation and use

This guide is for testers who receive the source code or a private build. CallMe has no account or
server; configuration, avatars, media, and diagnostics remain on the device where it is installed.

## iPhone

### Free path: sign with each tester's Mac and Apple ID

1. Install Xcode on a Mac and launch it once to finish component setup.
2. Pair the iPhone over USB and tap **Trust**. After the first pairing, enable **Connect via network**
   in Xcode's **Devices and Simulators** window for wireless runs on the same network.
3. Open `CallMe.xcodeproj`.
4. Sign in under **Xcode Settings > Accounts**.
5. Under **TARGETS > CallMe > Signing & Capabilities**, enable automatic signing and select the
   tester's Personal Team.
6. Change the Bundle Identifier to a unique value such as `com.example.callme`.
7. Enable **Settings > Privacy & Security > Developer Mode** on the iPhone and restart if prompted.
8. Select the iPhone in Xcode and press `⌘R`.

Personal Team signing is for personal testing and expires, so Xcode must reinstall the app
periodically. A single free-signed IPA is not a long-term distribution mechanism for many friends.

Long-term distribution requires the project owner to join the Apple Developer Program and choose an
appropriate TestFlight, registered-device, or other Apple-compliant route. This project does not yet
configure those production distribution paths.

## Android

### Build from source

With JDK 17 and an Android SDK installed:

```bash
cd android
./gradlew testDebugUnitTest assembleDebug
```

The APK is written to `android/app/build/outputs/apk/debug/app-debug.apk`.

### Install a private APK

1. Transfer a trusted APK to the phone.
2. Allow the selected browser or file manager to install unknown apps when Android prompts.
3. Install and open CallMe.
4. Complete the permission checklist in the app.

Do not install APKs from unknown sources or with unexpected signatures. The current repository keeps
a third-party ringtone for personal local testing, so APKs containing it should not be published to
GitHub Releases or an app store.

## First-run permissions

- Android phone mode: phone-state permission, CallMe phone account, and exact alarms.
- WeChat-style voice: notifications, full-screen calls, exact alarms, and vendor background launch.
- WeChat-style video: voice permissions plus camera access.
- iPhone: Developer Mode and the locally signed developer profile; CallKit behavior still follows
  silent mode, Focus, and system ringtone volume.

Android system phone UI is owned by the default phone app and therefore changes by device. The
custom voice/video surface chooses a Xiaomi, Huawei/Honor, OPPO-family, vivo-family, Samsung, or
generic layout profile. Only the Xiaomi profile has been calibrated from real-device screenshots;
the others need corresponding screenshots for device-specific refinement.

## Troubleshooting

- If no delayed call appears, check whether the diagnostics log records the alarm firing.
- If the alarm fired but no Android surface appeared, inspect full-screen notification, background
  pop-up, phone-account, and battery settings.
- Silent mode, Focus, and system ringtone settings can suppress system-managed call sound.
- Free iPhone signing is temporary; reinstall from Xcode after expiration.
