"""Seed dummy reviews for the associate + consultant review modules.

Idempotent: matches on the natural unique-together keys per model and only
inserts what's missing. Re-runnable any number of times.

Run from backend/:
  DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py shell < seed_dummy_reviews.py

Populates:
  • ProfessionalReview (anyone-to-anyone, used everywhere a public profile or
    associate/consultant card shows a star rating) — for every dummy doctor
    seeds 3–8 reviews from a random subset of peers, in the right context.
  • ConsultantReview (booking-bound, drives the Find Consultants list's
    star rating) — fabricates 2–4 'connected' ConsultantBookings per dummy
    consultant and seeds a review on each so the cards show real averages.
"""
import random
from datetime import timedelta

from django.utils import timezone

from accounts.models import MedicalProfessional
from associates.models import ProfessionalReview
from consultants.models import ConsultantBooking, ConsultantReview

random.seed(20260503)

RIYA = MedicalProfessional.objects.get(user__username='phone_+919867933139')
TEST = MedicalProfessional.objects.get(user__username='phone_+919967406651')

DUMMY_ASSOCIATES = list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91906').order_by('id'))
DUMMY_CONSULTANTS = list(MedicalProfessional.objects.filter(
    user__username__startswith='phone_+91907').order_by('id'))

ALL = [RIYA, TEST] + DUMMY_ASSOCIATES + DUMMY_CONSULTANTS
print(f'Pool: {len(ALL)} profiles ({len(DUMMY_ASSOCIATES)} associates + '
      f'{len(DUMMY_CONSULTANTS)} consultants + Riya + Test)\n')


# ── Comment banks ──────────────────────────────────────────────────────────────

ASSOCIATE_COMMENTS_GOOD = [
    'Covered my Saturday clinic — patients were happy. Will hire again.',
    'Punctual, polite, treated my regulars like her own.',
    'Saved me during a CME week. Solid clinical hands.',
    'Filled in for two weekend shifts seamlessly.',
    'Great rapport with paedo cases. Highly recommended.',
    'Reliable. Showed up on time, finished on time.',
    'My team didn\'t miss a beat with him on the chair.',
    'Capable across routine + ortho consults. Easy to work with.',
]
ASSOCIATE_COMMENTS_OK = [
    'Decent. Took a bit of time to settle into our setup.',
    'Did the job. Communication on tricky cases could be better.',
    'OK for routine work — wouldn\'t use for complex prosthetic cases.',
]
ASSOCIATE_COMMENTS_LOW = [
    'Late on the day. Patients had to wait 40 min.',
    'Skipped a couple of records — had to redo charting after.',
]

CONSULTANT_COMMENTS_GOOD = [
    'Came in for an impacted-third case. Smooth surgery, patient stable.',
    'Excellent endo work — calcified canal, found it without perforation.',
    'Reliable for emergency RCT referrals. Always picks up calls.',
    'Quiet, methodical, knows when to refer back.',
    'Did a beautiful crown lengthening for my prosth case.',
    'Showed up within 90 min for an emergency. Patient saved.',
    'Cephalometric reading on my ortho case was spot on.',
    'Well prepared, checked imaging beforehand. Worth every rupee.',
]
CONSULTANT_COMMENTS_OK = [
    'Good clinical hands but charged a bit more than expected.',
    'Got the job done. Notes were sparse — had to ask for follow-up plan.',
    'Decent, but I wouldn\'t schedule them for a complex case.',
]
CONSULTANT_COMMENTS_LOW = [
    'Cancelled day-of. Scrambled to reschedule patient.',
    'Showed up but seemed rushed. Patient flagged it.',
]

GENERAL_COMMENTS = [
    'Attended the same study club for 2 years. Sharp clinician.',
    'Supportive colleague — always responds when I ask for advice.',
    'Met at IDA Mumbai. Good case discussions.',
    'Helped me with a tricky differential. Solid second opinion.',
]


def _pick_rating_and_comment(comments_good, comments_ok, comments_low):
    roll = random.random()
    if roll < 0.65:
        return random.randint(4, 5), random.choice(comments_good)
    if roll < 0.90:
        return 3, random.choice(comments_ok)
    return random.randint(1, 2), random.choice(comments_low)


# ── 1. ProfessionalReview seeding ──────────────────────────────────────────────

def _seed_prof_reviews_for(reviewee, primary_context, count_range, comments_bank):
    """Seed reviews about `reviewee` from a random subset of peers."""
    candidates = [p for p in ALL if p.id != reviewee.id]
    n = random.randint(*count_range)
    reviewers = random.sample(candidates, min(n, len(candidates)))
    new = 0
    for reviewer in reviewers:
        # 80% in the primary context (associate/consultant), 20% in 'general'
        ctx = primary_context if random.random() < 0.8 else 'general'
        bank = comments_bank if ctx == primary_context else (
            GENERAL_COMMENTS, GENERAL_COMMENTS, GENERAL_COMMENTS
        )
        rating, comment = _pick_rating_and_comment(*bank)
        _, created = ProfessionalReview.objects.get_or_create(
            reviewer=reviewer, reviewee=reviewee, context=ctx,
            defaults={'rating': rating, 'comment': comment},
        )
        if created:
            new += 1
    return new


