"""Server-only GCP adapters. No server, wallet or production switch is implied.

The composition root must inject authenticated reservation authorization and ADC
token acquisition. Tests inject fixtures; this module never reads an API key.
"""
from __future__ import annotations

import base64
from dataclasses import dataclass
import io
import json
import re
from typing import Callable, Protocol
import urllib.error
import urllib.request
import uuid
import wave


class ProviderError(Exception):
    """Safe code only: never include credentials, prompts or provider bodies."""


def _utf8_size(value: str) -> int:
    try:
        return len(value.encode("utf-8"))
    except UnicodeError:
        raise ProviderError("invalid-unicode") from None


@dataclass(frozen=True)
class Configuration:
    project: str
    speech_location: str
    vertex_location: str
    vertex_models: tuple[str, ...]
    languages: tuple[str, ...] = ("en-AU", "en-US", "en-GB")
    sandbox_enabled: bool = False
    environment: str = "sandbox"

    def validate(self) -> None:
        if any(not isinstance(value, str) for value in (self.project, self.speech_location, self.vertex_location, self.environment)) or type(self.sandbox_enabled) is not bool:
            raise ProviderError("invalid-configuration-types")
        if not re.fullmatch(r"[a-z][a-z0-9-]{4,28}[a-z0-9]", self.project):
            raise ProviderError("invalid-project")
        if self.speech_location not in ("us", "eu"):
            raise ProviderError("unsupported-speech-location")
        if self.vertex_location != "global" and not re.fullmatch(r"[a-z]+-[a-z]+[1-9][0-9]*", self.vertex_location):
            raise ProviderError("invalid-vertex-location")
        if not isinstance(self.vertex_models, tuple) or not self.vertex_models or len(self.vertex_models) > 20 or any(not isinstance(model, str) or not re.fullmatch(r"[a-zA-Z0-9._-]{1,100}", model) for model in self.vertex_models):
            raise ProviderError("invalid-model-allowlist")
        if not isinstance(self.languages, tuple) or not self.languages or len(self.languages) > 30 or any(not isinstance(language, str) or not re.fullmatch(r"[a-z]{2,3}-[A-Za-z]{2,8}(?:-[A-Za-z]{2,8})?", language) for language in self.languages):
            raise ProviderError("invalid-language-allowlist")
        if self.environment not in ("sandbox", "production"):
            raise ProviderError("invalid-environment")

    @classmethod
    def from_mapping(cls, values: dict) -> Configuration:
        required = {"project", "speech_location", "vertex_location", "vertex_models"}
        allowed = required | {"languages", "sandbox_enabled", "environment"}
        if not isinstance(values, dict) or not required.issubset(values) or set(values) - allowed:
            raise ProviderError("invalid-configuration")
        data = dict(values)
        for key in ("vertex_models", "languages"):
            if key in data:
                if not isinstance(data[key], list):
                    raise ProviderError("invalid-configuration")
                data[key] = tuple(data[key])
        result = cls(**data); result.validate(); return result


@dataclass(frozen=True)
class HTTPResponse:
    status: int
    data: bytes
    content_type: str = "application/json"


class Transport(Protocol):
    def post(self, url: str, headers: dict[str, str], body: bytes, *, response_limit: int, timeout: int) -> HTTPResponse: ...


class _NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class BoundedHTTPTransport:
    """One request, no retries, redirects, cookie jar or environment proxies."""
    def post(self, url: str, headers: dict[str, str], body: bytes, *, response_limit: int, timeout: int) -> HTTPResponse:
        request = urllib.request.Request(url, data=body, headers=headers, method="POST")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirects())
        try:
            with opener.open(request, timeout=timeout) as response:
                length = response.headers.get("Content-Length")
                if length is not None and int(length) > response_limit:
                    raise ProviderError("response-too-large")
                data = response.read(response_limit + 1)
                if len(data) > response_limit:
                    raise ProviderError("response-too-large")
                return HTTPResponse(response.status, data, response.headers.get("Content-Type", ""))
        except urllib.error.HTTPError as error:
            # Do not consume/log error bodies or follow their suggested URLs.
            return HTTPResponse(error.code, b"")
        except ProviderError:
            raise
        except Exception:
            raise ProviderError("uncertain-delivery") from None


