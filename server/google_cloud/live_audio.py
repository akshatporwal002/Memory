"""Disabled-by-default Gemini Live bridge. No grades, tools or repository writes.

The host supplies verified-session authorization and a server-owned SDK client.
Input transcripts are provisional, never automatically committed study answers.
"""
from __future__ import annotations

import asyncio
import base64
from contextlib import suppress
from dataclasses import dataclass
import hashlib
import json
import re
import time
import uuid

from adapters import ProviderError, _utf8_size


@dataclass(frozen=True)
class LiveConfiguration:
    models: tuple[str, ...] = ()
    enabled: bool = False
    environment: str = "sandbox"

    def validate(self):
        if type(self.enabled) is not bool or self.environment not in ("sandbox", "production"):
            raise ProviderError("invalid-live-configuration")
        if not isinstance(self.models, tuple) or len(self.models) > 20 or any(not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,100}", model) for model in self.models):
            raise ProviderError("invalid-live-models")


@dataclass(frozen=True)
class LiveEvent:
    kind: str
    generation: int
    text: str = ""
    audio: bytes = b""


def sdk_connector(client):
    """Client lifecycle, region and ADC configuration belong to the server host."""
    return lambda model, config: client.aio.live.connect(model=model, config=config)


class LiveAudioBridge:
    def __init__(self, configuration: LiveConfiguration, *, authorize, connect):
        configuration.validate()
        self.configuration, self.authorize, self.connect = configuration, authorize, connect
        self.session = self.context = None
        self.operation = self.model = None
        self.generation = self.sequence = self.input_bytes = self.output_bytes = self.text_bytes = 0
        self.suppressed = False
        self.used = False
        self.deadline = None
        self.frames = 0
        self.receiving = False
        self.watchdog = None
        self.send_lock = asyncio.Lock()

    def _authorize(self, purpose, payload):
        digest = hashlib.sha256(payload).hexdigest()
        try:
            self.authorize(self.operation, purpose, self.model, digest, self.sequence)
        except Exception:
            raise ProviderError("live-access-denied") from None

    async def open(self, *, operation_id: str, model: str, instructions: str = ""):
        if self.used:
            raise ProviderError("live-session-already-used")
        if not self.configuration.enabled or self.configuration.environment != "sandbox":
            raise ProviderError("live-not-configured")
        if model not in self.configuration.models or not isinstance(instructions, str) or _utf8_size(instructions) > 16000:
            raise ProviderError("invalid-live-request")
        try:
            if str(uuid.UUID(operation_id)) != operation_id:
                raise ValueError()
        except Exception:
            raise ProviderError("invalid-operation") from None
        self.operation, self.model = operation_id, model
        setup = {"response_modalities": ["AUDIO"], "input_audio_transcription": {},
                 "output_audio_transcription": {}, "system_instruction": instructions}
        self._authorize("live-connect", json.dumps(setup, sort_keys=True, separators=(",", ":")).encode())
        self.used = True  # An uncertain connection is not automatically reopened.
        self.deadline = time.monotonic() + 300
        try:
            self.context = self.connect(model, setup)
            self.session = await asyncio.wait_for(self.context.__aenter__(), 15)
            self.watchdog = asyncio.create_task(self._expire())
        except asyncio.CancelledError:
            await self.close()
            raise
        except Exception:
            await self.close()
            raise ProviderError("live-connection-uncertain") from None

    async def _expire(self):
        await asyncio.sleep(max(0, self.deadline - time.monotonic()))
        await self.close()

    async def _authorize_send(self, purpose, payload):
        try:
            self._authorize(purpose, payload)
        except ProviderError:
            await self.close()
            raise

    def user_started_speaking(self) -> LiveEvent:
        # The app must flush playback immediately, before awaiting any network send.
        self.generation += 1
        self.suppressed = True
        return LiveEvent("interrupt-playback", self.generation)

    async def send_audio(self, pcm: bytes):
        async with self.send_lock:
            if self.session is None:
                raise ProviderError("live-session-closed")
            if time.monotonic() >= self.deadline:
                await self.close(); raise ProviderError("live-session-limit")
            if not isinstance(pcm, bytes) or not 0 < len(pcm) <= 32000 or len(pcm) % 2 or self.input_bytes + len(pcm) > 16000 * 2 * 120:
                raise ProviderError("invalid-live-audio")
            self.sequence += 1
            await self._authorize_send("live-audio-input", pcm)
            self.input_bytes += len(pcm)
            try:
                await asyncio.wait_for(self.session.send_realtime_input(audio={"data": pcm, "mime_type": "audio/pcm;rate=16000"}), 10)
            except asyncio.CancelledError:
                await self.close(); raise
            except Exception:
                await self.close()
                raise ProviderError("live-send-uncertain") from None

    async def end_audio(self):
        async with self.send_lock:
            if self.session is None:
                raise ProviderError("live-session-closed")
            if time.monotonic() >= self.deadline:
                await self.close(); raise ProviderError("live-session-limit")
            self.sequence += 1
            await self._authorize_send("live-audio-end", b"audio-stream-end")
            try:
                await asyncio.wait_for(self.session.send_realtime_input(audio_stream_end=True), 10)
            except asyncio.CancelledError:
                await self.close(); raise
            except Exception:
                await self.close()
                raise ProviderError("live-send-uncertain") from None

    async def receive_turn(self):
        if self.session is None:
            raise ProviderError("live-session-closed")
        if self.receiving:
            raise ProviderError("live-receive-already-active")
        self.receiving = True
        session = self.session
        iterator = session.receive().__aiter__()
        try:
            while True:
                remaining = self.deadline - time.monotonic()
                if remaining <= 0:
                    raise ProviderError("live-session-limit")
                try:
                    message = await asyncio.wait_for(iterator.__anext__(), min(30, remaining))
                except StopAsyncIteration:
                    return  # SDK receive() ends per turn; this does not reconnect.
                if self.session is not session:
                    return  # Closing/account switching rejects late provider output.
                if not isinstance(message, dict):
                    message = message.model_dump(mode="json", by_alias=True, exclude_none=True)
                self.sequence += 1
                payload = json.dumps(message, ensure_ascii=True, separators=(",", ":")).encode()
                if len(payload) > 512000:
                    raise ProviderError("live-frame-limit")
                self._authorize("live-output", payload)
                for event in self.normalize(message):
                    yield event
        except asyncio.CancelledError:
            await self.close(); raise
        except ProviderError:
            await self.close(); raise
        except Exception:
            await self.close()
            raise ProviderError("live-receive-uncertain") from None
        finally:
            self.receiving = False

    def normalize(self, message: dict) -> list[LiveEvent]:
        if self.session is None:
            raise ProviderError("live-session-closed")
        self.frames += 1
        if self.frames > 4096 or self.deadline is not None and time.monotonic() >= self.deadline:
            raise ProviderError("live-session-limit")
        if not isinstance(message, dict) or message.get("toolCall") or message.get("tool_call"):
            raise ProviderError("unsupported-live-tool")
        content = message.get("serverContent", {})
        if not isinstance(content, dict):
            raise ProviderError("malformed-live-content")
        events = []
        interrupted = content.get("interrupted") is True
        if interrupted:
            self.generation += 1
            self.suppressed = False
            events.append(LiveEvent("interrupt-playback", self.generation))
        for key, kind in (("inputTranscription", "input-transcript-provisional"), ("outputTranscription", "spoken-response-transcript")):
            value = content.get(key)
            if value is not None:
                if not isinstance(value, dict) or not isinstance(value.get("text", ""), str):
                    raise ProviderError("malformed-live-transcript")
                text = value.get("text", "")
                self.text_bytes += _utf8_size(text)
                if self.text_bytes > 64000:
                    raise ProviderError("live-text-limit")
                if text and (kind == "input-transcript-provisional" or not self.suppressed and not interrupted):
                    events.append(LiveEvent(kind, self.generation, text=text))
        turn = content.get("modelTurn", {})
        if not isinstance(turn, dict) or not isinstance(turn.get("parts", []), list) or len(turn.get("parts", [])) > 100:
            raise ProviderError("malformed-live-turn")
        for part in turn.get("parts", []):
            if not isinstance(part, dict) or part.get("functionCall"):
                raise ProviderError("unsupported-live-part")
            if part.get("thought") is True:
                continue
            inline = part.get("inlineData")
            if inline is None:
                continue
            if not isinstance(inline, dict) or inline.get("mimeType") != "audio/pcm;rate=24000" or not isinstance(inline.get("data"), str) or len(inline["data"]) > 256000:
                raise ProviderError("malformed-live-audio")
            try:
                audio = base64.b64decode(inline["data"], validate=True)
            except Exception:
                raise ProviderError("malformed-live-audio") from None
            if not audio or len(audio) % 2:
                raise ProviderError("malformed-live-audio")
            self.output_bytes += len(audio)
            if self.output_bytes > 24000 * 2 * 300:
                raise ProviderError("live-output-limit")
            if not self.suppressed and not interrupted:
                events.append(LiveEvent("audio", self.generation, audio=audio))
        if content.get("turnComplete") is True:
            self.suppressed = False
            events.append(LiveEvent("turn-complete", self.generation))
        # Usage/connection-control frames are host data, never executable actions.
        return events

    async def close(self):
        watchdog, self.watchdog = self.watchdog, None
        if watchdog is not None and watchdog is not asyncio.current_task():
            watchdog.cancel()
            with suppress(asyncio.CancelledError):
                await watchdog
        context = self.context
        self.context = self.session = None
        self.suppressed = True
        self.generation += 1
        if context is not None:
            try:
                await asyncio.wait_for(context.__aexit__(None, None, None), 5)
            except Exception:
                pass  # Never leak SDK/provider exception bodies.
