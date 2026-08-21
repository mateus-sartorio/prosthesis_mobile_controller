# prosthesis_mobile_controller

## Environment configs

The app loads MQTT settings from a JSON file in `assets/config/`.

- `assets/config/dev.json` is for local development and emulator runs.
- `assets/config/prod.json` is for production builds.

Select the configuration with `APP_ENV`:

```bash
flutter run --dart-define=APP_ENV=dev
flutter run --dart-define=APP_ENV=prod
flutter build apk --release --dart-define=APP_ENV=prod
```

If you do not pass `APP_ENV`, the app defaults to `dev`.
