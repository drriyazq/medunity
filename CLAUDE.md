# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MedUnity — verified-doctor Android network for India. Monorepo with two parts:

- `backend/` — Django 5 + DRF + SimpleJWT REST API. Runs as `medunity-backend.service` (gunicorn 127.0.0.1:8009) + `medunity-celery.service`. Public via Nginx proxy at `https://trusmiledentist.in/medunity-api/` → `127.0.0.1:8009/api/v1/`. Admin at `https://trusmiledentist.in/medunity-admin/` (note: **not** `/admin/` — that path is the cross-project hub).
- `app/` — Flutter Android app (Riverpod + go_router). The `android/` folder is **not committed** — Windows generates it via `flutter create`. See `app/CLAUDE.md` and `app/README.md` for the Flutter workflow.

Edits happen on the VPS; Windows is build-only. Always `git push origin master` after committing or Windows builds stale code.

---

## Commands

### Backend (always from `backend/`)

```bash
cd /home/drriyazq/medunity/backend

# Reload prod backend after .py edits (no sudo needed for HUP, but systemctl is cleanest)
sudo systemctl restart medunity-backend
# or for a hot reload without dropping connections:
kill -HUP $(pgrep -f "gunicorn.*medunity" | head -1)

# Service logs
sudo journalctl -u medunity-backend -u medunity-celery -f

# Migrations / shell — DJANGO_SETTINGS_MODULE is REQUIRED, no default
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py makemigrations
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py migrate
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell

# Re-seed the 10 dummy associate doctors near Riya (idempotent)
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python seed_dummy_doctors.py

# Production install (one-shot; do NOT re-run casually)
sudo bash deploy/setup.sh        # initial systemd + nginx + collectstatic
sudo bash deploy/finalize.sh     # Phase-1 prod switch + privacy/terms hosting

# No test suite. tests.py files are stubs.
```

The systemd unit runs with `DJANGO_SETTINGS_MODULE=medunity.settings.prod` and `EnvironmentFile=backend/.env`. Local one-off commands need the explicit `DJANGO_SETTINGS_MODULE=` prefix — there's no default.

### Flutter app

VPS edits are committed and pushed; Windows pulls and builds. See `app/README.md` for the full Windows workflow. The `android/` folder is generated locally via `flutter create --org=in.areafair --project-name=medunity .` — never committed.

---

## Architecture

### Auth flow — dual path (India vs non-India)

Firebase SMS does not reliably deliver to Indian carriers. The app branches on country code:

**+91 (India) — WhatsApp OTP path:**
1. Flutter calls `authProvider.notifier.sendWhatsappOtp(phone)` → `POST /auth/otp/send/` (204).
2. Backend generates a 6-digit code, stores in Redis (`medunity:otp:<E164>`, 5-min TTL, 5-attempt cap via `accounts/otp.py`), sends via Meta Graph API using the `medunity_login_otp` auth template (`accounts/whatsapp.py`). Failed sends are logged in `OtpDeliveryLog`.
3. Flutter calls `verifyWhatsappOtp(phone, code)` → `POST /auth/otp/verify/`. Backend looks up or creates `User(username="phone_<E164>")`, returns a SimpleJWT pair.

**Non-India — Firebase fallback:**
1. Flutter calls `FirebaseAuth.verifyPhoneNumber()` → user enters OTP → Firebase ID token.
2. App POSTs `{id_token}` to `/auth/firebase/`. Backend calls `firebase_admin.auth.verify_id_token`, creates `User(username="firebase_<uid>")`, returns SimpleJWT pair.

**Shared from here:**
4. Every subsequent request: `Authorization: Bearer <access>`. Tokens stored in encrypted Hive (`HiveSetup.sessionBox`) via flutter_secure_storage.
5. **`IsAdminVerified` is the default permission** for all post-onboarding endpoints (`accounts/permissions.py`). Doctor cannot use any feature until admin flips `MedicalProfessional.is_admin_verified=True`. Flutter `AuthStatus` FSM: `loading → loggedOut → tokenIssued → pendingVerification → verified | rejected`.

**Dev test bypass:** `OTP_TEST_PHONES=+919867933139,+919967406651` and `OTP_TEST_CODE=123456` in `backend/.env`. Send returns 204 without contacting WhatsApp; verify accepts the hardcoded code. **Must be cleared before Production track** (Closed Testing keeps the bypass on for the Play reviewer). WhatsApp creds (`WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`) live in `.env`.

### Backend apps and what they own

URL mount points are in `backend/medunity/urls.py`. Each app exposes its own `urls.py` mounted under `/api/v1/<app>/`. Note the dual mount of `associates`: `/api/v1/associates/` (marketplace) + `/api/v1/reviews/` (global doctor-to-doctor reviews — separate URL conf at `associates/urls_reviews.py`).

