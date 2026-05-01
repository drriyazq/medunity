"""WhatsApp Business Cloud API client (Meta direct).

Adapted from suredatapro-new/clinic/whatsapp.py — single-tenant variant. Reads
credentials from Django settings (env-driven) instead of a per-clinic row.

Used for OTP delivery to +91 phones because Firebase SMS is unreliable in India.

Template prerequisites (Meta Business Manager):
  - Template name: settings.WHATSAPP_OTP_TEMPLATE_NAME (default 'medunity_login_otp')
  - Category: AUTHENTICATION
  - Body: contains exactly one {{1}} placeholder for the 6-digit code
  - Language: settings.WHATSAPP_OTP_LANG (default 'en')

API reference:
  https://developers.facebook.com/docs/whatsapp/cloud-api/reference/messages
"""
import logging

import requests
from django.conf import settings

log = logging.getLogger(__name__)

GRAPH_API_VERSION = "v22.0"
GRAPH_API_BASE = f"https://graph.facebook.com/{GRAPH_API_VERSION}"


def normalize_phone(raw: str, default_country_code: str = "91") -> str:
    """Strip spaces/dashes/+ and prepend country code if it looks bare."""
    if not raw:
        return ""
    n = raw.strip().replace(" ", "").replace("-", "").replace("+", "").replace("(", "").replace(")", "")
    if n.startswith("00"):
        n = n[2:]
    if not n.startswith(default_country_code) and len(n) == 10 and n.isdigit():
        n = default_country_code + n
    return n


def send_otp_template(phone: str, code: str, *, timeout: int = 15) -> dict:
    """Send the OTP via the configured WhatsApp authentication template.

    Returns:
        {'ok': True,  'message_id': '...', 'response': {...}}
        {'ok': False, 'error': 'human-readable reason', 'response': {...}}
    """
    access_token = settings.WHATSAPP_ACCESS_TOKEN
    phone_number_id = settings.WHATSAPP_PHONE_NUMBER_ID
    template_name = settings.WHATSAPP_OTP_TEMPLATE_NAME
    lang = settings.WHATSAPP_OTP_LANG

    if not access_token or not phone_number_id:
        return {"ok": False, "error": "WhatsApp not configured (missing token or phone ID).", "response": {}}

    to = normalize_phone(phone)
    if not to:
        return {"ok": False, "error": "Empty/invalid recipient number.", "response": {}}

    url = f"{GRAPH_API_BASE}/{phone_number_id}/messages"
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }
    # Authentication templates require BOTH the body parameter (renders {{1}}) AND
    # a button URL parameter (sets what the Copy-code / one-tap button copies/sends).
    # Both must repeat the same OTP string. Without the button component, Meta returns
    # error 131008 ("Required parameter is missing"). See:
    # https://developers.facebook.com/docs/whatsapp/cloud-api/guides/authentication-templates
    body = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "template",
        "template": {
            "name": template_name,
            "language": {"code": lang},
            "components": [
                {
                    "type": "body",
                    "parameters": [{"type": "text", "text": str(code)}],
                },
                {
                    "type": "button",
                    "sub_type": "url",
                    "index": "0",
                    "parameters": [{"type": "text", "text": str(code)}],
                },
            ],
        },
    }

    try:
        r = requests.post(url, headers=headers, json=body, timeout=timeout)
        data = r.json() if r.content else {}
    except requests.RequestException as e:
        log.exception("WhatsApp API request failed")
        return {"ok": False, "error": f"Network error: {e}", "response": {}}

    if r.status_code == 200 and data.get("messages"):
        return {
            "ok": True,
            "message_id": data["messages"][0].get("id", ""),
            "response": data,
        }

    err = data.get("error", {})
    msg = err.get("message") or err.get("error_user_msg") or f"HTTP {r.status_code}"
    code_id = err.get("code", "")
    sub = err.get("error_subcode", "")
    full = msg + (f" (code {code_id}" + (f", subcode {sub}" if sub else "") + ")" if code_id else "")
    return {"ok": False, "error": full, "response": data}
