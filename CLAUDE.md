# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MedUnity — verified-doctor Android network for India. Monorepo with two parts:

- `backend/` — Django 5 + DRF + SimpleJWT REST API (port 8009 in dev, gunicorn in prod). Public via Nginx proxy at `https://trusmiledentist.in/medunity-api/` → `127.0.0.1:8009/api/v1/`.
- `app/` — Flutter Android app (Riverpod + go_router). The `android/` folder is **not committed** — Windows generates it via `flutter create`. See `app/CLAUDE.md` and `app/README.md` for the full Flutter workflow.

Edits happen on the VPS; Windows is build-only. Always `git push origin master` after committing or Windows builds stale code.

---

## Commands

### Backend (always from `backend/`)

```bash
cd /home/drriyazq/medunity/backend

# Dev server (writes to logs/dev.log)
nohup bash -c 'DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py runserver 0.0.0.0:8009' >> logs/dev.log 2>&1 &

# Migrations
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py makemigrations
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py migrate

# Shell (use for ad-hoc data fixes — there's no admin UI for everything)
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell

# Tail logs
tail -f logs/dev.log logs/medunity.log

# Production deploy script (one-shot, idempotent)
sudo bash deploy/setup.sh

# No test suite. tests.py files are stubs.
```

`runserver` auto-reloads on `.py` changes. There's no separate "reload" command — file save is enough.

### Flutter app

VPS edits are committed and pushed; Windows pulls and builds. See `app/README.md` for the full Windows workflow. The `android/` folder is generated locally via `flutter create --org=in.areafair --project-name=medunity .` — never committed.

---

## Architecture

### Auth flow (Firebase Phone Auth → JWT)

1. Flutter calls `FirebaseAuth.verifyPhoneNumber()` → user enters OTP → gets a Firebase ID token.
2. App POSTs `{id_token}` to `/api/v1/auth/firebase/`.
3. Backend verifies via `firebase_admin.auth.verify_id_token`, looks up or creates a Django `User` with `username = "firebase_<uid>"`, returns a SimpleJWT access + refresh pair.
4. Every subsequent request: `Authorization: Bearer <access>`. App stores tokens in encrypted Hive (`HiveSetup.sessionBox`) — backed by Android Keystore via flutter_secure_storage.
5. **`IsAdminVerified` is the default permission** for all post-onboarding endpoints (`accounts/permissions.py`). A doctor cannot use any feature until an admin flips `MedicalProfessional.is_admin_verified=True`. The Flutter `AuthStatus` FSM (`loading → loggedOut → tokenIssued → pendingVerification → verified | rejected`) gates the UI.

**India testing constraint:** Firebase cannot send real SMS in India. Always use **test phone numbers** added in Firebase Console → Authentication → Sign-in method → Phone → Test phone numbers. The Flutter app sets `appVerificationDisabledForTesting=true` in `kDebugMode` so test numbers work without SHA-1 fingerprint registration. Production builds will need the real signing-cert SHA-1 in Firebase.

### Backend apps and what they own

URL mount points are in `backend/medunity/urls.py`. Every app exposes its own `urls.py` mounted under `/api/v1/<app>/`.

| App | Owns | Notable models / endpoints |
|---|---|---|
| `accounts` | Auth, profile, clinic, FCM device tokens | `MedicalProfessional` (1:1 `User`), `Clinic` (1:1 `MedicalProfessional`), `DeviceToken` (M:N user). Endpoints: `/auth/firebase/`, `/auth/profile/` (multipart), `/auth/me/`, `/auth/me/clinic-location/`, `/auth/verification-status/`, `/auth/devices/{register,unregister}/` |
| `sos` | Emergency dispatch | `SosAlert`, `SosResponse`. `find_nearby_clinics(lat, lng, exclude)` does auto-radius 1→2→5 km until ≥3 hits. **Sender-selected recipients:** `GET /sos/nearby-doctors/?lat=&lng=` lists candidates; `POST /sos/send/` accepts optional `recipient_ids[]` to filter the FCM fan-out. Throttle: 3 SOS / 24h per professional. |
| `circles` | Local doctor groups | `Circle` (geo-anchored), `CircleMembership`, `CirclePost`, `PostComment`. Auto-suggest joins by haversine. |
| `consultants` | Visiting consultant network | `ConsultantAvailability` (toggle on/off + lat/lng), `ConsultantBooking`, `ConsultantReview` (two-way) |
| `equipment` | Co-purchase + marketplace | `EquipmentPool`, `PoolMembership`, `PoolUsageSlot`, `MarketplaceListing`, `ListingInquiry` |
| `support` | Coverage requests + gamification | `CoverageRequest`, `BrowniePoint`. Points awarded via `post_save` signal in `support/AppConfig.ready`: SOS-accept → +10, coverage-accept → +15. |
| `vendors` | Crowd-sourced lab/dealer directory | `Vendor`, `VendorReview`, `VendorFlag`. Dedup uses `rapidfuzz` on submission. |
| `api` | Health check only | `/api/v1/health/` |

