# Release

## Einmalig: Keystore

```sh
keytool -genkeypair -v -keystore cashbandit-release.jks -storetype PKCS12 \
  -alias cashbandit -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=CashBandit"
```

Der Keystore **nie** ins Repo (`.gitignore` deckt `*.jks`, `*.keystore` und `key.properties` ab). Sicher aufbewahren (z. B. Passwort-Manager + Offline-Kopie) – ohne ihn können keine Updates mehr signiert werden, Android verweigert dann die Installation über die alte Version.

Lokal signieren: `android/key.properties`

```properties
storeFile=/pfad/zu/cashbandit-release.jks
storePassword=...
keyAlias=cashbandit
keyPassword=...
```

GitHub → *Settings → Secrets and variables → Actions*:

| Secret | Inhalt |
|---|---|
| `CASHBANDIT_KEYSTORE_BASE64` | `base64 -w0 cashbandit-release.jks` |
| `CASHBANDIT_KEYSTORE_PASSWORD` | Store-Passwort |
| `CASHBANDIT_KEY_ALIAS` | `cashbandit` |
| `CASHBANDIT_KEY_PASSWORD` | Key-Passwort |
| `GITLAB_MIRROR_TOKEN` | GitLab-Projekt-Token (write_repository) für den Spiegel |

## Release-APK lokal bauen

```sh
tools/fetch-sqlite.sh
flutter pub get
dart run build_runner build -d
flutter build apk --release                  # eine APK für alle Geräte
flutter build apk --release --split-per-abi  # kleinere APKs pro CPU-Architektur
```

## Neue Version

1. `pubspec.yaml`: `version: X.Y.Z+N` – `N` (versionCode) **immer** erhöhen.
2. Changelog: `fastlane/metadata/android/{de-DE,en-US}/changelogs/N.txt`.
3. Bei Schemaänderungen: `schemaVersion` in `lib/data/db.dart` erhöhen, Migrationsschritt ergänzen und
   `dart run drift_dev schema dump lib/data/db.dart drift_schemas/drift_schema_vN.json`.
4. Commit, dann Tag: `git tag -a vX.Y.Z -m "CashBandit X.Y.Z" && git push origin main vX.Y.Z`.
5. GitHub Actions:
   - **Release**: Tests, signierte APKs (arm64-v8a, armeabi-v7a, x86_64 + universell) und `SHA256SUMS` im GitHub-Release mit Changelog.
   - **Mirror**: `main` und Tags nach gitlab.com/CrashBandit82/cashbandit.
6. F-Droid erkennt neue Tags automatisch (`AutoUpdateMode: Version`, `UpdateCheckMode: Tags`).

Der Workflow bricht ab, wenn Tag und `pubspec.yaml`-Version nicht übereinstimmen.

## versionCode bei Split-APKs

Flutter addiert bei `--split-per-abi` 1000 × ABI: armeabi-v7a `1000+N`, arm64-v8a `2000+N`, x86_64 `4000+N`. Die universelle APK hat `N`. Wer einmal eine Split-APK installiert hat, kann die universelle derselben Version nicht darüber installieren (Downgrade) – beim Testen immer dieselbe Art verwenden.
