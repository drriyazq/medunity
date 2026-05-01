# Play Console — Data Safety Form Answers

Answer these exactly when filling the **Data Safety** section in the Play Console. Every answer reflects the app as built (verified-only access, TLS-only transport, AES-256 token storage on device, no third-party data sharing).

---

## Does your app collect or share any of the required user data types?
**Yes.**

## Is all of the user data collected by your app encrypted in transit?
**Yes.** All API traffic uses HTTPS with TLS 1.2+. WhatsApp OTP delivery uses Meta Graph API over HTTPS. Firebase services (Auth, FCM, Crashlytics) are HTTPS by default.

## Do you provide a way for users to request that their data is deleted?
**Yes.** Logout from the Profile screen wipes all locally stored data (tokens, profile cache). Server-side deletion can be requested by emailing `drdentalmail@gmail.com` from the registered phone number; we delete within 30 days.

---

## Data types collected

### Personal info

| Data type | Collected? | Required/Optional | Purpose | Shared with third parties? | Encrypted in transit? | User can request deletion? |
|---|---|---|---|---|---|---|
| Name | Yes (full name) | Required | Account; verification; identifying responder/sender on SOS | No | Yes | Yes |
| Email address | Not collected | — | — | — | — | — |
| User IDs | Yes (server-side `User.id`, `MedicalProfessional.id`) | Required | Account functionality | No | Yes | Yes |
| Address | Yes (clinic address, city) | Required | Find-nearby (SOS, consultant, circles) | No | Yes | Yes |
| Phone number | Yes | Required | Authentication (WhatsApp OTP for +91; Firebase Phone Auth otherwise) | No | Yes | Yes |
| Other info | Yes (medical registration number, council, qualifications, specialty) | Required | Verification gate | No | Yes | Yes |

### Health & fitness
- None collected.

### Financial info
- None collected. (Equipment co-purchase pools track membership and contribution markers but no payment info — settlement happens off-app.)

### Location

| Data type | Collected? | Purpose |
|---|---|---|
| Approximate location | Yes | Local circles auto-suggest |
| Precise location | Yes | SOS broadcast radius, clinic location, consultant find-nearby |

Location is sampled **on demand only** (when sending SOS, opening the find-nearby map, or pinning the clinic). MedUnity does **not** run background location collection.

### Messages
- None collected. The app does not read SMS, contacts, or any external messages. (Circle posts and comments are user-generated content the user types into the app and are stored on our servers — see *App activity* below.)

### Photos and videos
- Profile photo (optional)
- Marketplace listing photos (optional)
- Verification documents (medical registration certificate, optional photo of degree / clinic permit)

All collected for the stated purpose only. Not shared with third parties.

### Files and docs
- Verification documents (PDF or image) — required for the verification gate

### Calendar, Contacts, Call logs
- None collected.

### App activity

| Data type | Collected? | Purpose |
|---|---|---|
| App interactions | Yes — feature usage events server-side | Analytics |
| In-app search history | Not collected |
| Installed apps | Not collected |
| Other user-generated content | Yes — circle posts, comments, vendor reviews, consultant reviews, marketplace listing descriptions, SOS category text | Core feature |

User-generated content stays on our servers and is visible only to verified MedUnity users (and only inside the relevant circle / context).

### Web browsing
- Not collected.

### Device or other IDs

| Data type | Collected? | Purpose |
|---|---|---|
| Device ID / FCM token | Yes (stored in `DeviceToken` table) | Push notifications (SOS, verification status) |

### Diagnostics (Firebase Crashlytics)

| Data type | Collected? | Purpose | Required? |
|---|---|---|---|
| Crash logs | Yes | Crash diagnostics | Optional; release builds only |
| Diagnostics | Yes (stack traces) | Performance + stability | Optional |

Crashlytics collects: device model, OS version, app version, stack trace. No name, phone number, registration number, or location is logged.

---

## Data sharing

**Do you share any of the collected data with third parties?**

**No** — MedUnity does not share user data with third parties for advertising, analytics, marketing, or any other purpose.

The following are **service providers**, not third parties (covered by their respective platform-data terms):
- **Google Firebase** (Auth, FCM, Crashlytics) — auth, push, crash diagnostics
- **Meta WhatsApp Business Cloud API** — OTP delivery to +91 phones (uses an approved Authentication template)
- **Google Maps Platform** — map rendering for SOS, consultant, and circles screens

---

## Security practices

- Data is encrypted in transit (HTTPS / TLS 1.2+)
- JWT tokens on device are stored in `flutter_secure_storage` (Android Keystore)
- Local Hive cache (profile, FCM token, drafts) is encrypted with AES-256 using a Keystore-protected key
- Verified-only access — every account passes manual document review before any feature is reachable
- Users can request data deletion via email; we respond within 30 days
- Independent security review: not yet

---

## Target audience & content

### Who is this app primarily for?
**Adults 18+ only** — specifically licensed medical professionals. There is no child-facing content.

### Does your app include content appropriate for children?
**No.**

### Children's ads policy
N/A — app is not directed at children.

---

## Ads declaration

**Does your app contain ads?** **No.**

---

## App Access (for Play reviewers)

The app is gated by a manual admin verification step. To let Google reviewers test the full app without waiting on document review, two test phone numbers are pre-verified and bypass OTP delivery:

```
Reviewer test credentials (Internal/Closed Testing only):

  Phone:  +91 9867933139    OTP code: 123456
  Phone:  +91 9967406651    OTP code: 123456

Both accounts are pre-verified and have full access to every feature including SOS.
SOS-throttle bypass is enabled for these accounts so reviewers can re-trigger SOS without limits.

After typing the phone number on the sign-in screen, tap "Send OTP".
A 6-digit field appears — enter 123456 — and the Home screen loads.
```

Add this verbatim into the **App access** field in Play Console. Keep the bypass active in production for the closed-testing phase only.
