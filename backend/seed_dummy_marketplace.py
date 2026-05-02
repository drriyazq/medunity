"""Seed dummy data for: vendors, equipment co-purchase pools, marketplace
listings, practice-support (coverage) requests, and leaderboard points.

Run from backend/:
  DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell < seed_dummy_marketplace.py

Idempotent: matches by primary natural key per model and only inserts what is
missing. Uses existing dummy associate (+91906) and consultant (+91907) pools
plus Riya/Test Doctor as participants.
"""
import random
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone

from accounts.models import MedicalProfessional
from equipment.models import (
    EquipmentPool, MarketplaceListing, PoolMembership, ListingInquiry,
)
from support.models import BrowniePoint, CoverageRequest, award_points
from vendors.models import Vendor, VendorReview

random.seed(20260502)

RIYA = MedicalProfessional.objects.get(user__username='phone_+919867933139')
TEST = MedicalProfessional.objects.get(user__username='phone_+919967406651')

DUMMY_POOL = list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91906').order_by('id'))
DUMMY_POOL += list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91907').order_by('id'))
ALL = [RIYA, TEST] + DUMMY_POOL
print(f'Pool: {len(ALL)} doctors total ({len(DUMMY_POOL)} dummies + Riya + Test)\n')


# ── 1. VENDORS ────────────────────────────────────────────────────────────────

VENDORS = [
    ('Smile Solutions Lab', 'dental_lab',
     'Full-service dental lab specialising in zirconia and PFM crowns. 4-day standard turnaround.',
     '12 Hari Niwas, Andheri W', 'Mumbai', 'maharashtra', '400053', '+91 9820012345', 'smilesolutions.in'),
    ('Mehta Dental Depot', 'material_dealer',
     'Multi-brand consumables — composites, GIC, endo files, impression materials. Same-day delivery in Andheri.',
     'Shop 4, Lokhandwala Mkt', 'Mumbai', 'maharashtra', '400053', '+91 9819911223', 'mehtadepot.com'),
    ('CleanScan Imaging', 'imaging_centre',
     'CBCT, OPG, lateral cephs. NABL accredited. Reports in under 30 min.',
     '2nd Floor, Lokhandwala Plaza', 'Mumbai', 'maharashtra', '400053', '+91 9920018822', ''),
    ('Apex Equipment Service', 'equipment_technician',
     'On-site repair for chair units, autoclaves, compressors. ₹500 visit charge waived if repair undertaken.',
     '8 Veera Industrial Estate', 'Mumbai', 'maharashtra', '400053', '+91 9869912345', ''),
    ('PharmaXtra 24/7', 'pharmacy',
     'Compounding pharmacy with extensive stock of LA cartridges, post-op antibiotics, antifungals.',
     'Linking Rd, Bandra W', 'Mumbai', 'maharashtra', '400050', '+91 9930011456', 'pharmaxtra.in'),
    ('Aakash Dental Lab', 'dental_lab',
     'Specialises in implant prosthetics — TiBase, screw-retained, multi-unit bridges. Digital workflow.',
     'Khar Industrial Park', 'Mumbai', 'maharashtra', '400052', '+91 9870067788', ''),
    ('Crystal Imaging Hub', 'imaging_centre',
     'Affordable OPG and CBCT for paedo cases. Child-friendly setup.',
     'JP Road, Andheri W', 'Mumbai', 'maharashtra', '400058', '+91 9892211000', ''),
    ('GoldenStar Surgical', 'material_dealer',
     'Distributor for 3M, GC, Septodont, Dentsply. Bulk discounts on quarterly pre-orders.',
     'New Mahalaxmi Estate', 'Mumbai', 'maharashtra', '400063', '+91 9819988221', 'goldenstar.in'),
    ('Sanjivani Medi-Pharma', 'pharmacy',
     'Round-the-clock home delivery within 5km. Stocks rare medical compounds.',
     'SV Road, Santacruz W', 'Mumbai', 'maharashtra', '400054', '+91 9967700112', ''),
    ('Precision Lab Works', 'dental_lab',
     'Removable prosthodontics specialist — flexi dentures, attachments, complete dentures.',
     'Off SV Road, Andheri W', 'Mumbai', 'maharashtra', '400058', '+91 9820011009', ''),
    ('NeoTech Dental Service', 'equipment_technician',
     'Authorised service partner for Sirona, Planmeca, Acteon. AMC packages available.',
     'Marol MIDC', 'Mumbai', 'maharashtra', '400059', '+91 9869900221', 'neotech.in'),
    ('Kalyani Imaging Centre', 'imaging_centre',
     'Walking distance from Bandra station. Dental + ENT cone beam CT.',
     'SV Road, Bandra W', 'Mumbai', 'maharashtra', '400050', '+91 9930088771', ''),
    ('OrthoLab India', 'dental_lab',
     'Aligners, retainers, expansion appliances. In-house CBCT-driven workflow.',
     'Goregaon Industrial Area', 'Mumbai', 'maharashtra', '400063', '+91 9920033445', 'ortholab.in'),
    ('SwiftServe Dental Repair', 'equipment_technician',
     'Same-day chair-side repair for autoclaves, micromotors, ultrasonic scalers.',
     'Off Linking Rd, Khar W', 'Mumbai', 'maharashtra', '400052', '+91 9869977661', ''),
    ('Anjali Material Mart', 'material_dealer',
     'Small-clinic friendly minimum order quantities. Cash-on-delivery available.',
     'New Link Rd, Andheri W', 'Mumbai', 'maharashtra', '400053', '+91 9892020022', ''),
]

