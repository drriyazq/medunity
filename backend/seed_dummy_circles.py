"""Seed dummy Circles + memberships + posts + comments for testing.

Run with:
  cd /home/drriyazq/medunity/backend
  DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell < seed_dummy_circles.py

Idempotent: matched by Circle.name. Re-runs refresh content but don't duplicate.
Uses existing dummy associate (+91906000000X) and consultant (+91907000000Y)
pools as members + post authors + commenters.
"""
import random
from decimal import Decimal

from django.utils import timezone

from accounts.models import MedicalProfessional
from circles.models import Circle, CircleMembership, CirclePost, PostComment


random.seed(20260502)


# Setting clinic location on a fresh dummy doctor triggers
# auto_join_or_create_circle, which spams 'Mumbai Doctors Circle' clones with
# 1–2 members each. Sweep them up before seeding the curated list.
from circles.models import Circle as _Circle
_junk = _Circle.objects.filter(
    circle_type='auto', name='Mumbai Doctors Circle'
).filter(posts__isnull=True).distinct()
_n = _junk.count()
if _n:
    _junk.delete()
    print(f'Cleaned up {_n} stray auto-created Mumbai Doctors Circle rows.')


# ── Riya's anchor ─────────────────────────────────────────────────────────────
RIYA = MedicalProfessional.objects.get(user__username='phone_+919867933139')
TEST = MedicalProfessional.objects.get(user__username='phone_+919967406651')

# Pull dummy doctors created by the other seeders.
ASSOCIATES = list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91906').order_by('id'))
CONSULTANTS = list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91907').order_by('id'))
ALL_DUMMIES = ASSOCIATES + CONSULTANTS
print(f'Dummy pool: {len(ASSOCIATES)} associates + {len(CONSULTANTS)} consultants = {len(ALL_DUMMIES)} total')


# ── Circle definitions ────────────────────────────────────────────────────────
# (name, description, circle_type, lat, lng, radius_km, riya_joins_as,
#  test_doctor_joins, n_other_members, n_posts)
CIRCLES = [
    # Three circles where Riya is a member already (My Circles will have content)
    ('Andheri West Doctors', 'Local circle for clinics in Andheri West.',
     'manual', 19.1378, 72.8389, 2.5, 'admin', True, 12, 14),
    ('Lokhandwala Dental Network', 'Dental practitioners in Lokhandwala Complex.',
     'manual', 19.1402, 72.8339, 1.5, 'member', False, 8, 11),
    ('Versova Medical Forum', 'GPs and specialists from Versova area.',
     'manual', 19.1300, 72.8200, 2.0, 'member', True, 10, 9),

    # Circles Riya isn't in — Nearby tab will show Join buttons
    ('Bandra Health Hub', 'Cross-specialty group for Bandra clinics.',
     'manual', 19.0590, 72.8295, 3.0, None, False, 14, 16),
    ('Khar West Dentists', 'Dental community of Khar.',
     'manual', 19.0700, 72.8345, 1.5, None, False, 7, 6),
    ('Mumbai Endodontists Society', 'City-wide endo-only society.',
     'auto', 19.1000, 72.8500, 8.0, None, False, 9, 12),
    ('Mumbai Pediatric Dental Forum', 'Paedo-focused study circle.',
     'manual', 19.1500, 72.8300, 5.0, None, False, 6, 7),
    ('Andheri Surgeons Network', 'OMFS, plastic, general surgeons.',
     'manual', 19.1450, 72.8500, 3.5, None, True, 8, 10),
]


