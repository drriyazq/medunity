# Publishing MedUnity — End-to-End Checklist

A linear walk-through from today's state to a live Internal Testing release, then Closed Testing.

---

## Phase 1 — One-time setup (~2 hours)

### 1.1 Generate the upload keystore (on Windows)

```bat
cd medunity\app\android
make-keystore.bat
```

This creates `%USERPROFILE%\medunity-upload.jks` and prints instructions for `key.properties`.

**Back it up to two places.** If you lose the keystore, Play Store will never accept an update again — you'd have to publish under a new package name and rebuild your user base.

### 1.2 Create `android/key.properties`

Copy `android/key.properties.template` → `android/key.properties` and fill in real values. Already gitignored.

### 1.3 Enable Firebase Crashlytics in Firebase Console

1. <https://console.firebase.google.com/> → MedUnity project
2. Build → **Crashlytics** → **Get started**
3. The SDK is already wired in `pubspec.yaml` and `main.dart` (release-only via `kReleaseMode`).

### 1.4 Host Privacy Policy + Terms on `trusmiledentist.in`

Already deployed by VPS-side run of this checklist. Verify:
- <https://trusmiledentist.in/medunity/privacy/>
- <https://trusmiledentist.in/medunity/terms/>

Both should return 200 with the policy content.

### 1.5 Backend on Gunicorn + systemd

Already deployed by VPS-side run. Verify:

```bash
systemctl is-active medunity-backend     # → active
systemctl is-enabled medunity-backend    # → enabled
curl -sI https://trusmiledentist.in/medunity-api/health/    # → 200
```

If `runserver` PIDs are still around, they should have been killed during the deploy. Re-check with `pgrep -fa "runserver 0.0.0.0:8009"`.

---

## Phase 2 — Build the release bundle (~15 minutes, on Windows)

### 2.1 Sync + build

```bat
cd medunity
git pull origin master

cd app
flutter pub get
flutter build appbundle --release
```

Output: `app\build\app\outputs\bundle\release\app-release.aab`

### 2.2 Smoke test the release APK on your phone first

Don't upload the AAB to Play Console before confirming the release build runs. R8/ProGuard occasionally breaks reflection paths that worked in debug.

```bat
cd app
flutter build apk --release
flutter install --release
```

Walk the full path on your phone:
1. Sign in (use `+91 9867933139` + OTP `123456`)
2. Home loads → Brownie Points card visible
3. Send a test SOS to the second test phone (`+91 9967406651`); verify it lands and the responder map updates
4. Open Circles → My Circles + Nearby tabs
5. Open Consultants → toggle availability
6. Open Marketplace → load grid
7. Profile → check verified badge

If any step crashes, run `adb logcat | findstr Flutter` to capture the stack and fix before uploading.

---

## Phase 3 — Play Console submission (~2–3 hours for Internal Testing)

### 3.1 Create the Play Console app

1. <https://play.google.com/console/> → **Create app**
2. App name: `MedUnity — Doctor Network`
3. Default language: English (India)
4. App or game: **App**
5. Free or paid: **Free**
6. Declarations: accept Developer Program Policies + US export laws

### 3.2 Fill the dashboard setup tasks (left sidebar)

- **App access** — paste the App Access block from `DATA_SAFETY.md` (lists both reviewer test phones + OTP `123456`)
- **Ads** — No ads
- **Content rating** — fill the IARC questionnaire using `CONTENT_RATING.md`
- **Target audience and content** — Adults only (18+); confirm no children content; declare Firebase SDKs and WhatsApp Business API
- **News app** — No
- **COVID-19 contact tracing** — No
- **Data safety** — copy answers from `DATA_SAFETY.md`
- **Government apps** — No
- **Financial features** — No
- **Health** — Mark **Yes** ("Health features"); under sub-questions, declare:
  - Does the app provide medical / health information for clinicians? **Yes**
  - Does the app provide diagnostic / treatment recommendations? **No** (peer discussion only — no algorithmic guidance)
- **Privacy policy URL** — `https://trusmiledentist.in/medunity/privacy/`

### 3.3 Store listing

