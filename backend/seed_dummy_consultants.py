"""One-shot seeder for 20 dummy verified consultants near Riya's clinic.

All seeded consultants are LIVE (`is_available=True`) and stay live regardless
of schedule. Specializations are picked from Riya's (dentist) consultant
search pool — DENTAL_CLUSTER + anaesthesiologist — so they show up in her
'find consultants' results.

Run with:
  cd /home/drriyazq/medunity/backend
  DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell < seed_dummy_consultants.py

Idempotent: matches by phone number, only inserts what's missing.
"""
import math
import random
from decimal import Decimal

from django.contrib.auth.models import User
from django.utils import timezone

from accounts.models import Clinic, MedicalProfessional
from consultants.models import ConsultantAvailability


# ── Riya's anchor (target test account: +919867933139) ───────────────────────
ANCHOR_LAT = 19.137800
ANCHOR_LNG = 72.838900

# 20 dummy consultants — distributed across the 8 specialties Riya (dentist)
# sees in the consultant-search filter (DENTAL_CLUSTER + anaesthesiologist).
DUMMY = [
    ('+919070000001', 'Dr Ananya Bose',       'dentist',          'Bose Family Dental',           'Andheri West'),
    ('+919070000002', 'Dr Rahul Pillai',      'oral_surgeon',     'Pillai Maxillofacial',         'Versova'),
    ('+919070000003', 'Dr Kavita Shah',       'endodontist',      'Shah Endo Specialists',        'Lokhandwala'),
    ('+919070000004', 'Dr Manish Verma',      'orthodontist',     'Verma Smile Orthodontics',     'Andheri West'),
    ('+919070000005', 'Dr Pooja Saxena',      'periodontist',     'Saxena Gum Care',              'Seven Bungalows'),
    ('+919070000006', 'Dr Vikrant Desai',     'prosthodontist',   'Desai Crown & Bridge',         'Lokhandwala'),
    ('+919070000007', 'Dr Sneha Patel',       'pedodontist',      'KidWise Paediatric Dental',    'Versova'),
    ('+919070000008', 'Dr Arjun Menon',       'anaesthesiologist','Menon Dental Anaesthesia',     'Andheri West'),
    ('+919070000009', 'Dr Ritika Sharma',     'dentist',          'Sharma Dental Studio',         'Lokhandwala'),
    ('+919070000010', 'Dr Devansh Khurana',   'oral_surgeon',     'Khurana OMFS',                 'Andheri East'),
    ('+919070000011', 'Dr Neha Bansal',       'endodontist',      'Bansal Root Canal Centre',     'Versova'),
    ('+919070000012', 'Dr Yash Goel',         'orthodontist',     'Goel Aligners & Braces',       'Lokhandwala'),
    ('+919070000013', 'Dr Aishwarya Iyer',    'periodontist',     'Iyer Perio Lab',               'Andheri East'),
    ('+919070000014', 'Dr Suresh Hegde',      'prosthodontist',   'Hegde Restorative Dental',     'Versova'),
    ('+919070000015', 'Dr Tanvi Rao',         'pedodontist',      'Little Smiles Paediatric',     'Andheri West'),
    ('+919070000016', 'Dr Karthik Venkatesh', 'anaesthesiologist','Venkatesh Dental Sedation',    'Bandra West'),
    ('+919070000017', 'Dr Maya Chaudhary',    'dentist',          'Chaudhary Modern Dental',      'Bandra West'),
    ('+919070000018', 'Dr Faisal Pasha',      'oral_surgeon',     'Pasha Cleft & Trauma',         'Khar West'),
    ('+919070000019', 'Dr Aditi Saxena',      'endodontist',      'Saxena Microendo',             'Khar West'),
    ('+919070000020', 'Dr Harshad Joshi',     'anaesthesiologist','Joshi Sedation Dental',        'Santa Cruz West'),
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


# Spread 20 consultants from 0.3 km to 10 km, evenly around the compass.
random.seed(2026)
created_profs = 0
created_clinics = 0
created_avail = 0
n = len(DUMMY)

for i, (phone, name, spec, clinic_name, locality) in enumerate(DUMMY):
    dist = 0.3 + (i / (n - 1)) * 9.7   # 0.3 → 10.0 km
    bearing = (i * (360.0 / n)) + random.uniform(-8, 8)
    lat, lng = offset(ANCHOR_LAT, ANCHOR_LNG, dist, bearing)

    username = f'phone_{phone}'
    user, _ = User.objects.get_or_create(
        username=username,
        defaults={'email': f'{phone.lstrip("+")}@medunity.phone'},
    )

    is_dental = spec in (
        'dentist', 'oral_surgeon', 'endodontist', 'orthodontist',
        'periodontist', 'prosthodontist', 'pedodontist',
    )
    prof, prof_created = MedicalProfessional.objects.get_or_create(
        user=user,
        defaults={
            'phone': phone,
            'phone_verified_at': timezone.now(),
            'full_name': name,
            'role': 'visiting_consultant',
            'roles': ['visiting_consultant'],
            'medical_council': 'maharashtra_mc',
            'license_number': f'DUMMYC-{phone[-6:]}',
            'specialization': spec,
            'years_experience': random.randint(4, 25),
            'qualification': 'BDS, MDS' if is_dental else 'MBBS, MD',
            'is_admin_verified': True,
            'verified_at': timezone.now(),
            'verification_submitted_at': timezone.now(),
            'is_active_listing': True,
        },
    )
    if prof_created:
        created_profs += 1
    else:
        # Idempotent: ensure flagged + role list contains visiting_consultant
        changed = []
        if not prof.is_admin_verified:
            prof.is_admin_verified = True
            prof.verified_at = prof.verified_at or timezone.now()
            changed.extend(['is_admin_verified', 'verified_at'])
        if not prof.is_active_listing:
            prof.is_active_listing = True
            changed.append('is_active_listing')
        roles = prof.roles or []
        if 'visiting_consultant' not in roles:
            roles.append('visiting_consultant')
            prof.roles = roles
            changed.append('roles')
        if changed:
            prof.save(update_fields=changed)

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
            'location_locked': True,
        },
    )
    if clinic_created:
        created_clinics += 1
    else:
        clinic.lat = Decimal(f'{lat:.6f}')
        clinic.lng = Decimal(f'{lng:.6f}')
        clinic.location_locked = True
        clinic.save(update_fields=['lat', 'lng', 'location_locked'])

    # Permanent Go Live for testing — schedule left empty so they stay live
    # without window logic interfering.
    avail, avail_created = ConsultantAvailability.objects.get_or_create(
        consultant=prof,
        defaults={
            'is_available': True,
            'available_since': timezone.now(),
            'lat': Decimal(f'{lat:.6f}'),
            'lng': Decimal(f'{lng:.6f}'),
            'last_ping_at': timezone.now(),
            'mobility_mode': 'stationary',
            'travel_radius_km': 15,
            'working_schedule': [],
            'visibility_mode': 'open',
        },
    )
    if avail_created:
        created_avail += 1
    else:
        # Idempotent: pin them live + at the right coords
        avail.is_available = True
        avail.available_since = avail.available_since or timezone.now()
        avail.lat = Decimal(f'{lat:.6f}')
        avail.lng = Decimal(f'{lng:.6f}')
        avail.last_ping_at = timezone.now()
        avail.mobility_mode = 'stationary'
        avail.travel_radius_km = 15
        avail.working_schedule = []
        avail.visibility_mode = 'open'
        avail.save(update_fields=[
            'is_available', 'available_since', 'lat', 'lng',
            'last_ping_at', 'mobility_mode', 'travel_radius_km',
            'working_schedule', 'visibility_mode', 'updated_at',
        ])

    print(f'  {phone} {name:<24s} {spec:<18s} {dist:5.2f} km @ ({lat:.5f}, {lng:.5f})')

print(
    f'\n{n} consultants seeded — '
    f'{created_profs} new professionals, '
    f'{created_clinics} new clinics, '
    f'{created_avail} new availability rows.'
)
print('All are LIVE (is_available=True), travel_radius_km=15, visibility=open.')
