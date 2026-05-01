import logging

from django.conf import settings
from django.contrib.auth.models import User
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework_simplejwt.tokens import RefreshToken

from . import otp as otp_store
from . import whatsapp as wa
from .models import Clinic, DeviceToken, MedicalProfessional, OtpDeliveryLog
from .serializers import (
    ClinicSerializer,
    DeviceTokenSerializer,
    MedicalProfessionalSerializer,
    MedicalProfessionalUpdateSerializer,
)

logger = logging.getLogger(__name__)


def _get_or_init_firebase():
    """Lazy Firebase init — credentials file may not be present in dev."""
    import firebase_admin
    from django.conf import settings
    from firebase_admin import credentials as fb_credentials

    if not firebase_admin._apps:
        from medunity.firebase_init import init_firebase
        init_firebase()
    return firebase_admin._apps


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
def firebase_auth_view(request):
    """
    Verify a Firebase Phone Auth ID token and return a Django JWT pair.
    Firebase UID is used as the username — phone numbers are never stored in auth.User.
    """
    from firebase_admin import auth as fb_auth

    id_token = request.data.get("id_token", "").strip()
    if not id_token:
        return Response({"detail": "id_token required."}, status=status.HTTP_400_BAD_REQUEST)

    _get_or_init_firebase()

    try:
        decoded = fb_auth.verify_id_token(id_token)
    except Exception as exc:
        logger.warning(f"[auth] Firebase token verification failed: {exc}")
        return Response({"detail": "Invalid or expired Firebase token."}, status=status.HTTP_401_UNAUTHORIZED)

    uid = decoded["uid"]
    phone = decoded.get("phone_number", "")

    user, created = User.objects.get_or_create(
        username=f"firebase_{uid}",
        defaults={"email": f"{uid}@medunity.firebase"},
    )

    profile_exists = MedicalProfessional.objects.filter(user=user).exists()

    refresh = RefreshToken.for_user(user)
    return Response({
        "refresh": str(refresh),
        "access": str(refresh.access_token),
        "profile_exists": profile_exists,
        "uid": uid,
    })


# ── WhatsApp OTP auth (India) ─────────────────────────────────────────────────


def _normalize_e164(raw: str) -> str:
    """Normalise to leading-+ E.164 (e.g. '+919867933139'). Returns '' if invalid."""
    if not raw:
        return ""
    s = raw.strip().replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    if s.startswith("00"):
        s = "+" + s[2:]
    if not s.startswith("+"):
        # Bare 10-digit Indian number → assume +91
        if s.isdigit() and len(s) == 10:
            s = "+91" + s
        else:
            s = "+" + s
    digits = s[1:]
    if not digits.isdigit() or not (8 <= len(digits) <= 15):
        return ""
    return s


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
def send_otp_view(request):
    """Generate a 6-digit OTP and send it via WhatsApp template.

    Body: {"phone": "+919867933139"}
    Returns 204 on success (no body — never echo the code).
    Test bypass: phones in settings.OTP_TEST_PHONES skip the WhatsApp send entirely.
    """
    phone = _normalize_e164(request.data.get("phone", ""))
    if not phone:
        return Response({"detail": "Valid phone (E.164) required."}, status=status.HTTP_400_BAD_REQUEST)

    if phone in settings.OTP_TEST_PHONES:
        # No code stored, no WhatsApp call — verify_otp_view accepts OTP_TEST_CODE directly.
        return Response(status=status.HTTP_204_NO_CONTENT)

    code = otp_store.generate_code()
    otp_store.store(phone, code)

    result = wa.send_otp_template(phone, code)
    OtpDeliveryLog.objects.create(
        phone=phone,
        template_name=settings.WHATSAPP_OTP_TEMPLATE_NAME,
        result_ok=result.get("ok", False),
        message_id=result.get("message_id", ""),
        error_message=result.get("error", "")[:2000],
        response_json=result.get("response", {}),
    )

    if not result.get("ok"):
        logger.warning(f"[otp] WhatsApp send failed for {phone}: {result.get('error')}")
        return Response(
            {"detail": "Could not send OTP. Please try again or use SMS-based sign-in."},
            status=status.HTTP_502_BAD_GATEWAY,
        )

    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@permission_classes([permissions.AllowAny])