class GoogleCloudAdapters:
    def __init__(self, configuration: Configuration, *, authorize: Callable[[str, str, str], None],
                 access_token: Callable[[], str], transport: Transport | None = None):
        configuration.validate()
        self.configuration = configuration
        self._authorize = authorize
        self._access_token = access_token
        self._transport = transport or BoundedHTTPTransport()

    def _send(self, operation_id: str, purpose: str, model: str, url: str, payload: dict, *, limit: int = 250_000) -> dict:
        config = self.configuration
        # Production remains unavailable until the hosted accounting/auth path is implemented.
        if not config.sandbox_enabled or config.environment != "sandbox":
            raise ProviderError("not-configured")
        try:
            if str(uuid.UUID(operation_id)) != operation_id:
                raise ValueError()
            body = json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()
        except Exception:
            raise ProviderError("invalid-request") from None
        if len(body) > 8_100_000:
            raise ProviderError("request-too-large")
        try:
            # Authorization must bind the verified learner, environment, operation,
            # model, disclosure and usage reservation before any billed dispatch.
            self._authorize(operation_id, purpose, model)
        except Exception:
            raise ProviderError("access-denied") from None
        try:
            token = self._access_token()
            if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9._~+/=-]{1,4096}", token):
                raise ValueError()
        except Exception:
            raise ProviderError("credentials-unavailable") from None
        try:
            response = self._transport.post(url, {"Authorization": "Bearer " + token, "Content-Type": "application/json",
                "X-Goog-User-Project": config.project}, body, response_limit=limit, timeout=120)
        except ProviderError:
            raise
        except Exception:
            raise ProviderError("uncertain-delivery") from None
        if not 200 <= response.status < 300:
            raise ProviderError("provider-http-" + str(response.status))
        if len(response.data) > limit:
            raise ProviderError("response-too-large")
        if response.content_type.split(";", 1)[0].strip().lower() != "application/json":
            raise ProviderError("malformed-response")
        try:
            result = json.loads(response.data)
            if not isinstance(result, dict):
                raise ValueError()
            return result
        except Exception:
            raise ProviderError("malformed-response") from None

    def transcribe_chirp(self, audio: bytes, *, language: str, operation_id: str) -> dict:
        if language not in self.configuration.languages:
            raise ProviderError("unsupported-language")
        if not isinstance(audio, bytes) or not 44 <= len(audio) <= 6_000_000:
            raise ProviderError("invalid-audio")
        try:
            with wave.open(io.BytesIO(audio), "rb") as source:
                rate, count = source.getframerate(), source.getnframes()
                if source.getnchannels() != 1 or source.getsampwidth() != 2 or source.getcomptype() != "NONE" or not 8000 <= rate <= 48000 or count <= 0:
                    raise ValueError()
                if count / rate >= 60:
                    raise ProviderError("long-audio-needs-streaming-or-batch")
                frames = source.readframes(count + 1)
                if len(frames) != count * 2:
                    raise ValueError()
            # Preserve samples exactly while omitting unrelated WAV metadata.
            encoded = io.BytesIO()
            with wave.open(encoded, "wb") as canonical:
                canonical.setnchannels(1); canonical.setsampwidth(2); canonical.setframerate(rate); canonical.writeframes(frames)
        except ProviderError:
            raise
        except Exception:
            raise ProviderError("invalid-audio") from None
        location, project = self.configuration.speech_location, self.configuration.project
        url = f"https://{location}-speech.googleapis.com/v2/projects/{project}/locations/{location}/recognizers/_:recognize"
        result = self._send(operation_id, "transcription", "chirp_3", url, {
            "config": {"autoDecodingConfig": {}, "languageCodes": [language], "model": "chirp_3"},
            "content": base64.b64encode(encoded.getvalue()).decode("ascii")})
        parts = result.get("results")
        if not isinstance(parts, list) or not 1 <= len(parts) <= 500:
            raise ProviderError("empty-or-malformed-transcript")
        text = []
        for part in parts:
            alternatives = part.get("alternatives") if isinstance(part, dict) else None
            if not isinstance(alternatives, list) or not alternatives or not isinstance(alternatives[0], dict) or not isinstance(alternatives[0].get("transcript"), str):
                raise ProviderError("malformed-transcript")
            text.append(alternatives[0]["transcript"])
        transcript = " ".join(text)
        if not transcript.strip() or _utf8_size(transcript) > 16_000:
            raise ProviderError("empty-or-oversized-transcript")
        billed = result.get("totalBilledTime")
        usage = {"totalBilledTime": billed} if isinstance(billed, str) and re.fullmatch(r"[0-9]{1,6}(?:\.[0-9]{1,9})?s", billed) else {}
        return {"text": transcript, "usage": usage}

    def generate_vertex_text(self, messages: list[dict], *, model: str, instructions: str, operation_id: str, max_output_tokens: int = 1024) -> dict:
        if model not in self.configuration.vertex_models or type(max_output_tokens) is not int or not 1 <= max_output_tokens <= 4096:
            raise ProviderError("unsupported-model-or-budget")
        if not isinstance(instructions, str) or _utf8_size(instructions) > 16_000 or not isinstance(messages, list) or not 1 <= len(messages) <= 40:
            raise ProviderError("invalid-messages")
        if any(not isinstance(message, dict) or set(message) != {"role", "text"} or message["role"] not in ("user", "model")
               or not isinstance(message["text"], str) or not message["text"].strip() for message in messages):
            raise ProviderError("invalid-messages")
        if sum(_utf8_size(message["text"]) for message in messages) > 100_000:
            raise ProviderError("messages-too-large")
        config = self.configuration
        host = "aiplatform.googleapis.com" if config.vertex_location == "global" else config.vertex_location + "-aiplatform.googleapis.com"
        url = f"https://{host}/v1/projects/{config.project}/locations/{config.vertex_location}/publishers/google/models/{model}:generateContent"
        result = self._send(operation_id, "text", model, url, {
            "systemInstruction": {"parts": [{"text": instructions}]},
            "contents": [{"role": message["role"], "parts": [{"text": message["text"]}]} for message in messages],
            "generationConfig": {"maxOutputTokens": max_output_tokens}})
        candidates = result.get("candidates")
        if not isinstance(candidates, list) or len(candidates) != 1 or not isinstance(candidates[0], dict) or candidates[0].get("finishReason") != "STOP":
            raise ProviderError("incomplete-or-blocked-generation")
        content = candidates[0].get("content")
        parts = content.get("parts") if isinstance(content, dict) else None
        if not isinstance(parts, list) or len(parts) > 100:
            raise ProviderError("malformed-generation")
        text = []
        for part in parts:
            if not isinstance(part, dict):
                raise ProviderError("malformed-generation")
            if part.get("thought") is True:
                continue
            if "functionCall" in part or not isinstance(part.get("text"), str):
                raise ProviderError("unsupported-nontext-generation")
            text.append(part["text"])
        output = "".join(text)
        if not output.strip() or _utf8_size(output) > 64_000:
            raise ProviderError("empty-or-oversized-generation")
        usage = result.get("usageMetadata", {})
        usage = {key: value for key, value in usage.items() if key in ("promptTokenCount", "candidatesTokenCount", "totalTokenCount") and type(value) is int and 0 <= value <= 10_000_000} if isinstance(usage, dict) else {}
        return {"text": output, "usage": usage}
