# CLAUDE.md — MedUnity Flutter App

AI-assistant guidance for the Flutter source in `app/`. Read this before touching any file under `app/lib/`.

## What this is

Flutter Android app for the MedUnity verified-doctor network. Verified medical professionals only
(gated by admin review). Features: SOS emergency dispatch, local doctor circles, consultant
booking, equipment co-purchase/marketplace, practice support, brownie-points gamification,
vendor directory.

**Build host:** Flutter SDK is NOT installed on the VPS. All builds run on the Windows machine.
The VPS is for editing source and pushing to GitHub. Windows `git pull`s and runs
`flutter pub get` / `flutter run` / `flutter build appbundle`.

**Always `git push origin main` after committing on the VPS** — otherwise Windows builds stale code.

## Companion backend

Django 5 + DRF + SimpleJWT at `/home/drriyazq/medunity/backend/`. Live at
`https://medunity.areafair.in` (port 8009). Full API surface in `backend/api/urls.py`.
JWT access token in `Authorization: Bearer <token>` header on every authenticated request.

## First-time Windows setup

See [README.md](README.md) for the full step-by-step. Short version:

```bat
:: From repo root, cd into app/
flutter create --org=in.areafair --project-name=medunity .
flutter pub get
flutter run
```

**applicationId:** `in.areafair.medunity` — generated correctly by `flutter create`, no manual fix needed.

**Firebase (after flutter create):**
- `android/settings.gradle.kts` → add `id("com.google.gms.google-services") version "4.4.2" apply false` to `plugins { … }`
- `android/app/build.gradle.kts` → add `id("com.google.gms.google-services")` to `plugins { … }`
- Place `google-services.json` (from Firebase Console, project `medunity`) at `android/app/google-services.json`
- Place `firebase-credentials.json` (service-account key) at `backend/firebase-credentials.json`

**This is the same Kotlin DSL placement as SureDataPro:** version goes in `settings.gradle.kts`,
bare `id(…)` goes in app-level `build.gradle.kts`. Do NOT add it to a project-level `build.gradle.kts`
(the modern Flutter scaffold doesn't have one).

## Architecture

```
lib/
├── main.dart                   # Entry: Firebase init → Hive init → ProviderScope → MedUnityApp
├── app.dart                    # GoRouter definition + routerProvider + MedUnityApp (ConsumerWidget)
├── theme.dart                  # MedUnityColors + MedUnityTheme.light()
├── data/
│   ├── api/client.dart         # Dio + JWT Bearer interceptor
│   └── local/hive_setup.dart   # Hive init + AES-256 encryption key
├── state/
│   └── auth_provider.dart      # Riverpod StateNotifier — AuthStatus FSM
├── services/
│   └── push_service.dart       # FCM wrapper — SOS high-priority push + navigation
└── features/
    ├── auth/                   # phone_signin, pending_verification, rejection screens
    ├── consent/                # consent_screen (shown before auth)
    ├── onboarding/             # profile_setup_screen (after Firebase token)
    ├── home/                   # home_shell.dart — ShellRoute bottom nav (5 tabs)
    ├── home_screen/            # home_screen.dart — points card, quick nav, previews
    ├── sos/                    # category_sheet, sos_countdown, sos_status, incoming_sos
    ├── circles/                # circles_screen, circle_detail, post_detail, create_circle_sheet
    ├── consultants/            # consultants_screen, availability_toggle, find_consultants_tab, bookings_tab, review_sheet, consultant_profile
    ├── equipment/              # equipment_screen, pools_tab, marketplace_tab, pool_detail, listing_detail, my_listings
    ├── support/                # support_screen, requests_tab, leaderboard_screen
    ├── vendors/                # vendors_screen, vendor_detail
    └── profile/                # profile_screen
```

## Auth flow (AuthStatus FSM)

```
loading → loggedOut → (Firebase OTP) → tokenIssued → (profile setup) → pendingVerification
                                                                              ↓ (admin approves)
                                                                           verified
                                                              (admin rejects) ↓
                                                                           rejected
```

Router in `app.dart` redirects based on status. SOS routes require `verified`; all others redirect
to `/signin` when `loggedOut`.

## State management

**Riverpod only.** Providers live close to their feature (`*_provider.dart` files). `authProvider`
is a global `StateNotifier<AuthState>`. Do not introduce BLoC or `provider` package — Riverpod is
the chosen library for MedUnity (SureDataPro uses `provider`; MedUnity/SmartStep/KidsImaan use Riverpod).

## Routing

`go_router` with a `ShellRoute` for the 5-tab bottom nav (`/home`, `/circles`, `/consultants`,
`/marketplace`, `/profile`). SOS screens (`/sos/*`) are full-screen routes outside the shell.
`routerProvider` is in `app.dart`; router rebuilds when `authProvider` changes via `_AuthListenable`.

## Local storage

- `hive_flutter` + AES-256 box for lightweight persistent state (tokens, profile cache).
- `flutter_secure_storage` for secrets that must survive app reinstall on Android (JWT token).

## Push notifications (FCM)

`services/push_service.dart` wraps FCM. SOS alerts arrive as high-priority FCM messages; the
handler calls `setPushNavigate` to push the `/sos/incoming/:alertId` route. Init failure is
non-fatal — app still launches with push disabled. Firebase must be initialised in `main.dart`
before `runApp`.

## Key packages

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Navigation |
| `dio` | HTTP with JWT interceptor |
| `hive_flutter` + `hive` | Local cache |
| `flutter_secure_storage` | Token storage (Android Keystore) |
| `firebase_core` + `firebase_messaging` + `firebase_auth` | Firebase Phone Auth + FCM |
| `flutter_local_notifications` | SOS foreground notification |
| `google_maps_flutter` | Consultant/SOS maps |
| `geolocator` + `permission_handler` | Location for SOS radius + consultant search |
| `image_picker` | Profile photo + equipment listing images |
| `intl` | Date formatting |
| `package_info_plus` | App version for device registration |

## Things to avoid

- Do not introduce `provider` package — Riverpod is already in place.
- Do not add offline SQLite/Hive sync cache beyond what already exists — MedUnity is online-only for MVP.
- Do not build a web or iOS target — Android only for MVP.
- Do not add Red Flag Registry features — deferred indefinitely (legal review pending).
