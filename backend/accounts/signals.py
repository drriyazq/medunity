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
    # Import here to avoid circular import at module load time
    from circles.models import auto_join_or_create_circle
    auto_join_or_create_circle(instance.owner)