# ── Realistic post + comment templates ────────────────────────────────────────
POST_TEMPLATES = [
    ('discussion',
     'Anyone has experience with the new {brand} apex locator? Looking for honest feedback before I invest. Currently using a Propex Pixi for 4 years.'),
    ('discussion',
     'Saw an interesting periapical radiolucency on tooth 36 today — patient asymptomatic, vital. Would you do a CBCT first or just observe?'),
    ('event',
     'CME workshop on direct posterior composites this Saturday at Sun-N-Sand Juhu, 9 AM. Hands-on with {brand}. Limited to 30 dentists. ₹2500 reg fee.'),
    ('discussion',
     'Need a recommendation — patient needs full mouth rehabilitation, age 62, on warfarin. Looking for a prosthodontist who handles medically compromised cases well.'),
    ('announcement',
     'Reminder — IDA Mumbai branch dues are due by month end. The new digital portal makes payment quicker than the bank deposit slip route.'),
    ('discussion',
     'Question for the senior dentists — how do you handle a patient who refuses radiographs but needs RCT diagnosis? Documenting refusal in writing each time?'),
    ('discussion',
     'Sharing a case: 28F came in with chief complaint of throbbing pain RHS. Pulpitis on 47 confirmed. Did single-visit RCT under LA, patient sailed through. Any tips on managing flare-ups in single-visit cases?'),
    ('event',
     'Free dental camp this Sunday at Versova for slum-area children — looking for 5 more volunteers. Especially need a paedo specialist. DM me to sign up.'),
    ('discussion',
     'Anyone using {brand} CBCT machine? Considering between that and Carestream 9300. Image quality vs running cost — what tipped your decision?'),
    ('announcement',
     'New IDA Mumbai branch Whatsapp group rules — please limit non-clinical content. The clinical referral channel is much more useful when not flooded.'),
    ('discussion',
     'Patient walked in with severe trismus post-extraction done elsewhere. Can\'t open >15mm. What is your protocol — diazepam + warm compresses + soft diet, or jump to imaging?'),
    ('discussion',
     'Looking for a GP comfortable with diabetic patients on insulin who needs surgical extractions. PG hospital is too far for my elderly patient.'),
    ('discussion',
     'Just received my new {brand} curing light — seems to work, but cure depth on bulk-fill resin disappointing. What output (mW/cm²) are you all running for posterior bulk-fill?'),
    ('event',
     'IAOMP study group meeting this Friday 7pm — case discussions on oral cancer screening. Open to all members. RSVP for dinner.'),
    ('discussion',
     'Needles question — anyone shifted from 27G to 30G long for IANB? Curious about your success rate change.'),
    ('discussion',
     'Patient adamantly wants veneers despite caries on 11 and 21 (cervical). I keep declining and recommending RCT first. Is anyone else seeing more such patients post Instagram trends?'),
    ('announcement',
     'Local lab Smile Solutions has reduced zirconia turn-around to 4 days from 7. Quality has been consistent for me over the last 2 months — good option for impatient patients.'),
    ('discussion',
     'How are you all handling no-show patients? I\'ve started taking 50% advance for full mouth treatment plans — works but feels transactional. Better strategies?'),
    ('discussion',
     'Anyone interested in a joint purchase of an i-CAT FLX V17 to share between 3-4 clinics? Costs distribute and we all get advanced imaging without each owning one.'),
    ('discussion',
     'Sealants on permanent first molars — at what age do you stop offering them? I\'ve had a 14-year-old whose mother insisted today and I felt the molars had already accumulated stain.'),
]

COMMENT_TEMPLATES = [
    'Great question — I had a similar case last month.',
    'Following for the answers, very relevant for my practice.',
    'Tried this with two patients, worked well in both.',
    'Disagree slightly — in my experience CBCT is overused for this.',
    'Thanks for sharing — saving for reference.',
    'Yes I had the exact issue. Switched brands and it resolved.',
    'Tagging Dr Kapoor, he handles these cases regularly.',
    'My approach: imaging first, intervention only if symptomatic.',
    'I went through this exercise last year, happy to share my notes offline.',
    'Honestly — I would refer out. Not worth the medico-legal exposure.',
    'Available Saturday — count me in.',
    'Sounds like a great workshop, register link please?',
    '+1, can confirm from personal experience.',
    'See you there!',
    'Have you considered a third option?',
    'Interesting — what was the patient demographic?',
    'I asked my prof about this in PG, can share his thoughts.',
    'Great share, thanks for documenting it.',
    'In my opinion, more research needed before generalising.',
    'Let me know what you decide — keen to follow.',
]

BRANDS = ['Eighteeth', 'Acteon', 'Sirona', 'Carestream', 'Planmeca',
          'Vatech', 'Septodont', 'Dentsply', 'Voco', '3M ESPE', 'GC Asia']


def fill_template(template: str) -> str:
    return template.replace('{brand}', random.choice(BRANDS))


# ── Build / refresh ───────────────────────────────────────────────────────────
created_circles = 0
refreshed_circles = 0
total_members = 0
total_posts = 0
total_comments = 0