REVIEW_BODIES_GOOD = [
    'Excellent turnaround time. Have been using them for 2 years now.',
    'Quality is consistent — we use them as our primary lab.',
    'Reliable, fair pricing, good communication.',
    'Solid choice for routine cases.',
    'Highly recommended — staff is responsive on WhatsApp.',
    'Best in the area for the price point.',
]
REVIEW_BODIES_MIXED = [
    'Good for bread-and-butter cases, less reliable for complex ones.',
    'Quality has dropped slightly in the last 6 months.',
    'Decent — but you have to be specific about your prep design.',
    'Hit or miss. Some cases are great, others need redo.',
    'OK for routine — not my first choice for premium cases.',
]
REVIEW_BODIES_LOW = [
    'Had to redo a unit twice. Disappointing.',
    'Communication issues — multiple follow-ups needed.',
    'Quality inconsistent — switched after a year.',
]

print('--- Vendors ---')
new_vendors = 0
new_reviews = 0
for v in VENDORS:
    name, cat, desc, addr, city, state, pincode, phone, web = v
    vendor, created = Vendor.objects.get_or_create(
        name=name,
        defaults={
            'category': cat, 'description': desc, 'address': addr,
            'city': city, 'state': state, 'pincode': pincode,
            'phone': phone, 'website': web,
            'added_by': random.choice(ALL),
            'is_verified': True,
        },
    )
    if created:
        new_vendors += 1
    n_reviews = random.randint(3, 12)
    reviewers = random.sample(ALL, min(n_reviews, len(ALL)))
    for reviewer in reviewers:
        # Lean positive — most vendors are good. Occasional mixed/low.
        roll = random.random()
        if roll < 0.55:
            rating = random.randint(4, 5)
            comment = random.choice(REVIEW_BODIES_GOOD)
        elif roll < 0.85:
            rating = 3
            comment = random.choice(REVIEW_BODIES_MIXED)
        else:
            rating = random.randint(1, 2)
            comment = random.choice(REVIEW_BODIES_LOW)
        _, c = VendorReview.objects.get_or_create(
            vendor=vendor, reviewer=reviewer,
            defaults={
                'rating': rating,
                'quality_rating': max(1, rating + random.choice([-1, 0, 0])),
                'delivery_rating': max(1, rating + random.choice([-1, 0, 0, 1])),
                'comment': comment,
            },
        )
        if c:
            new_reviews += 1
    vendor.recalc_ratings()
print(f'  vendors: +{new_vendors} created, {Vendor.objects.count()} total')
print(f'  reviews: +{new_reviews} created\n')


# ── 2. EQUIPMENT POOLS (co-purchase) ──────────────────────────────────────────

