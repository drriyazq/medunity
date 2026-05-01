"""OTP store backed by Redis.

Key shape:
    medunity:otp:<E164>          → 6-digit code (TTL = settings.OTP_TTL_SECONDS)
    medunity:otp:<E164>:attempts → wrong-attempt counter (parallel TTL)

After OTP_MAX_ATTEMPTS wrong codes the entry is deleted and the user must
request a new OTP. Verifying the correct code also deletes the entry (single-use).
"""
import logging
import secrets

import redis
from django.conf import settings

log = logging.getLogger(__name__)

_KEY_PREFIX = "medunity:otp:"


def _client() -> redis.Redis:
    # decode_responses=True so we get str back, not bytes
    return redis.Redis.from_url(settings.REDIS_URL, decode_responses=True)


def _key(phone: str) -> str:
    return f"{_KEY_PREFIX}{phone}"


def _attempts_key(phone: str) -> str:
    return f"{_KEY_PREFIX}{phone}:attempts"


def generate_code() -> str:
    """Cryptographically random 6-digit code, zero-padded."""
    return f"{secrets.randbelow(1_000_000):06d}"


def store(phone: str, code: str) -> None:
    """Persist a fresh code for `phone` with TTL. Resets the attempt counter."""
    r = _client()
    ttl = settings.OTP_TTL_SECONDS
    pipe = r.pipeline()
    pipe.setex(_key(phone), ttl, code)
    pipe.delete(_attempts_key(phone))
    pipe.execute()


class VerifyResult:
    OK = "ok"
    WRONG_CODE = "wrong_code"
    EXPIRED = "expired"
    TOO_MANY_ATTEMPTS = "too_many_attempts"


def verify(phone: str, code: str) -> str:
    """Atomically check `code` against the stored OTP for `phone`.

    Returns one of the VerifyResult.* constants. On OK the entry is deleted
    (single-use). On wrong_code the attempt counter is incremented; once it
    reaches settings.OTP_MAX_ATTEMPTS the entry is purged and TOO_MANY_ATTEMPTS
    is returned on subsequent tries.
    """
    r = _client()
    stored = r.get(_key(phone))
    if stored is None:
        return VerifyResult.EXPIRED

    if stored == code:
        pipe = r.pipeline()
        pipe.delete(_key(phone))
        pipe.delete(_attempts_key(phone))
        pipe.execute()
        return VerifyResult.OK

    # wrong code → bump attempts, mirror TTL of the OTP key on first miss
    attempts = r.incr(_attempts_key(phone))
    if attempts == 1:
        ttl = r.ttl(_key(phone))
        if ttl and ttl > 0:
            r.expire(_attempts_key(phone), ttl)

    if attempts >= settings.OTP_MAX_ATTEMPTS:
        pipe = r.pipeline()
        pipe.delete(_key(phone))
        pipe.delete(_attempts_key(phone))
        pipe.execute()
        return VerifyResult.TOO_MANY_ATTEMPTS

    return VerifyResult.WRONG_CODE
