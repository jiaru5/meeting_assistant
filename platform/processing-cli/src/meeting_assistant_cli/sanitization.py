from __future__ import annotations

import re
from collections.abc import Mapping, Sequence


_ABSOLUTE_PATH_RE = re.compile(r"(?<![\w.-])(?:~|/)[^\s'\"),;\]}]+")
_BEARER_VALUE_RE = re.compile(r"(?i)\b(bearer\s+)[A-Za-z0-9._~+/=-]{8,}")
_ASSIGNED_SENSITIVE_VALUE_RE = re.compile(
    r"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|token|secret|password|credential)\s*[:=]\s*['\"]?[^'\"\s,;}]+"
)
_OPENAI_STYLE_VALUE_RE = re.compile(r"\bsk-[A-Za-z0-9_-]{8,}")
_GITHUB_STYLE_VALUE_RE = re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{8,}")
_AWS_ACCESS_KEY_RE = re.compile(r"\bAKIA[0-9A-Z]{12,}\b")

def redact_sensitive_text(value: object, *, max_length: int = 240, redact_paths: bool = True) -> str:
    text = " ".join(str(value).replace("\x00", "").split())
    text = _BEARER_VALUE_RE.sub(r"\1<redacted>", text)
    text = _ASSIGNED_SENSITIVE_VALUE_RE.sub(lambda match: f"{match.group(1)}=<redacted>", text)
    text = _OPENAI_STYLE_VALUE_RE.sub("<redacted-secret>", text)
    text = _GITHUB_STYLE_VALUE_RE.sub("<redacted-secret>", text)
    text = _AWS_ACCESS_KEY_RE.sub("<redacted-secret>", text)
    if redact_paths:
        text = _ABSOLUTE_PATH_RE.sub("<path>", text)
    if len(text) > max_length:
        return text[: max_length - 14].rstrip() + " <truncated>"
    return text


def sanitize_failure_details(details: Mapping[str, object] | None) -> dict[str, object]:
    if not details:
        return {}
    return {str(key): _sanitize_detail_value(str(key), value) for key, value in details.items()}


def safe_exception_details(exc: BaseException) -> dict[str, object]:
    return {"error": exc.__class__.__name__}


def _sanitize_detail_value(key: str, value: object) -> object:
    if isinstance(value, Mapping):
        return {str(child_key): _sanitize_detail_value(str(child_key), child_value) for child_key, child_value in value.items()}
    if isinstance(value, str):
        return redact_sensitive_text(value, max_length=240, redact_paths=False)
    if isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray, str)):
        return [_sanitize_detail_value(key, item) for item in value]
    return value
