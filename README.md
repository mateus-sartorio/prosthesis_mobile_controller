# prosthesis_mobile_controller

## Environment configs

The app loads MQTT settings from a JSON file in `assets/config/`.

- `assets/config/dev.json` is for local development and emulator runs.

Select the configuration with `APP_ENV`:

```bash
flutter run --dart-define=APP_ENV=dev
```

If you do not pass `APP_ENV`, the app defaults to `dev`.

## MQTT credentials

The broker username and password are kept out of the config files and out of
git. They are read from `secrets.json` at the project root, which is ignored by
git. Create it from the template and fill in your credentials:

```bash
cp secrets.example.json secrets.json
```

Then pass it when running or building (the VS Code launch profiles already do
this):

```bash
flutter run --dart-define=APP_ENV=dev --dart-define-from-file=secrets.json
flutter build apk --release --dart-define-from-file=secrets.json
```

Leaving a value empty connects without that credential. Note that the values
are compiled into the app binary, so use a broker user restricted to the
`prosthesis/#` topics rather than an admin account.