print('--- ProfessionalReview ---')
total_new = 0

# Associates: 3–8 reviews each, mostly in 'associate' context
for assoc in DUMMY_ASSOCIATES:
    total_new += _seed_prof_reviews_for(
        assoc, 'associate', (3, 8),
        (ASSOCIATE_COMMENTS_GOOD, ASSOCIATE_COMMENTS_OK, ASSOCIATE_COMMENTS_LOW),
    )

# Consultants: 4–10 reviews each, mostly in 'consultant' context
for consult in DUMMY_CONSULTANTS:
    total_new += _seed_prof_reviews_for(
        consult, 'consultant', (4, 10),
        (CONSULTANT_COMMENTS_GOOD, CONSULTANT_COMMENTS_OK, CONSULTANT_COMMENTS_LOW),
    )

# Riya + Test get a couple too so their public profile isn't empty
for prof in (RIYA, TEST):
    total_new += _seed_prof_reviews_for(
        prof, 'general', (2, 5),
        (CONSULTANT_COMMENTS_GOOD, CONSULTANT_COMMENTS_OK, CONSULTANT_COMMENTS_LOW),
    )

print(f'  +{total_new} ProfessionalReview rows created '
      f'({ProfessionalReview.objects.count()} total)\n')


# ── 2. ConsultantReview seeding (needs parent ConsultantBooking) ───────────────

PROCEDURES = [
    'Surgical removal of impacted 38',
    'Re-RCT 26 (calcified MB canal)',
    'Implant placement #36 + immediate temporisation',
    'Apicoectomy #11',
    'Periodontal flap surgery, sextant 4',
    'Crown lengthening #16',
    'Sinus lift + grafting #26',
    'Ortho consultation — Class II div 1',
    'Cephalometric tracing review',
    'Frenectomy + soft-tissue grafting #41',
    'Pulpotomy #74 (paedo)',
    'Endodontic retreatment #46',
]

print('--- ConsultantBooking + ConsultantReview ---')
new_bookings = 0
new_reviews = 0
now = timezone.now()

for consult in DUMMY_CONSULTANTS:
    # 2–4 connected bookings per consultant, requesters from associates/Riya/Test
    candidate_requesters = [p for p in ALL if p.id != consult.id]
    n_bookings = random.randint(2, 4)
    requesters = random.sample(candidate_requesters, min(n_bookings, len(candidate_requesters)))

    for req in requesters:
        procedure = random.choice(PROCEDURES)
        booking, created = ConsultantBooking.objects.get_or_create(
            requester=req, consultant=consult, procedure=procedure,
            defaults={
                'status': 'connected',
                'notes': '',
                'responded_at': now - timedelta(days=random.randint(7, 60)),
                'completed_at': now - timedelta(days=random.randint(1, 6)),
            },
        )
        if created:
            new_bookings += 1

        # Requester reviews consultant
        rating, comment = _pick_rating_and_comment(
            CONSULTANT_COMMENTS_GOOD, CONSULTANT_COMMENTS_OK, CONSULTANT_COMMENTS_LOW)
        _, c1 = ConsultantReview.objects.get_or_create(
            booking=booking, reviewer=req,
            defaults={'reviewee': consult, 'rating': rating, 'comment': comment},
        )
        if c1:
            new_reviews += 1

        # Sometimes the consultant reviews the requester back (60% of bookings)
        if random.random() < 0.6:
            rating2, comment2 = _pick_rating_and_comment(
                CONSULTANT_COMMENTS_GOOD, CONSULTANT_COMMENTS_OK, CONSULTANT_COMMENTS_LOW)
            _, c2 = ConsultantReview.objects.get_or_create(
                booking=booking, reviewer=consult,
                defaults={'reviewee': req, 'rating': rating2, 'comment': comment2},
            )
            if c2:
                new_reviews += 1

print(f'  +{new_bookings} ConsultantBooking rows created '
      f'({ConsultantBooking.objects.count()} total)')
print(f'  +{new_reviews} ConsultantReview rows created '
      f'({ConsultantReview.objects.count()} total)\n')


# ── Summary ────────────────────────────────────────────────────────────────────

from django.db.models import Avg, Count
print('Top 10 ProfessionalReview leaderboard (by avg rating, min 3 reviews):')
top = (
    MedicalProfessional.objects
    .annotate(avg=Avg('reviews_about_me__rating'), n=Count('reviews_about_me'))
    .filter(n__gte=3)
    .order_by('-avg', '-n')[:10]
)
for i, p in enumerate(top, start=1):
    print(f'  #{i:>2} {p.full_name:<26} {p.get_specialization_display():<24} '
          f'{p.avg:.2f}★ ({p.n} reviews)')

print()
print('Top 10 ConsultantReview leaderboard (by avg rating):')
top_c = (
    MedicalProfessional.objects
    .annotate(avg=Avg('reviews_received__rating'), n=Count('reviews_received'))
    .filter(n__gte=2)
    .order_by('-avg', '-n')[:10]
)
for i, p in enumerate(top_c, start=1):
    print(f'  #{i:>2} {p.full_name:<26} {p.get_specialization_display():<24} '
          f'{p.avg:.2f}★ ({p.n} reviews)')
