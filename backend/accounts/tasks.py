import logging

from medunity.celery_app import celery_app

logger = logging.getLogger(__name__)


@celery_app.task(bind=True, max_retries=3, default_retry_delay=60)
def notify_verification_decision(self, professional_id: int, decision: str):
    """
    Send FCM push to all devices of the professional when admin verifies/rejects.
    decision: 'verified' | 'rejected'
    """
    try:
        from .models import MedicalProfessional
        from medunity.fcm import send_push_to_many

        prof = MedicalProfessional.objects.select_related('user').get(pk=professional_id)
        tokens = list(prof.user.device_tokens.values_list('token', flat=True))
        if not tokens:
            logger.info(f"[accounts] No device tokens for professional {professional_id}")
            return

        if decision == 'verified':
            title = 'Welcome to MedUnity!'
            body = f'Hi Dr. {prof.full_name.split()[0]}, your profile has been verified. You now have full access.'
        else:
            title = 'Profile Review Update'
            body = 'Your profile needs attention. Please open MedUnity for details.'

        count = send_push_to_many(
            tokens, title, body,
            data={'type': 'verification_decision', 'decision': decision},
        )
        logger.info(f"[accounts] Verification push sent to {count}/{len(tokens)} devices")
    except Exception as exc:
        logger.exception(f"[accounts] notify_verification_decision failed: {exc}")
        raise self.retry(exc=exc)