POOLS = [
    # ── BULK-BUY pools — each member buys their own unit, group discount ──────
    # (name, category, description, target ₹, max_members, status, purpose)
    ('Andheri Composite Bulk Buy — 3M Filtek Z350',
     'consumables',
     '12 Andheri/Lokhandwala dentists pooling for 25% bulk discount on Filtek Z350 XT '
     'kits direct from 3M India distributor. Each clinic gets its own kit.',
     540000, 12, 'funded', 'bulk_buy'),
    ('Eighteeth E-Connect Pro — Mumbai endo group',
     'surgical_instruments',
     '8 endo-active practices across Andheri/Bandra buying their own unit at distributor '
     'pricing (₹32k → ₹26k each).',
     208000, 8, 'open', 'bulk_buy'),
    ('Class B Autoclave (24L) — bulk distributor deal',
     'sterilization',
     '6 clinics in Versova/Lokhandwala co-ordering Mocom B-Iclave units. Free installation '
     '+ 2-yr AMC included at this volume.',
     570000, 6, 'open', 'bulk_buy'),
    ('Woodpecker iLED Curing Light — bulk x15',
     'surgical_instruments',
     '15 Andheri/Bandra dentists. Distributor offered ₹8500 → ₹6800 per unit at this volume.',
     102000, 15, 'active', 'bulk_buy'),
    ('Septodont LA Cartridges — quarterly bulk',
     'consumables',
     '20-clinic quarterly pre-order from Septodont India. Lignospan price drops from '
     '₹40 → ₹28 per cartridge. Each clinic gets its own quota delivered.',
     240000, 20, 'open', 'bulk_buy'),
    ('GC Fuji IX GIC — Bandra cluster bulk',
     'consumables',
     '12 Bandra/Khar clinics ordering quarterly. Bulk rate from GC India authorised dealer.',
     108000, 12, 'open', 'bulk_buy'),

    # ── SHARED-USE pools — group buys ONE unit and shares it ─────────────────
    ('Implant Surgical Kit (BioHorizons) — Andheri share',
     'surgical_instruments',
     'ONE BioHorizons surgical kit hosted centrally in Lokhandwala. 6 implant-active '
     'dentists share it — most place 3-4 implants/month so a private kit sits idle. '
     'Members book usage days in the app.',
     85000, 6, 'active', 'shared_use'),
    ('PFM Repair Kit (Cojet + Opaque + Stains) — shared',
     'lab_equipment',
     'Bond-on PFM repair kit. 8 dentists in Andheri/Versova share. Used 2-4 times a month '
     'per member — not worth owning solo. Stored at host clinic, members pick up for the day.',
     45000, 8, 'active', 'shared_use'),
    ('Apex Locator Root ZX II — Lokhandwala cluster',
     'diagnostic',
     'Single Root ZX II shared between 5 GP dentists who do occasional emergency RCTs but '
     'mostly refer. Borrowable for 24h slots.',
     58000, 5, 'open', 'shared_use'),
    ('Electrosurgery Unit (Bonart ART-E1) — shared',
     'surgical_instruments',
     '6 Bandra-area dentists share one unit. Used ~6×/month per clinic for gingivectomy, '
     'frenectomy, troughing for crown impressions.',
     35000, 6, 'open', 'shared_use'),
    ('Diode Laser (Picasso 5W) — Bandra/Khar share',
     'surgical_instruments',
     '4-clinic share for soft-tissue procedures. Pickup/dropoff via local courier between '
     'clinics. Locked usage calendar prevents conflicts.',
     145000, 4, 'funded', 'shared_use'),
    ('Implant Torque Wrench + Multi-System Drivers — shared',
     'surgical_instruments',
     '8 implant-active dentists in Versova/Andheri share one set of drivers covering '
     'Nobel/Straumann/Adin/Osstem connections. Used at the second-stage / restorative visit.',
     22000, 8, 'active', 'shared_use'),
    ('Sandblaster (Renfert Vario Basic) — Lokhandwala share',
     'lab_equipment',
     '5 clinics share one sandblaster for alumina abrasion before re-cementation, repair '
     'cases, and surface conditioning. Stored at host clinic.',
     28000, 5, 'open', 'shared_use'),
]

