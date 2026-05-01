"""One-shot seeder for 10 dummy verified doctors near Riya's clinic.

Run with:
  DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell < seed_dummy_doctors.py

Idempotent: matches by phone number and only inserts what's missing.
Also locks Test Doctor's clinic location so the GPS-update endpoint
refuses overwrites (both test phones are physically together).
"""
import math
import random
from decimal import Decimal

from django.contrib.auth.models import User
from django.utils import timezone

from accounts.models import Clinic, MedicalProfessional


# ── Riya's anchor (target test account: +919867933139) ───────────────────────
ANCHOR_LAT = 19.137086
ANCHOR_LNG = 72.844311

# 10 dummy doctors — variety of specializations + scattered within ~2km
DUMMY = [
    ('+919060000001', 'Dr Aanya Mehta',     'dentist',         'Aanya Dental & Smiles',      'Andheri West'),
    ('+919060000002', 'Dr Vikram Iyer',     'oral_surgeon',    'Iyer Oral & Maxillofacial', 'Versova'),
    ('+919060000003', 'Dr Nisha Joshi',     'orthodontist',    'Joshi Orthodontics',         'Lokhandwala'),
    ('+919060000004', 'Dr Rohit Kapoor',    'endodontist',     'Kapoor Root Canal Centre',   'Andheri West'),
    ('+919060000005', 'Dr Priya Nair',      'pedodontist',     'KidCare Dental Clinic',      'Seven Bungalows'),
    ('+919060000006', 'Dr Sameer Kulkarni', 'periodontist',    'GumGuard Periodontics',      'Lokhandwala'),
    ('+919060000007', 'Dr Anjali Rao',      'general_physician','Rao Family Clinic',         'Versova'),
    ('+919060000008', 'Dr Karan Bhatia',    'paediatrician',   'Tiny Steps Paediatrics',     'Andheri West'),
    ('+919060000009', 'Dr Meera Sundaram',  'gynaecologist',   'Sundaram Womens Health',     'Lokhandwala'),
    ('+919060000010', 'Dr Tarun Khanna',    'orthopaedic',     'Khanna Bone & Joint',        'Andheri West'),
]


def offset(lat0, lng0, dist_km, bearing_deg):
    """Return (lat, lng) offset by dist_km along bearing_deg from anchor."""
    R = 6371.0
    bearing = math.radians(bearing_deg)
    lat1 = math.radians(lat0)
    lng1 = math.radians(lng0)
    lat2 = math.asin(
        math.sin(lat1) * math.cos(dist_km / R)
        + math.cos(lat1) * math.sin(dist_km / R) * math.cos(bearing)
    )
    lng2 = lng1 + math.atan2(
        math.sin(bearing) * math.sin(dist_km / R) * math.cos(lat1),
        math.cos(dist_km / R) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lng2)


# Deterministic spread: ring of 10 points 0.4–1.8 km from anchor
random.seed(42)
created_profs = 0
created_clinics = 0
for i, (phone, name, spec, clinic_name, locality) in enumerate(DUMMY):
    dist = 0.4 + (i / 9.0) * 1.4   # 0.4 → 1.8 km
    bearing = i * 36 + random.uniform(-10, 10)  # full 360° spread
    lat, lng = offset(ANCHOR_LAT, ANCHOR_LNG, dist, bearing)

    username = f'phone_{phone}'
    user, _ = User.objects.get_or_create(
        username=username,
        defaults={'email': f'{phone.lstrip("+")}@medunity.phone'},
    )

    prof, prof_created = MedicalProfessional.objects.get_or_create(
        user=user,
        defaults={
            'phone': phone,
            'phone_verified_at': timezone.now(),
            'full_name': name,
            'role': 'clinic_owner',
            'medical_council': 'maharashtra_mc',
            'license_number': f'DUMMY-{phone[-6:]}',
            'specialization': spec,
            'years_experience': random.randint(3, 22),
            'qualification': 'BDS, MDS' if 'dent' in spec or spec in (
                'oral_surgeon', 'orthodontist', 'endodontist',
                'periodontist', 'pedodontist', 'prosthodontist',
            ) else 'MBBS',
            'is_admin_verified': True,
            'verified_at': timezone.now(),
            'verification_submitted_at': timezone.now(),
            'is_active_listing': True,
        },
    )
    if prof_created:
        created_profs += 1
    else:
        # idempotent backfill — make sure they are verified + active
        if not prof.is_admin_verified or not prof.is_active_listing:
            prof.is_admin_verified = True
            prof.is_active_listing = True
            prof.verified_at = prof.verified_at or timezone.now()
            prof.save(update_fields=['is_admin_verified', 'is_active_listing', 'verified_at'])

    clinic, clinic_created = Clinic.objects.get_or_create(
        owner=prof,
        defaults={
            'name': clinic_name,
            'address': f'Plot {random.randint(10, 199)}, {locality}',
            'city': 'Mumbai',
            'state': 'maharashtra',
            'pincode': '400053',
            'phone': phone,
            'lat': Decimal(f'{lat:.6f}'),
            'lng': Decimal(f'{lng:.6f}'),
            'location_set_at': timezone.now(),
            'location_locked': True,    # dummy clinics are pinned
        },
    )
    if clinic_created:
        created_clinics += 1
    else:
        # idempotent: ensure coords + lock are correct on re-run
        clinic.lat = Decimal(f'{lat:.6f}')
        clinic.lng = Decimal(f'{lng:.6f}')
        clinic.location_set_at = clinic.location_set_at or timezone.now()
        clinic.location_locked = True
        clinic.save(update_fields=['lat', 'lng', 'location_set_at', 'location_locked'])

    print(f'  {phone} {name:<22s} {spec:<18s} {dist:.2f} km @ ({lat:.5f}, {lng:.5f})')

print(f'\nCreated {created_profs} new professionals, {created_clinics} new clinics')

# ── Lock Test Doctor (+919967406651) at their existing distinct location ─────
try:
    test_prof = MedicalProfessional.objects.get(phone='+919967406651')
    test_clinic = test_prof.clinic
    test_clinic.location_locked = True
    test_clinic.save(update_fields=['location_locked'])
    print(f'\nLocked +919967406651 ({test_prof.full_name}) at '
          f'({test_clinic.lat}, {test_clinic.lng}) — distinct from anchor.')
except MedicalProfessional.DoesNotExist:
    print('Test Doctor +919967406651 not found.')
