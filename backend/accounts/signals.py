from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import Clinic


@receiver(post_save, sender=Clinic)
def on_clinic_location_set(sender, instance, **kwargs):
    """Auto-join or create a local circle when a clinic's GPS location is first saved."""
    if instance.lat is None or instance.lng is None:
        return
    if not instance.owner.is_admin_verified:
        return
    from circles.models import auto_join_or_create_circle
    auto_join_or_create_circle(instance.owner)


def _award_sos_points(response_instance):
    """Award Brownie Points when a SOS response is accepted. Called from sos post_save."""
    if response_instance.status != 'accepted':
        return
    from support.models import award_points
    award_points(
        recipient=response_instance.responder,
        source_type='sos_response',
        source_id=response_instance.alert_id,
        reason=f'Responded to SOS #{response_instance.alert_id}',
    )


def connect_sos_points():
    """Connect SOS response signal. Called from support AppConfig.ready()."""
    from sos.models import SosResponse

    @receiver(post_save, sender=SosResponse, weak=False)
    def on_sos_response(sender, instance, created, **kwargs):
        if created and instance.status == 'accepted':
            _award_sos_points(instance)
        elif not created and instance.status == 'accepted':
            # status updated to accepted (not created already accepted)
            _award_sos_points(instance)
