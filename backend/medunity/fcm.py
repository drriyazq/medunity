import logging

logger = logging.getLogger(__name__)


def send_push_notification(
    fcm_token: str,
    title: str,
    body: str,
    data: dict | None = None,
    priority: str = "normal",
    channel_id: str | None = None,
    sound: str | None = None,
) -> bool:
    """
    Send a push notification to a single device.
    Non-blocking — never raises, always returns True/False.

    Firebase init is handled in Django app startup and Celery worker_process_init.
    """
    if not fcm_token:
        return False
    try:
        from firebase_admin import messaging

        payload = {}
        if data:
            payload.update({str(k): str(v) for k, v in data.items()})

        android_notification = None
        if channel_id or sound:
            android_notification = messaging.AndroidNotification(
                channel_id=channel_id or "default",
                sound=sound,
            )

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=payload,
            token=fcm_token,
            android=messaging.AndroidConfig(
                priority=priority,
                notification=android_notification,
            ),
            apns=messaging.APNSConfig(
                payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True))
            ),
        )
        response = messaging.send(message)
        logger.info(f"[FCM] Sent: {response}")
        return True
    except Exception:
        logger.exception(f"[FCM] Failed for token {fcm_token[:20]}...")
        return False


def send_push_to_many(tokens: list[str], title: str, body: str, data: dict | None = None, **kwargs) -> int:
    """Fan-out push to multiple device tokens. Returns success count."""
    return sum(send_push_notification(t, title, body, data, **kwargs) for t in tokens)
