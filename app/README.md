# MedUnity Android App

Flutter Android app for the MedUnity verified-doctor network at `https://medunity.areafair.in`.

The `android/` folder is **not in the repo** — Flutter generates it locally on the Windows build host.
See [CLAUDE.md](CLAUDE.md) for AI-assistant guidance and full architecture notes.

---

## First-time setup on Windows

From the cloned repo root, `cd` into `app/`, then:

```bat
flutter create --org=in.areafair --project-name=medunity .
flutter pub get
flutter run
```

`flutter create` on a populated directory only adds missing platform files — it will not overwrite
`pubspec.yaml`, `analysis_options.yaml`, `lib/`, `README.md`, or `CLAUDE.md`.

**applicationId note:** `flutter create --project-name=medunity` produces
`applicationId = "in.areafair.medunity"` in `android/app/build.gradle.kts` — that is the correct
package name, no manual fix needed.

---

## Firebase wiring (one-time, after first flutter create)

1. Download `google-services.json` from the Firebase Console (project: `medunity`) and place it at
   `app/android/app/google-services.json` (gitignored — never commit this file).
2. Drop `firebase-credentials.json` (service-account key) at `backend/firebase-credentials.json`
   (gitignored — never commit this file).
3. In `android/settings.gradle.kts` add to the `plugins { … }` block:
   ```kotlin
   id("com.google.gms.google-services") version "4.4.2" apply false
   ```
4. In `android/app/build.gradle.kts` add to the `plugins { … }` block:
   ```kotlin
   id("com.google.gms.google-services")
   ```
   (no version, no `apply false` on the app-level file)
5. Run `flutter run --uninstall-first` after any Gradle plugin change.

**Kotlin DSL placement note:** this scaffold uses `pluginManagement {}` in `settings.gradle.kts`,
so the version declaration for `com.google.gms.google-services` goes in `settings.gradle.kts` —
NOT in a project-level `build.gradle.kts` (Flutter's modern scaffold doesn't use one).

---

## Android permissions (one-time, after flutter create)

In `android/app/src/main/AndroidManifest.xml`, above the `<application>` tag:

```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

After adding, track the file so a fresh clone doesn't lose the permissions:

```bat
git add -f android\app\src\main\AndroidManifest.xml
git commit -m "Track AndroidManifest with required permissions"
git push origin main
```

---

## Daily build loop

```bat
cd app
git pull
flutter pub get    REM only if pubspec changed
flutter run        REM device must be connected with USB debugging on
```

---

## Release build

```bat
cd app
flutter build appbundle --release
REM upload build\app\outputs\bundle\release\app-release.aab to Play Console
```

Generate a signing key first (same workflow as SmartStep / SureDataPro):

```bat
keytool -genkey -v -keystore medunity.jks -alias medunity -keyalg RSA -keysize 2048 -validity 10000
```

Store the keystore and `key.properties` locally on the Windows machine — never commit them.

---

## VPS → Windows sync workflow

```bash
# On VPS — after editing Flutter source in app/
cd /home/drriyazq/medunity
git add -A && git commit -m "..."
git push origin main    # MUST push or Windows builds stale code
```

```bat
:: On Windows
cd app
git pull
flutter pub get
flutter run
```