for spec in CIRCLES:
    (name, desc, ctype, lat, lng, radius, riya_role,
     test_joins, n_other_members, n_posts) = spec

    circle, was_created = Circle.objects.get_or_create(
        name=name,
        defaults={
            'description': desc,
            'circle_type': ctype,
            'created_by': RIYA if riya_role == 'admin' else random.choice(ALL_DUMMIES),
            'radius_km': radius,
            'center_lat': Decimal(f'{lat:.6f}'),
            'center_lng': Decimal(f'{lng:.6f}'),
            'is_active': True,
        },
    )
    if was_created:
        created_circles += 1
    else:
        # Refresh basic metadata in case we re-tuned the seed
        circle.description = desc
        circle.circle_type = ctype
        circle.radius_km = radius
        circle.center_lat = Decimal(f'{lat:.6f}')
        circle.center_lng = Decimal(f'{lng:.6f}')
        circle.is_active = True
        circle.save(update_fields=[
            'description', 'circle_type', 'radius_km',
            'center_lat', 'center_lng', 'is_active',
        ])
        refreshed_circles += 1

    # ── Memberships ──────────────────────────────────────────────────────────
    if riya_role:
        m, _ = CircleMembership.objects.get_or_create(
            circle=circle, member=RIYA, defaults={'role': riya_role, 'is_active': True})
        if not m.is_active or m.role != riya_role:
            m.is_active = True
            m.role = riya_role
            m.save(update_fields=['is_active', 'role'])

    if test_joins:
        m, _ = CircleMembership.objects.get_or_create(
            circle=circle, member=TEST, defaults={'role': 'member', 'is_active': True})
        if not m.is_active:
            m.is_active = True
            m.save(update_fields=['is_active'])

    # Pick deterministic dummy members for this circle
    others = random.sample(ALL_DUMMIES, min(n_other_members, len(ALL_DUMMIES)))
    for prof in others:
        m, created = CircleMembership.objects.get_or_create(
            circle=circle, member=prof,
            defaults={'role': 'member', 'is_active': True})
        if not m.is_active:
            m.is_active = True
            m.save(update_fields=['is_active'])
        if created:
            total_members += 1

    circle.recalc_member_count()

    # ── Posts ────────────────────────────────────────────────────────────────
    existing_posts = circle.posts.count()
    needed = max(0, n_posts - existing_posts)
    member_pool = list(circle.memberships.filter(is_active=True).values_list('member_id', flat=True))
    member_pool_objs = list(MedicalProfessional.objects.filter(pk__in=member_pool))
    if needed > 0 and member_pool_objs:
        for i in range(needed):
            ptype, ptemplate = random.choice(POST_TEMPLATES)
            content = fill_template(ptemplate)
            author = random.choice(member_pool_objs)
            post = CirclePost.objects.create(
                circle=circle,
                author=author,
                post_type=ptype,
                content=content,
            )
            total_posts += 1

            # 0–7 comments per post
            n_comments = random.choices(
                [0, 1, 2, 3, 4, 5, 7], weights=[2, 3, 5, 5, 4, 3, 2])[0]
            for _ in range(n_comments):
                commenter = random.choice(member_pool_objs)
                PostComment.objects.create(
                    post=post,
                    author=commenter,
                    content=random.choice(COMMENT_TEMPLATES),
                )
                total_comments += 1
            post.recalc_comment_count()

    # Backfill comments on existing posts that have zero (so detail page is meaty)
    for post in circle.posts.filter(comments__isnull=True).distinct():
        n_comments = random.randint(2, 5)
        for _ in range(n_comments):
            commenter = random.choice(member_pool_objs or [RIYA])
            PostComment.objects.create(
                post=post, author=commenter,
                content=random.choice(COMMENT_TEMPLATES),
            )
            total_comments += 1
        post.recalc_comment_count()


print(f'\nCircles: {created_circles} created, {refreshed_circles} refreshed.')
print(f'Memberships added: {total_members}')
print(f'Posts created: {total_posts}')
print(f'Comments created: {total_comments}')
print()
print('Riya membership summary:')
for m in CircleMembership.objects.filter(member=RIYA, is_active=True).select_related('circle'):
    print(f'  - {m.circle.name} ({m.role})')
print()
print('Nearby (circles within 10 km of Riya she is NOT in):')
from sos.models import haversine_km
ria_lat, ria_lng = float(RIYA.clinic.lat), float(RIYA.clinic.lng)
for c in Circle.objects.filter(is_active=True):
    if c.center_lat is None: continue
    if c.memberships.filter(member=RIYA, is_active=True).exists(): continue
    d = haversine_km(ria_lat, ria_lng, float(c.center_lat), float(c.center_lng))
    if d <= 10:
        print(f'  - {c.name:<40s} {d:5.2f} km away  members={c.member_count}  posts={c.posts.count()}')