| App | Owns | Notable models / endpoints |
|---|---|---|
| `accounts` | Auth, profile, clinic, FCM device tokens, multi-role | `MedicalProfessional` (1:1 `User`), `Clinic` (1:1 `MedicalProfessional`), `DeviceToken`, `OtpDeliveryLog`. Endpoints: `/auth/otp/{send,verify}/`, `/auth/firebase/`, `/auth/profile/` (multipart), `/auth/me/`, `/auth/me/clinic-location/` (returns **HTTP 423** if `Clinic.location_locked=True`), `/auth/verification-status/`, `/auth/devices/{register,unregister}/` |
| `sos` | Emergency dispatch | `SosAlert`, `SosResponse`, `SosRecipient` (one row per (alert, professional) so recipients can see their incoming history). `find_nearby_clinics(lat, lng, exclude)` does auto-radius 1→2→5 km until ≥3 hits. Sender-selected recipients: `GET /sos/nearby-doctors/?lat=&lng=` lists candidates; `POST /sos/send/` accepts `recipient_ids[]` to filter the FCM fan-out. Throttle: 3 SOS / 24h per professional, **bypassed for `MedicalProfessional.id ≤ 20`** (founding/test accounts — clear before Production). |
| `circles` | Local doctor groups | `Circle` (geo-anchored), `CircleMembership`, `CirclePost`, `PostComment`. Auto-suggest joins by haversine. |
| `consultants` | Visiting consultant network | `ConsultantAvailability` (toggle on/off + lat/lng), `ConsultantBooking`, `ConsultantReview` (two-way). Per-patient flow — conceptually separate from `AssociateBooking`. |
| `equipment` | Co-purchase + marketplace | `EquipmentPool`, `PoolMembership`, `PoolUsageSlot`, `MarketplaceListing`, `ListingInquiry` |
| `support` | Coverage requests + gamification | `CoverageRequest`, `BrowniePoint`. Points awarded via `post_save` signal in `support/AppConfig.ready`: SOS-accept → +10, coverage-accept → +15. |
| `vendors` | Crowd-sourced lab/dealer directory | `Vendor`, `VendorReview`, `VendorFlag`. Dedup uses `rapidfuzz` on submission. |
| `associates` | Paid temp clinic coverage marketplace + global doctor reviews | `AssociateProfile` (1:1 `MedicalProfessional`, owns `is_available_for_hire` + `rate_per_slot/day` + `travel_radius_km`), `AssociateBooking` (lifecycle `pending → connected | declined | cancelled`; phones revealed only when `connected`), `ProfessionalReview` (`unique_together=('reviewer','reviewee','context')`). Routes: `/api/v1/associates/{me,me/toggle,search,bookings,bookings/<id>,<prof_id>}/` + `/api/v1/reviews/{,<pk>,of/<prof_id>,mine/of/<prof_id>}/` |
| `api` | Health check only | `/api/v1/health/` |

### Locked design decisions for the associates feature (don't second-guess)

- **No money flow.** Rates are display text. Bookings are connection signals — once `connected`, both phones are revealed and the parties settle privately. Don't add Razorpay / escrow / GST. The user explicitly said "we don't have money."
- **Reviews are anyone-to-anyone, not booking-gated.** Any verified `MedicalProfessional` can rate any other in any context. Resubmit overwrites the existing row via `update_or_create` on (reviewer, reviewee, context).
- **Public-anonymous, admin-knows.** Reviewer FK is stored on `ProfessionalReview` for admin audit but **never** exposed in any API response. Don't add `reviewer` to `ProfessionalReviewSerializer`.
- **`AssociateBookingSerializer.get_associate_phone` and `get_hiring_clinic_phone` return `''` whenever `status != 'connected'`.** The Flutter booking detail screen relies on this — don't show the Call button when phone is empty.
- **Search rule.** Top 30 within the *associate's* `travel_radius_km` (not the searcher's). Default sort distance, options `rate` / `rating`.

### Multi-role on MedicalProfessional

`ROLE_CHOICES = [clinic_owner, hospital_owner, visiting_consultant, associate_doctor]`. Two fields coexist on `MedicalProfessional`:

- `role: CharField` — single primary role, retained for back-compat with legacy onboarding. Don't write to it from new code.
- `roles: JSONField` (default `[]`) — **canonical multi-select**. New code reads/writes here. Validation against `VALID_ROLE_KEYS` in `accounts/models.py`.

### Cross-app conventions