OLD_POOL_NAMES_TO_REMOVE = [
    'Andheri CBCT Co-Op (i-CAT FLX V17)',
    'Sirona Cerec Primemill — group purchase',
    'Group Autoclave Service Contract (3 yr)',
    'Carestream 8200 OPG — Bandra cluster',
    'Bulk Endo File Order (Reciproc Blue)',
    'Premium Dental Chair Replacement Pool',
]

print('--- Equipment Pools ---')
removed_old = EquipmentPool.objects.filter(name__in=OLD_POOL_NAMES_TO_REMOVE).delete()[0]
if removed_old:
    print(f'  removed {removed_old} stale pool(s) from pre-purpose seeder')
new_pools = 0
new_memberships = 0
for p in POOLS:
    name, cat, desc, target, max_m, st, purpose = p
    pool, created = EquipmentPool.objects.get_or_create(
        name=name,
        defaults={
            'category': cat, 'description': desc,
            'purpose': purpose,
            'target_amount': Decimal(str(target)),
            'created_by': random.choice(ALL),
            'status': st, 'max_members': max_m,
        },
    )
    # Backfill purpose on pre-existing rows from old seeder runs
    if not created and pool.purpose != purpose:
        pool.purpose = purpose
        pool.save(update_fields=['purpose'])
    if created:
        new_pools += 1
    # Fill rate based on status
    if st == 'open':
        fill = random.uniform(0.4, 0.7)
    elif st == 'funded':
        fill = 1.0
    else:  # active
        fill = 1.0
    n_members = max(1, int(max_m * fill))
    members = random.sample(ALL, min(n_members, len(ALL)))
    contribution = Decimal(str(target)) / max_m
    for m in members:
        _, c = PoolMembership.objects.get_or_create(
            pool=pool, member=m,
            defaults={
                'contribution_amount': contribution.quantize(Decimal('0.01')),
                'is_active': True,
            },
        )
        if c:
            new_memberships += 1
    pool.recalc()
print(f'  pools: +{new_pools} created, {EquipmentPool.objects.count()} total')
print(f'  memberships: +{new_memberships} created\n')


# ── 3. MARKETPLACE LISTINGS ───────────────────────────────────────────────────

LISTINGS = [
    # (title, category, price, condition)
    ('Used Sirona C2+ Chair (2019)', 'dental_chairs', 285000, 'good',
     'Single owner. Light wear on upholstery. Service history available.'),
    ('Brand new Carestream 8200 OPG', 'imaging', 525000, 'new',
     'Sealed unit, factory warranty intact. Reluctant sale due to closure of branch.'),
    ('Acteon X-Mind Trium Sensor (size 1)', 'imaging', 95000, 'like_new',
     'Used <50 exposures. Replacement bought as size 2 was needed.'),
    ('Surgical Implant Kit - BioHorizons', 'surgical_instruments', 65000, 'good',
     'All drills + drivers included. Used for ~30 cases.'),
    ('NSK Surgic Pro Implant Motor', 'surgical_instruments', 78000, 'like_new',
     'Calibrated 6 months ago. Foot pedal + cord pristine.'),
    ('Endo Activator (Sybron)', 'surgical_instruments', 18000, 'good',
     'Working tips included.'),
    ('Bench-top Autoclave (Class B, 23L)', 'sterilization', 95000, 'fair',
     'Functional, gasket replaced last year. Outer panel scratched.'),
    ('Dental Composite Bulk Lot (assorted)', 'consumables', 28000, 'new',
     'Mixed shades — A1, A2, A3. Expiry 2027+.'),
    ('Eighteeth E-Connect Pro Endo Motor', 'surgical_instruments', 32000, 'like_new',
     'Wireless, latest model. Two cordless heads.'),
    ('Class A Dry Heat Sterilizer', 'sterilization', 22000, 'good',
     'Suitable for clinics with low load.'),
    ('Used Vatech Smart Plus CBCT', 'imaging', 1450000, 'good',
     'Selling due to upgrade. AMC valid till 2027.'),
    ('Mobile Suction Unit (Cattani)', 'surgical_instruments', 38000, 'fair',
     'Some hose wear, motor strong.'),
    ('LED Curing Light (Woodpecker iLed)', 'surgical_instruments', 8500, 'like_new',
     'Battery 90% capacity.'),
    ('Cavitron Touch Ultrasonic Scaler', 'surgical_instruments', 42000, 'good',
     'Three insert tips included.'),
    ('Bulk Impression Material (Aquasil)', 'consumables', 12000, 'new',
     '6 cartridges, sealed.'),
    ('Microscope (Zeiss OPMI Pico)', 'diagnostic', 285000, 'good',
     'Floor model, sturdy. Covers + dust cover included.'),
    ('Used Glide Path File Set', 'consumables', 4500, 'fair',
     'Assorted tapers, ~50% life remaining.'),
    ('Tribrace Articulator Set (Hanau Wide-Vue)', 'lab_equipment', 32000, 'like_new',
     'Used for one full mouth case.'),
    ('Pulp Tester (Parkell Digitest)', 'diagnostic', 9500, 'good',
     'Functional, batteries new.'),
    ('NSK Volvere i7 Lab Handpiece', 'lab_equipment', 42000, 'like_new',
     'Brushless motor, low hours.'),
    ('Air Compressor (Belmont 1HP)', 'sterilization', 38000, 'fair',
     'Works fine, bit noisy. Pressure gauge replaced.'),
    ('Set of 30 LA Cartridges (Lignospan)', 'consumables', 1200, 'new',
     'Sealed box, 2026 batch.'),
]

