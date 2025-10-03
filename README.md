# BLDC Fan Controller

![Flutter](https://flutter.dev/images/flutter-logo-sharing.png)

**BLDC Fan** is a cross-platform Flutter mobile application designed for controlling Brushless DC (BLDC) ceiling fans and integrated smart lights via Bluetooth Low Energy (BLE). Built for Android and iOS, it provides an intuitive interface for discovering, connecting, and managing fans in different rooms. Whether you're adjusting fan speeds, setting timers, or customizing RGB/CCT lighting with a camera color picker, this app makes smart home fan control seamless and fun.

The app features a modern Material 3 design with light/dark theme support, portrait-only orientation, and smooth animations like rotating fan graphics.

## Features

- **BLE Device Discovery & Connection**: Scan for compatible fans (e.g., "Ventum" or "Simpex" models), assign to rooms, and connect securely.
- **Room Management**: Organize fans by room with add/edit/delete functionality; persists data locally.
- **Fan Controls**:
  - Radial gauge for 1-5 speed levels.
  - Quick "Speed" (gear 6) and "Boost" (gear 7) buttons.
  - Timer presets (5m to 8h) with live countdown.
- **Light Controls**:
  - RGB sliders and hue strip for full color selection.
  - CCT (Color Temperature) slider (2500K warm to 6500K cool).
  - Hex color preview and camera-based color picking (tap to sample from live camera feed).
- **Multi-Device Support**: Manage multiple fans from a home dashboard.
- **Offline Persistence**: Saves device info, rooms, and last settings using SharedPreferences.
- **Animations & UX**: Rotating fan visuals, air-blowing effects on splash, and responsive layouts.

## Screenshots

| Splash Screen | Device Scanning | Home Dashboard |
|---------------|-----------------|----------------|
| ![Splash](screenshots/splash.png) | ![Scanning](screenshots/scanning.png) | ![Home](screenshots/home.png) |

| Fan Controls | Light Controls | Camera Picker |
|--------------|----------------|---------------|
| ![Fan](screenshots/fan.png) | ![Light](screenshots/light.png) | ![Camera](screenshots/camera.png) |

*(Add actual screenshots to `/screenshots/` folder for a polished repo.)*

## Getting Started

### Prerequisites
- Flutter SDK (v3.0+ recommended): [Install Flutter](https://docs.flutter.dev/get-started/install)
- Android/iOS development setup (for building/running on devices).
- A compatible BLDC fan with BLE (e.g., models supporting the app's command protocol).

### Installation

1. **Clone the Repo**:
   ```
   git clone <your-repo-url>
   cd bldcfan
   ```

2. **Install Dependencies**:
   ```
   flutter pub get
   ```

3. **Run the App**:
   - Connect a device or start an emulator.
   - Launch in debug mode:
     ```
     flutter run
     ```
   - For release builds:
     ```
     flutter build apk  # Android
     flutter build ios  # iOS (requires Xcode)
     ```

4. **Permissions**:
   - On first run, grant Bluetooth, Location (for Android BLE scanning), and Camera permissions.
   - Ensure Bluetooth is enabled on your device.

### Usage

1. **First Launch**: The splash screen auto-navigates to device scanning.
2. **Scan & Connect**: Search for fans, assign to a room (e.g., "Living Room"), and connect.
3. **Dashboard**: View saved fans; tap to control or long-press for options (edit/delete).
4. **Controls**:
   - **Fan**: Use the dial for speeds, buttons for boost/timer.
   - **Light**: Slide for RGB/CCT; tap camera icon to pick colors live.
5. **Add More Fans**: From home, tap "Add Fans" to rescan.

BLE commands are sent as byte packets (e.g., `[0x05]` for gear 1, `[0xD5, R, G, B, 0x5D]` for RGB). Customize in `lib/ble.dart` if needed.

## Project Structure

```
lib/
├── main.dart              # App entry, themes, orientation
├── screens/               # UI screens (splash, scanning, home, rooms)
├── controllers/           # Fan/light control screens
├── ble.dart & ble_utility.dart  # BLE helpers
└── camera_color_picker.dart    # Camera integration
test/widget_test.dart      # Basic smoke tests
```

## Dependencies

Key packages (see `pubspec.yaml` for full list):
- `flutter_blue_plus`: BLE communication.
- `camera & image`: Color picking from camera.
- `shared_preferences`: Local storage.
- `permission_handler & location`: Runtime permissions.
- `syncfusion_flutter_gauges`: Speed dial UI.

Run `flutter pub outdated` to check for updates.

## Testing

Run unit/widget tests:
```
flutter test
```

Current tests verify splash rendering and navigation. Expand with `flutter test --coverage`.

## Contributing

1. Fork the repo.
2. Create a feature branch (`git checkout -b feature/amazing-feature`).
3. Commit changes (`git commit -m 'Add amazing feature'`).
4. Push (`git push origin feature/amazing-feature`).
5. Open a Pull Request.

Follow Dart/Flutter style guidelines. Issues welcome!

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter community for the amazing framework.
- Syncfusion for gauge components.
- Inspired by smart home IoT projects.

For support or customizations, open an issue or contact the maintainer.

---

*Built with ❤️ for smarter homes.*

