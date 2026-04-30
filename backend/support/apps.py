from django.apps import AppConfig


class SupportConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'support'

    def ready(self):
        from accounts.signals import connect_sos_points
        connect_sos_points()