Use content from `STORE_LISTING.md`:
- App icon, feature graphic, screenshots → upload assets
- Short description, full description → paste
- Support email → `drdentalmail@gmail.com`
- Website → `https://trusmiledentist.in/medunity/`
- Category → Medical

### 3.4 Create the Internal Testing release

1. **Testing → Internal testing → Create new release**
2. **Upload** `app-release.aab`
3. **Release name**: `1.0.0 (Internal)` (auto-populates from `versionName`)
4. **Release notes**:
    ```
    Initial internal testing release.
    - Verified-doctor sign-in (WhatsApp OTP for +91, Firebase fallback otherwise)
    - SOS one-tap broadcast within 1 km
    - Local Doctor Circles with posts/comments
    - Consultant find-nearby + booking
    - Equipment co-purchase pools + marketplace
    - Practice support requests + Brownie Points leaderboard
    - Verified vendor / lab directory
    Reviewer credentials in App Access section.
    ```
5. **Testers** — create a "MedUnity Internal" list; add your Google account + 2 colleagues
6. **Review release** → **Start rollout to Internal testing**

Google reviews this typically within a few hours. You'll get an email when it's live.

### 3.5 Share the opt-in link

Once approved, Play Console shows an opt-in URL. Send it to testers. They click it, accept the invitation, install MedUnity from the Play Store (not the APK).

---

## Phase 4 — Moving to Closed Testing (~1 week later)

Prerequisites:
1. Zero unresolved Crashlytics crashes for 7 consecutive days
2. At least 3 different Android versions / OEMs tested
3. 20+ real testers added to the Closed track (required to graduate to Production later)
4. `medunity-backend.service` healthy under load (`journalctl -u medunity-backend --since '7 days ago' | grep -i error` clean)

### Then:

1. **Testing → Closed testing → Create track** (name: "Beta")
2. Promote the reviewed Internal release, OR upload a fresh `1.1.0 (Closed)` release
3. Add the 20+ testers
4. Roll out

---

## Phase 5 — Before Production (NOT yet)

Before promoting to Production track:
1. **Disable OTP test bypass** in `backend/.env`:
   ```
   OTP_TEST_PHONES=
   OTP_TEST_CODE=
   ```
2. **Disable SOS throttle bypass** in `backend/sos/views.py` — remove `prof.id ≤ 20` guard.
3. Restart `medunity-backend`.
4. Update App Access in Play Console to remove the test-phone block.
5. Switch SQLite → Postgres if not already.
6. 14-day soak on Closed Testing with no critical crashes.

---

## Files in this directory

| File | Purpose |
|---|---|
| `STORE_LISTING.md` | Copy-paste content for Play Console store listing |
| `DATA_SAFETY.md` | Exact answers for the Data Safety form |
| `CONTENT_RATING.md` | Exact answers for the IARC questionnaire |
| `hosted/privacy.html` | Privacy Policy hosted at trusmiledentist.in/medunity/privacy/ |
| `hosted/terms.html` | Terms of Use hosted at trusmiledentist.in/medunity/terms/ |
| `PUBLISHING.md` | This file |

---

## Things that will bite you (common mistakes)

1. **Forgetting to back up the keystore** — do it twice, in different places (cloud + USB). Single most catastrophic mistake.
2. **Uploading the debug AAB** — always `--release`. Debug build is rejected by Play Console.
3. **Skipping the release-APK smoke test** — R8 minification can break reflection-based code that works in debug.
4. **Wrong applicationId** — must be `in.areafair.medunity` (generated by `flutter create --org=in.areafair --project-name=medunity`). Don't override.
5. **Forgetting Firebase SHA-1** — both the **debug** and **release** SHA-1 fingerprints must be added in Firebase Console for Phone Auth and FCM to work.
6. **Missing Crashlytics opt-in** — SDK is wired but Firebase Console requires a one-time "Get started" click in Build → Crashlytics. Without it, uploads are silently dropped.
7. **Production launch with test bypass active** — `OTP_TEST_PHONES` and `OTP_TEST_CODE` must be empty in `.env` before Production track. Closed Testing is fine.