print('--- Marketplace Listings ---')
new_listings = 0
new_inquiries = 0
for L in LISTINGS:
    title, cat, price, cond, desc = L
    listing, created = MarketplaceListing.objects.get_or_create(
        title=title,
        defaults={
            'seller': random.choice(ALL),
            'description': desc,
            'category': cat,
            'price': Decimal(str(price)),
            'condition': cond,
            'status': 'active',
        },
    )
    if created:
        new_listings += 1
    # 0–3 inquiries per listing for the count badge to look real
    n_inquiries = random.choices([0, 1, 2, 3, 5], weights=[2, 3, 4, 3, 1])[0]
    inquirers = random.sample(
        [p for p in ALL if p.id != listing.seller_id],
        min(n_inquiries, len(ALL) - 1),
    )
    for q in inquirers:
        _, c = ListingInquiry.objects.get_or_create(
            listing=listing, inquirer=q,
            defaults={'message': random.choice([
                'Still available?',
                'Interested — can I see it in person?',
                'Best price?',
                'Service history available?',
                'Any issues with the unit?',
                'Negotiable on price?',
            ])},
        )
        if c:
            new_inquiries += 1
    listing.inquiry_count = listing.inquiries.count()
    listing.save(update_fields=['inquiry_count'])
print(f'  listings: +{new_listings} created, {MarketplaceListing.objects.count()} total')
print(f'  inquiries: +{new_inquiries} created\n')


# ── 4. COVERAGE / PRACTICE-SUPPORT REQUESTS ───────────────────────────────────

now = timezone.now()
COVERAGE = [
    ('coverage', 'Cover my Saturday clinic — going to hometown',
     'Need a dentist for full Saturday OPD. ~10-12 patients booked. Anaesthesia handled by chair-side assistant.',
     2, 9, 'open'),
    ('coverage', 'Friday evening urgent cover',
     'Family emergency, need someone for 4-7 PM Friday. Mostly review patients.',
     0, 4, 'open'),
    ('space_lending', 'Need operatory for 2 hours Sunday',
     'My clinic is 30 km away — looking for a chair near Andheri/Versova for one consult on Sunday.',
     5, 6, 'open'),
    ('coverage', 'Maternity leave coverage — 2 weeks',
     'Looking for an associate for 2 weeks starting next month. Pae rate negotiable.',
     14, 28, 'open'),
    ('space_lending', 'Need a chair for emergency RCT',
     'Patient en route, my unit out of service. Anyone with a free chair within 30 min of Andheri?',
     0, 1, 'open'),
    ('coverage', 'Holiday week locum',
     'Going to Goa Dec 22-29. Looking for someone to keep the clinic running.',
     30, 38, 'open'),
    ('coverage', 'Quick AM coverage tomorrow',
     'Doctor appointment 9-11 AM. Need someone to handle walk-ins. Should be light.',
     1, 1, 'accepted'),
    ('space_lending', 'Operatory needed for cosmetic case',
     'Patient prefers a private room for full mouth photographs. Borrowing a chair for 90 min.',
     3, 3, 'accepted'),
    ('coverage', 'CME on Sunday — clinic cover',
     'Attending IDA workshop. Need cover 10am-5pm.',
     7, 7, 'accepted'),
    ('coverage', 'Tomorrow afternoon — sick leave',
     'Caught a viral, calling in sick. Looking for someone 2-7 PM.',
     0, 0, 'closed'),
    ('coverage', 'Two-day cover next week',
     'Family wedding. Need full-day cover Tue + Wed.',
     5, 6, 'open'),
    ('space_lending', 'Looking for surgical OT for impaction',
     '4 mandibular thirds, sedation. Need a clinic with N₂O setup.',
     10, 10, 'open'),
]

