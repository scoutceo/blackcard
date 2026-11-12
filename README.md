# blackcard

A minimal Android app (Flutter) that gives Google Wallet an Apple Pay–style
double-click screen: a true-black display showing your chosen card image and a
small grey "Hold Near Reader" prompt, and nothing else.

blackcard is **only a visual front end**. Google Wallet stays the default NFC
payment app and answers the terminal in the background. blackcard never reads,
stores, or transmits card data.

## What it does

- Pure `#000000` screen with no status bar, no white flash and no splash icon
- Your card flicks up from below the screen, tilted in 3D, and springs into
  place with a light haptic tick
- A thin contactless mark and "Hold Near Reader" fade in and breathe slowly
- Shows "NFC is off" (tap to open NFC settings) when it can't work
- Optionally appears straight over the lock screen. Wallet still asks you to
  unlock to pay, and changing the card or settings always requires an unlock.
- Closes itself after a timeout (30 s / 60 s / 2 min), when the screen turns
  off, or when you leave it (including when Wallet's payment-complete sheet
  appears). Doesn't appear in Recents.
- Pre-warmed Flutter engine and 120 Hz rendering, so the double press feels
  instant

## Privacy

- **No `INTERNET` permission** in release builds. The manifest actively
  removes it, so dependencies can't add it back. Debug builds include it only so
  Flutter hot reload can reach the Dart VM.
- The card image is chosen with the system photo picker (no storage
  permission needed), cropped on-device, and kept in app-private storage
  (`/data/data/app.blackcard/files/`). The original is kept alongside so you
  can re-adjust the crop.
- Backup and device-to-device transfer are disabled, so the image never leaves
  the phone.
- No third-party packages beyond Flutter's own `material_ui`.

Check a release build:

```sh
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Setup on the phone

1. Install the app (see below).
2. Open blackcard once and **tap the empty card** to choose an image, then
   pinch, drag or twist it to fit the card frame. **Long-press the card** any
   time for settings: change or re-crop the image, pick the timeout, and
   turn lock-screen display on or off.
3. Settings → **Advanced features → Side button → Double press → Open app →
   blackcard**.
4. Settings → **Connections → NFC and contactless payments**: make sure
   **Google Wallet** is the default and "Pay with currently open app" is off,
   or set to the default.

Double-press the side button, unlock, and hold the phone near the reader.

## Development

Built with Flutter stable on Linux and deployed to the phone over wireless ADB
(through Tailscale, in my case):

```sh
adb pair <phone-ip>:<pairing-port> <code>   # once
adb connect <phone-ip>:<port>               # after each Wireless debugging toggle
flutter run                                 # debug + hot reload
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### Signing

Release builds are signed with the key described in `android/key.properties`
(gitignored, never committed):

```properties
storeFile=/path/to/blackcard-release.jks
storePassword=...
keyAlias=blackcard
keyPassword=...
```

Debug builds use the same key, so you can switch between a hot-reload build
and a release build without uninstalling (which would wipe the saved card).
Without `key.properties`, both fall back to the standard debug key.

`lib/main.dart` is the pay screen, `lib/crop.dart` the card cropper and
`lib/settings.dart` the settings sheet. `android/app/src/main/kotlin/app/blackcard/`
holds the Activity (screen-off/leave handling, photo picker, private storage)
and the engine pre-warm.

## Disclaimer

Not affiliated with Apple or Google. "Apple Pay" and "Google Wallet" are
trademarks of their respective owners and are mentioned only to describe
interoperability.
