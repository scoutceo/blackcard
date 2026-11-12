# blackcard

A minimal Android app (Flutter) that gives Google Wallet an Apple Pay–style
double-click screen: a true-black display showing your chosen card image and a
small grey "Hold Near Reader" prompt, and nothing else.

blackcard is **only a visual front end**. Google Wallet stays the default NFC
payment app and answers the terminal in the background. blackcard never reads,
stores, or transmits card data.

## What it does

- Pure `#000000` screen (no white flash at launch, no splash icon)
- Your card image near the top in ID-1 card proportions with rounded corners
- Contactless icon and "Hold Near Reader" in grey
- Closes itself after 60 s, when the screen turns off, or when you leave it
  (including when Wallet's payment-complete sheet appears)
- Doesn't appear in Recents
- Flutter engine is pre-warmed so the double press shows the screen
  almost instantly

## Privacy

- **No `INTERNET` permission** in release builds. The manifest actively
  removes it, so dependencies can't add it back. Debug builds include it only so
  Flutter hot reload can reach the Dart VM.
- The card image is copied with the system photo picker (no storage
  permission needed) to app-private storage: `/data/data/app.blackcard/files/card`.
- Backup and device-to-device transfer are disabled, so the image never leaves
  the phone.
- No third-party packages beyond Flutter's own `material_ui`.

Check a release build:

```sh
aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
```

## Setup on the phone

1. Install the app (see below).
2. Open blackcard once and **tap the empty card** to choose your card image.
   Long-press the card any time to change it.
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
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`lib/main.dart` contains the whole UI. `android/app/src/main/kotlin/app/blackcard/`
holds the Activity (screen-off/leave handling, photo picker, private storage)
and the engine pre-warm.

## Disclaimer

Not affiliated with Apple or Google. "Apple Pay" and "Google Wallet" are
trademarks of their respective owners and are mentioned only to describe
interoperability.