def verify_otp_view(request):
    """Verify a code against the stored OTP and return a SimpleJWT pair.

    Body: {"phone": "+919867933139", "code": "123456"}
    Returns the same shape as firebase_auth_view: {refresh, access, profile_exists, uid}.
    `uid` here is the E.164 phone (used as the natural identity key for non-Firebase users).
    """
    phone = _normalize_e164(request.data.get("phone", ""))
    code = (request.data.get("code") or "").strip()
    if not phone or not code:
        return Response({"detail": "phone and code required."}, status=status.HTTP_400_BAD_REQUEST)

    test_bypass = (
        phone in settings.OTP_TEST_PHONES
        and settings.OTP_TEST_CODE
        and code == settings.OTP_TEST_CODE
    )
    if not test_bypass:
        result = otp_store.verify(phone, code)
        if result == otp_store.VerifyResult.WRONG_CODE:
            return Response({"detail": "Incorrect code."}, status=status.HTTP_400_BAD_REQUEST)
        if result == otp_store.VerifyResult.EXPIRED:
            return Response({"detail": "Code expired. Request a new OTP."}, status=status.HTTP_400_BAD_REQUEST)
        if result == otp_store.VerifyResult.TOO_MANY_ATTEMPTS:
            return Response(
                {"detail": "Too many wrong attempts. Request a new OTP."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )
        # else: VerifyResult.OK — fall through to JWT issue

    user, _ = User.objects.get_or_create(
        username=f"phone_{phone}",
        defaults={"email": f"{phone.lstrip('+')}@medunity.phone"},
    )

    prof = MedicalProfessional.objects.filter(user=user).first()
    if prof:
        prof.phone_verified_at = timezone.now()
        prof.save(update_fields=["phone_verified_at"])

    refresh = RefreshToken.for_user(user)
    return Response({
        "refresh": str(refresh),
        "access": str(refresh.access_token),
        "profile_exists": prof is not None,
        "uid": phone,
    })


# ── Profile + verification (shared by Firebase and WhatsApp paths) ────────────


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def create_profile(request):
    """First-time profile creation — multipart (includes license/degree doc uploads)."""
    if MedicalProfessional.objects.filter(user=request.user).exists():
        return Response({"detail": "Profile already exists. Use PATCH /auth/me/ to update."}, status=status.HTTP_409_CONFLICT)

    uid = _uid_from_user(request.user)  # may be None for WhatsApp-OTP users

    d = request.data

    required = ['full_name', 'role', 'medical_council', 'license_number', 'specialization',
                'clinic_name', 'clinic_address', 'clinic_city', 'clinic_state',
                'clinic_pincode', 'clinic_phone']
    missing = [f for f in required if not d.get(f)]
    if missing:
        return Response({"detail": f"Missing required fields: {', '.join(missing)}"}, status=status.HTTP_400_BAD_REQUEST)

    prof = MedicalProfessional.objects.create(
        user=request.user,
        firebase_uid=uid,
        phone=d.get('phone', ''),
        full_name=d['full_name'],
        email=d.get('email', ''),
        role=d['role'],
        medical_council=d['medical_council'],
        license_number=d['license_number'],
        specialization=d['specialization'],
        years_experience=d.get('years_experience') or None,
        qualification=d.get('qualification', ''),
        about=d.get('about', ''),
        profile_photo=request.FILES.get('profile_photo'),
        license_doc=request.FILES.get('license_doc'),
        degree_doc=request.FILES.get('degree_doc'),
        clinic_proof_doc=request.FILES.get('clinic_proof_doc'),
        verification_submitted_at=timezone.now(),
    )

    Clinic.objects.create(
        owner=prof,
        name=d['clinic_name'],
        address=d['clinic_address'],
        city=d['clinic_city'],
        state=d['clinic_state'],
        pincode=d['clinic_pincode'],
        phone=d['clinic_phone'],
        landline_phone=d.get('clinic_landline_phone', ''),
        website=d.get('clinic_website', ''),
    )

    return Response({
        "profile": MedicalProfessionalSerializer(prof).data,
        "status": "pending_verification",
    }, status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH"])
@permission_classes([permissions.IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def me(request):
    try:
        prof = MedicalProfessional.objects.select_related('clinic').get(user=request.user)
    except MedicalProfessional.DoesNotExist:
        return Response({"detail": "Profile not found."}, status=status.HTTP_404_NOT_FOUND)

    if request.method == "GET":
        return Response(MedicalProfessionalSerializer(prof).data)

    # PATCH — only non-credential fields
    serializer = MedicalProfessionalUpdateSerializer(prof, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response(MedicalProfessionalSerializer(prof).data)


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def set_clinic_location(request):
    """Update clinic GPS — required before SOS can be used."""
    try:
        prof = MedicalProfessional.objects.get(user=request.user)
        clinic = prof.clinic
    except (MedicalProfessional.DoesNotExist, Clinic.DoesNotExist):
        return Response({"detail": "Profile or clinic not found."}, status=status.HTTP_404_NOT_FOUND)

    if clinic.location_locked:
        return Response(
            {"detail": "Clinic location is locked and cannot be updated from the app."},
            status=status.HTTP_423_LOCKED,
        )

    lat = request.data.get('lat')
    lng = request.data.get('lng')
    if lat is None or lng is None:
        return Response({"detail": "lat and lng required."}, status=status.HTTP_400_BAD_REQUEST)

    try:
        from decimal import Decimal
        clinic.set_location(Decimal(str(lat)), Decimal(str(lng)))
    except Exception:
        return Response({"detail": "Invalid lat/lng values."}, status=status.HTTP_400_BAD_REQUEST)

    return Response(ClinicSerializer(clinic).data)


@api_view(["GET"])
@permission_classes([permissions.IsAuthenticated])
def verification_status(request):
    try:
        prof = MedicalProfessional.objects.get(user=request.user)
    except MedicalProfessional.DoesNotExist:
        return Response({"status": "no_profile"})

    return Response({
        "status": prof.verification_status,
        "reason": prof.rejection_reason or None,
        "submitted_at": prof.verification_submitted_at,
        "verified_at": prof.verified_at,
        "clinic_location_set": prof.clinic.lat is not None if hasattr(prof, 'clinic') else False,
    })


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def register_device(request):
    serializer = DeviceTokenSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    token = serializer.validated_data['token']
    DeviceToken.objects.update_or_create(
        token=token,
        defaults={
            'user': request.user,
            'platform': serializer.validated_data.get('platform', 'android'),
            'app_version': serializer.validated_data.get('app_version', ''),
        },
    )
    return Response({"detail": "Device registered."})


@api_view(["POST"])
@permission_classes([permissions.IsAuthenticated])
def unregister_device(request):
    token = request.data.get('token', '').strip()
    if not token:
        return Response({"detail": "token required."}, status=status.HTTP_400_BAD_REQUEST)
    DeviceToken.objects.filter(user=request.user, token=token).delete()
    return Response({"detail": "Device unregistered."})


# ── helpers ───────────────────────────────────────────────────────────────────

def _uid_from_user(user: User) -> str | None:
    """Extract firebase UID from the username format 'firebase_<uid>'.

    Returns None for WhatsApp-OTP users (username 'phone_<E164>') — those use
    the OneToOne `user=request.user` lookup directly.
    """
    if user.username.startswith("firebase_"):
        return user.username[len("firebase_"):]
    return None
