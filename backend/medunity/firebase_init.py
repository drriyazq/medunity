import logging
import os

import firebase_admin
from firebase_admin import credentials as fb_credentials

logger = logging.getLogger(__name__)

_initialised = False


def init_firebase() -> None:
    """Initialise Firebase Admin SDK exactly once per process."""
    global _initialised
    if _initialised:
        return
    cred_path = os.getenv(
        "FIREBASE_CREDENTIALS_PATH",
        os.path.join(os.path.dirname(os.path.dirname(__file__)), "firebase-credentials.json"),
    )
    if not os.path.exists(cred_path):
        logger.warning(f"[Firebase] credentials file not found at {cred_path} — push disabled")
        return
    cred = fb_credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)
    _initialised = True
    logger.info("[Firebase] Admin SDK initialised")
