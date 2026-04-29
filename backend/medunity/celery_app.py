import os

from celery import Celery
from celery.signals import worker_process_init

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/2")

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "medunity.settings.dev")

celery_app = Celery(
    "medunity",
    broker=REDIS_URL,
    backend=REDIS_URL,
)

celery_app.config_from_object("django.conf:settings", namespace="CELERY")

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_acks_late=True,
    worker_prefetch_multiplier=1,
    broker_connection_retry_on_startup=True,
    beat_schedule={},
)

celery_app.autodiscover_tasks()


@worker_process_init.connect
def _init_firebase_in_worker(**_kwargs):
    """Each Celery worker process needs its own Firebase Admin SDK init."""
    from medunity.firebase_init import init_firebase
    init_firebase()