- **Geo math** lives in `sos/models.py` — `haversine_km()` and `find_nearby_clinics()` are imported by other apps (e.g. `circles/models.py`). No PostGIS dependency; raw-SQL Haversine over Python lists. Don't introduce PostGIS — current dataset size makes this fine and keeps deploys simple.
- **No serializer shortcuts.** Each app has its own `serializers.py` and views are `@api_view` function-based (no ViewSets). Multipart uploads (profile docs, listing images) use `parser_classes([MultiPartParser, FormParser])`.
- **Soft-delete is not used.** Deletes are real. Privacy-sensitive cascades rely on Django's default ON DELETE CASCADE.
- **Celery worker IS running** as `medunity-celery.service` (Redis DB 2 broker). `celery_app.py` autodiscovers `tasks.py` per app; today only `accounts/tasks.py::notify_verification_decision` is wired (admin verifies/rejects → push to user). New tasks are safe to add — the worker is up.
- **FCM:** `medunity/fcm.py::send_push_notification` is the single fan-out point. SOS uses `priority='high'` + `channel_id='sos_critical'` + `sound='siren'`. Lazy-inits Firebase Admin SDK before first send (don't rely on app startup). Service-account JSON path is `FIREBASE_CREDENTIALS_PATH` (defaults to `backend/firebase-credentials.json`, gitignored).

### Settings layout

`backend/medunity/settings/{base,dev,prod}.py`. Always set `DJANGO_SETTINGS_MODULE=medunity.settings.dev` (or `prod`) for local commands — no default. Env via django-environ from `backend/.env`. Public access requires both `ALLOWED_HOSTS` (currently `localhost, 127.0.0.1, medunity.areafair.in, trusmiledentist.in, www.trusmiledentist.in` in prod `.env`) and Nginx routing — never bind `0.0.0.0:8009` in prod (gunicorn binds to `127.0.0.1:8009`).

### Mobile carrier gotcha

Indian mobile carriers (Jio/Airtel) block direct connections to non-standard ports like 8009. The Flutter app **must** hit the Nginx-proxied URL `https://trusmiledentist.in/medunity-api/` on phone testing — direct `http://187.127.134.77:8009/` will time out. The proxy lives in `/etc/nginx/sites-enabled/trusmile` (location block: `/medunity-api/ → http://127.0.0.1:8009/api/v1/`).

### Flutter side (high level)

Riverpod `StateNotifier` + `go_router` shell route with 5 tabs (Home / Circles / Consult / Market / Profile). SOS routes live outside the shell as full-screen flows. Detailed Flutter architecture is in `app/CLAUDE.md`. Cross-cutting points relevant to backend work:

- API base URL: `String.fromEnvironment('API_BASE_URL', defaultValue: 'https://trusmiledentist.in/medunity-api')`. Override per build with `--dart-define`.
- Hive box `medunity_session` (encrypted) holds `access_token`, `refresh_token`, `consent_accepted`, `profile_setup_draft`, `fcm_token`. Don't store anything else there without considering its privacy class.
- Lib layout: `lib/features/<domain>/` — one folder per backend app (`auth`, `sos`, `circles`, `consultants`, `equipment`, `support`, `vendors`, `associates`, plus `consent`, `home`, `home_screen`, `onboarding`, `profile`).

---

## Things to avoid

- **Don't use `nohup runserver` on this VPS.** That recipe is dead — backend is on `medunity-backend.service`. Restart with `sudo systemctl restart medunity-backend` (or `kill -HUP $(pgrep -f "gunicorn.*medunity" | head -1)` for hot reload). Old memory snippets / docs may still mention runserver; ignore them.
- **Don't bypass `IsAdminVerified`.** New endpoints default to it. If a feature must be reachable pre-verification (profile creation, location capture), explicitly opt out per-view.
- **Two username conventions — don't mix them up.** Firebase path: `username="firebase_<uid>"`, `email="<uid>@medunity.firebase"`. WhatsApp OTP path: `username="phone_<E164>"`, `email="<E164-no-plus>@medunity.phone"`. All profile-lookup views use `MedicalProfessional.objects.get(user=request.user)` (OneToOne) — never look up by `firebase_uid` directly.
- **Don't broadcast SOS without selection.** The recipient picker (`select_recipients_screen.dart` → `recipient_ids[]`) is the supported flow. The legacy "all nearby" path still works server-side for backward compat but the app should never send without `recipient_ids`.
- **Respect `Clinic.location_locked`.** `/auth/me/clinic-location/` returns HTTP 423 when set. Used to pin the Test Doctor's clinic at (19.1352, 72.8448) so two physically-co-located test phones can still trigger SOS fan-out.
- **Don't add `reviewer` to `ProfessionalReviewSerializer`.** Reviewer identity is admin-audit-only; exposing it would break the public-anonymous design.
- **Don't write to `MedicalProfessional.role` from new code.** Use `roles` (JSONField). The single `role` field is back-compat only.

## Critical reminders before Production track (NOT closed testing)

- Empty `OTP_TEST_PHONES` and `OTP_TEST_CODE` in `backend/.env`, restart `medunity-backend`.
- Remove the `prof.id ≤ 20` SOS throttle bypass in `backend/sos/views.py` (or set the threshold to `0`).
- Remove the App Access reviewer block from Play Console.
- Switch SQLite → PostgreSQL (`DATABASE_URL` in `.env`).
- 14-day soak on Closed Testing with no critical Crashlytics issues.