### Cross-app conventions

- **Geo math** lives in `sos/models.py` — `haversine_km()` and `find_nearby_clinics()` are imported by other apps (e.g. `circles/models.py`). There is no PostGIS dependency; everything is raw-SQL Haversine.
- **No serializer shortcuts.** Each app has its own `serializers.py` and views are `@api_view` function-based (no ViewSets). Multipart uploads (profile docs, listing images) use `parser_classes([MultiPartParser, FormParser])`.
- **Soft-delete is not used.** Deletes are real. Privacy-sensitive cascades (e.g. SOS responses on alert delete) rely on Django's default ON DELETE CASCADE.
- **Celery is wired but light-touch.** `celery_app.py` autodiscovers `tasks.py` per app; today only `accounts/tasks.py::notify_verification_decision` is called (admin verifies/rejects → push to user). Broker is Redis DB 2 (`REDIS_URL=redis://localhost:6379/2`). If you add a task, make sure the celery worker is actually running (`innercircle-celery`-style systemd unit not yet provisioned for medunity).
- **FCM:** `medunity/fcm.py::send_push_notification` is the single fan-out point. SOS uses `priority='high'` + `channel_id='sos_critical'` + `sound='siren'`. Service-account JSON path is `FIREBASE_CREDENTIALS_PATH` (defaults to `backend/firebase-credentials.json`, gitignored).

### Settings layout

`backend/medunity/settings/{base,dev,prod}.py`. Always set `DJANGO_SETTINGS_MODULE=medunity.settings.dev` (or `prod`). Env via django-environ from `backend/.env`. Public access requires both `ALLOWED_HOSTS` (currently `localhost, 127.0.0.1, 187.127.134.77, trusmiledentist.in` in dev) and `ufw allow 8009`.

### Mobile carrier gotcha

Indian mobile carriers (Jio/Airtel) block direct connections to non-standard ports like 8009. The Flutter app **must** hit the Nginx-proxied URL `https://trusmiledentist.in/medunity-api/` on phone testing — direct `http://187.127.134.77:8009/` will time out. The proxy lives in `/etc/nginx/sites-enabled/trusmile` (location block: `/medunity-api/ → http://127.0.0.1:8009/api/v1/`).

### Flutter side (high level)

Riverpod `StateNotifier` + `go_router` shell route with 5 tabs (Home / Circles / Consult / Market / Profile). SOS routes live outside the shell as full-screen flows. The detailed Flutter architecture is in `app/CLAUDE.md`. Key cross-cutting points relevant to backend work:

- API base URL: `String.fromEnvironment('API_BASE_URL', defaultValue: 'https://trusmiledentist.in/medunity-api')`. Override per build with `--dart-define`.
- Hive box `medunity_session` (encrypted) holds `access_token`, `refresh_token`, `consent_accepted`, `profile_setup_draft`, `fcm_token`. Don't store anything else there without considering its privacy class.

---

## Things to avoid

- **Don't add Celery tasks unless you're prepared to run a worker.** Today the worker is intermittently absent in dev — synchronous code paths must not silently degrade if a task never executes.
- **Don't bypass `IsAdminVerified`.** New endpoints default to it. If a feature must be reachable pre-verification (e.g. profile creation, location capture), explicitly opt out per-view.
- **Don't store phone numbers on `User`.** The Django `User.username` is `firebase_<uid>` and `email` is `<uid>@medunity.firebase`. The phone number stays in Firebase only — pulling it server-side requires `firebase_admin.auth.get_user(uid).phone_number`.
- **Don't broadcast SOS without selection.** The recipient picker (`select_recipients_screen.dart` → `recipient_ids[]`) is the supported flow. The legacy "all nearby" path still works server-side for backward compat but the app should never send without `recipient_ids`.
- **Don't introduce PostGIS.** Geo queries are intentionally raw-SQL Haversine over Python lists. The current dataset size makes this fine and keeps deploys simple.
