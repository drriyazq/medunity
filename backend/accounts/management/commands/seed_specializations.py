"""
Idempotent command — prints the full specialization list for verification.
No DB writes needed: choices are baked into the model. Re-run safely at any time.
"""
from django.core.management.base import BaseCommand

from accounts.models import DOCTOR_SPECIALIZATIONS, MEDICAL_COUNCILS


class Command(BaseCommand):
    help = "Print the specialization and medical council choices (no DB writes — for verification)."

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS(f"\nSpecializations ({len(DOCTOR_SPECIALIZATIONS)}):"))
        for key, label in DOCTOR_SPECIALIZATIONS:
            self.stdout.write(f"  {key:35s} {label}")

        self.stdout.write(self.style.SUCCESS(f"\nMedical Councils ({len(MEDICAL_COUNCILS)}):"))
        for key, label in MEDICAL_COUNCILS:
            self.stdout.write(f"  {key:20s} {label}")

        self.stdout.write(self.style.SUCCESS("\n✓ Choices are embedded in model — no migration needed."))
