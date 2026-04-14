import logging
import os
import re
from dataclasses import dataclass
from typing import Optional

import httpx
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

_FAST2SMS_URL = os.environ.get(
    "FAST2SMS_API_URL",
    "https://www.fast2sms.com/dev/bulkV2",
)
_FAST2SMS_ROUTE = os.environ.get("FAST2SMS_ROUTE", "q").strip() or "q"
_FAST2SMS_LANGUAGE = os.environ.get("FAST2SMS_LANGUAGE", "english").strip() or "english"
_FAST2SMS_TIMEOUT = httpx.Timeout(connect=5.0, read=20.0, write=5.0, pool=5.0)


@dataclass(frozen=True)
class TrustedContact:
    name: str
    phone: str
    email: Optional[str] = None


def _normalize_phone_number(phone: str) -> str:
    digits = re.sub(r"\D", "", phone or "")
    if digits.startswith("91") and len(digits) == 12:
        return digits[2:]
    return digits


def _last4(phone: str) -> str:
    return phone[-4:] if len(phone) >= 4 else phone


def _build_message(*, lat: float, lon: float, sender_name: str) -> str:
    safe_sender = sender_name.strip() or "WalkSafe"
    return (
        f"{safe_sender} SOS alert. I may be in danger and need help.\n"
        f"Location: https://www.google.com/maps?q={lat:.6f},{lon:.6f}\n"
        f"Coordinates: {lat:.6f}, {lon:.6f}"
    )


def _build_payload(*, phone: str, message: str) -> dict[str, str]:
    payload: dict[str, str] = {
        "route": _FAST2SMS_ROUTE,
        "numbers": phone,
        "message": message,
    }

    if _FAST2SMS_ROUTE == "q":
        payload["language"] = _FAST2SMS_LANGUAGE

    sender_id = os.environ.get("FAST2SMS_SENDER_ID")
    if sender_id:
        payload["sender_id"] = sender_id

    template_id = os.environ.get("FAST2SMS_TEMPLATE_ID")
    if template_id:
        payload["template_id"] = template_id

    entity_id = os.environ.get("FAST2SMS_ENTITY_ID")
    if entity_id:
        payload["entity_id"] = entity_id

    return payload


async def send_sms(
    *,
    contact: TrustedContact,
    lat: float,
    lon: float,
    sender_name: str,
) -> tuple[bool, Optional[str]]:
    api_key = os.environ.get("FAST2SMS_API_KEY", "").strip()
    if not api_key:
        logger.warning("Fast2SMS API key is not configured.")
        return False, "FAST2SMS_API_KEY is not configured"

    phone = _normalize_phone_number(contact.phone)
    if len(phone) != 10:
        logger.warning("Invalid trusted contact phone for %s: %r", contact.name, contact.phone)
        return False, f"Invalid phone number: {contact.phone}"

    message = _build_message(lat=lat, lon=lon, sender_name=sender_name)
    payload = _build_payload(phone=phone, message=message)

    try:
        async with httpx.AsyncClient(timeout=_FAST2SMS_TIMEOUT) as client:
            response = await client.post(
                _FAST2SMS_URL,
                headers={"authorization": api_key},
                data=payload,
            )
    except httpx.TimeoutException as exc:
        logger.warning("Fast2SMS timeout for %s (...%s): %s", contact.name, _last4(phone), exc)
        return False, "Fast2SMS request timed out"
    except httpx.HTTPError as exc:
        logger.warning("Fast2SMS request error for %s (...%s): %s", contact.name, _last4(phone), exc)
        return False, f"Fast2SMS request failed: {exc}"

    # Log the raw response for debugging - this makes future failures diagnosable
    logger.debug(
        "Fast2SMS raw response for %s: status=%d body=%s",
        contact.name,
        response.status_code,
        response.text[:500],
    )

    try:
        data = response.json()
    except Exception as parse_err:
        logger.warning(
            "Fast2SMS returned non-JSON for %s: %s | body: %s",
            contact.name,
            parse_err,
            response.text[:200],
        )
        # Treat as failure - cannot determine outcome
        return False, f"Fast2SMS returned unparseable response: {response.text[:100]}"

    # Fast2SMS success detection - handle both bool True and string "true"
    # The API documentation says {"return": true} but real responses vary.
    # We check: HTTP 200 AND ("return" is truthy OR "request_id" is present)
    # A request_id in the response confirms the message was accepted regardless
    # of the "return" field type.
    return_val = data.get("return")
    request_id = data.get("request_id")

    success = (
        response.status_code == 200
        and (
            return_val is True
            or return_val == "true"
            or str(return_val).lower() == "true"
            or request_id is not None
        )
    )

    if success:
        logger.info(
            "SMS sent to %s (...%s) | request_id=%s",
            contact.name,
            _last4(phone),
            request_id,
        )
        return True, None

    messages = data.get("message", [])
    if isinstance(messages, list):
        error_detail = ", ".join(str(message) for message in messages)
    else:
        error_detail = str(messages) if messages else str(data)

    logger.warning(
        "Fast2SMS rejected for %s (...%s): return=%r, message=%s",
        contact.name,
        _last4(phone),
        return_val,
        error_detail,
    )
    return False, f"Fast2SMS rejected: {error_detail}"