print('--- Coverage Requests ---')
new_requests = 0
authors_pool = ALL
for c in COVERAGE:
    rtype, title, desc, days_from_now, days_end, st = c
    obj, created = CoverageRequest.objects.get_or_create(
        title=title,
        defaults={
            'requester': random.choice(authors_pool),
            'request_type': rtype,
            'description': desc,
            'city': 'Mumbai',
            'start_dt': now + timedelta(days=days_from_now),
            'end_dt': now + timedelta(days=days_end),
            'status': st,
        },
    )
    if created:
        new_requests += 1
        if st in ('accepted', 'closed'):
            # Assign acceptor + award points
            acceptor = random.choice([p for p in ALL if p.id != obj.requester_id])
            obj.accepted_by = acceptor
            obj.accepted_at = now - timedelta(hours=random.randint(1, 240))
            obj.save(update_fields=['accepted_by', 'accepted_at'])
            award_points(
                acceptor,
                'coverage' if rtype == 'coverage' else 'space_lending',
                source_id=obj.pk, reason=f'Accepted: {title}',
            )
print(f'  requests: +{new_requests} created, {CoverageRequest.objects.count()} total\n')


# ── 5. LEADERBOARD POINTS — varied tiers for clear ranking ────────────────────
# Award additional points so the leaderboard scrolls through clear leaders.

print('--- Leaderboard tiers ---')
# Distribute award counts so the top has 200+ pts, mid has ~80, bottom ~10.
# Reasons mix sos_response (10pt), coverage (15pt), space_lending (15pt).
TIER_TARGETS = [
    (250, 'top'), (220, 'top'), (185, 'top'),                     # 3 leaders
    (150, 'high'), (140, 'high'), (130, 'high'), (120, 'high'),   # 4 strong
    (95, 'mid'), (85, 'mid'), (75, 'mid'), (65, 'mid'),           # 4 mid
    (50, 'mid'), (45, 'mid'),                                      # 2 mid
    (30, 'low'), (25, 'low'), (20, 'low'),                         # 3 starter
]
# Pick recipients deterministically so re-runs are stable.
random.seed(202605020)
recipients = random.sample(ALL, min(len(TIER_TARGETS), len(ALL)))
new_points = 0
for prof, (target, _label) in zip(recipients, TIER_TARGETS):
    current = sum(p.points for p in prof.brownie_points.all())
    needed = target - current
    while needed > 0:
        # Pick a source whose default points fits or is just under needed
        source = random.choice(['sos_response', 'coverage', 'space_lending'])
        bp = award_points(prof, source, reason=random.choice([
            'Accepted SOS — emergency consult delivered',
            'Covered clinic for a CME absence',
            'Lent operatory for an emergency RCT',
            'Took an after-hours emergency for a colleague',
            'Provided sedation slot for a paediatric case',
        ]))
        new_points += 1
        needed -= bp.points
print(f'  awarded +{new_points} BrowniePoint rows\n')


# ── Final summary ─────────────────────────────────────────────────────────────

from django.db.models import Sum
print('Top 8 leaderboard preview:')
top = (
    BrowniePoint.objects.values('recipient')
    .annotate(total=Sum('points')).order_by('-total')[:8]
)
for i, row in enumerate(top, start=1):
    p = MedicalProfessional.objects.get(pk=row['recipient'])
    print(f'  #{i:>2} {p.full_name:<26} {p.get_specialization_display():<20} {row["total"]} pts')
