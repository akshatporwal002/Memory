import base64
import hashlib
from dataclasses import replace
import io
import json
import unittest
import uuid
import wave
from unittest.mock import patch

from adapters import BoundedHTTPTransport, Configuration, GoogleCloudAdapters, HTTPResponse, ProviderError


def wav(seconds=1, rate=16000):
    result = io.BytesIO()
    with wave.open(result, "wb") as target:
        target.setnchannels(1); target.setsampwidth(2); target.setframerate(rate)
        target.writeframes(b"\x01\x00" * int(seconds * rate))
    return result.getvalue()


class FixtureTransport:
    def __init__(self, result=None, status=200):
        self.result, self.status, self.calls = result, status, []

    def post(self, url, headers, body, **limits):
        self.calls.append((url, headers, json.loads(body), limits))
        if isinstance(self.result, Exception):
            raise self.result
        return HTTPResponse(self.status, json.dumps(self.result).encode())


class AdapterTests(unittest.TestCase):
    def testConfigurationCannotEnableSandboxThroughStringOrAcceptCredentialFields(self):
        values = {"project": "engram-fixture", "speech_location": "eu", "vertex_location": "global", "vertex_models": ["gemini-fixture"]}
        configuration = Configuration.from_mapping(values)
        self.assertIs(configuration.sandbox_enabled, False)
        self.assertEqual(configuration.vertex_models, ("gemini-fixture",))
        for added in ({"sandbox_enabled": "false"}, {"service_account_key": "secret"}, {"vertex_models": "gemini-fixture"}):
            with self.assertRaises(ProviderError): Configuration.from_mapping(values | added)

    def testInvalidUnicodeIsRejectedWithoutLeakingProviderData(self):
        transport = FixtureTransport({"results": [{"alternatives": [{"transcript": "\ud800"}]}]})
        with self.assertRaisesRegex(ProviderError, "invalid-unicode"):
            self.adapter(transport).transcribe_chirp(wav(), language="en-AU", operation_id=self.operation)
        with self.assertRaisesRegex(ProviderError, "invalid-unicode"):
            self.adapter(FixtureTransport({})).generate_vertex_text([{"role": "user", "text": "\ud800"}], model="gemini-fixture", instructions="", operation_id=self.operation)
    def setUp(self):
        self.config = Configuration("engram-fixture", "us", "global", ("gemini-fixture",), sandbox_enabled=True)
        self.operation = str(uuid.uuid4())
        self.authorizations, self.tokens = [], []

    def testSpeechOutputUsesConfiguredVoiceAndReturnsValidatedPCMWithoutPlayback(self):
        audio = wav(rate=24000)
        transport = FixtureTransport({"audioContent": base64.b64encode(audio).decode()})
        config = replace(self.config, speech_output_voices=("en-AU-fixture",))
        result = self.adapter(transport, config).synthesize_google("A short explanation.", voice="en-AU-fixture", language="en-AU", operation_id=self.operation)
        self.assertEqual(result, audio)
        url, _, body, _ = transport.calls[0]
        self.assertEqual(url, "https://texttospeech.googleapis.com/v1/text:synthesize")
        self.assertEqual(body, {"input": {"text": "A short explanation."}, "voice": {"languageCode": "en-AU", "name": "en-AU-fixture"}, "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": 24000}})
        self.assertEqual(self.authorizations[0][:3], (self.operation, "speech-output", "en-AU-fixture"))

    def testSpeechOutputRejectsUnconfiguredVoiceAndUTF8BudgetBeforeDispatch(self):
        transport = FixtureTransport({})
        with self.assertRaisesRegex(ProviderError, "unsupported-voice-or-language"):
            self.adapter(transport).synthesize_google("text", voice="en-AU-fixture", language="en-AU", operation_id=self.operation)
        adapter = self.adapter(transport, replace(self.config, speech_output_voices=("en-AU-fixture",)))
        for text in (" ", "α" * 2001, "\ud800"):
            with self.assertRaises(ProviderError): adapter.synthesize_google(text, voice="en-AU-fixture", language="en-AU", operation_id=self.operation)
        with self.assertRaises(ProviderError): adapter.synthesize_google("text", voice="en-AU-fixture", language="en-US", operation_id=self.operation)
        self.assertEqual(self.tokens, []); self.assertEqual(transport.calls, [])

    def testSpeechOutputRejectsFakeTruncatedOrLongAudioWithoutRetry(self):
        config = replace(self.config, speech_output_voices=("en-AU-fixture",))
        for encoded in ("!invalid!", base64.b64encode(b"<html>not audio</html>").decode(), base64.b64encode(wav(rate=24000)[:-10]).decode(), base64.b64encode(wav(seconds=121, rate=24000)).decode()):
            transport = FixtureTransport({"audioContent": encoded})
            with self.assertRaisesRegex(ProviderError, "invalid-speech-audio"):
                self.adapter(transport, config).synthesize_google("text", voice="en-AU-fixture", language="en-AU", operation_id=self.operation)
            self.assertEqual(len(transport.calls), 1)

    def testAuthorizationBindsExactPayloadAndSeparatesInputFromSpeechOutput(self):
        transport = FixtureTransport({"audioContent": base64.b64encode(wav(rate=24000)).decode()})
        adapter = self.adapter(transport, replace(self.config, speech_output_voices=("en-AU-fixture",)))
        for text in ("First", "Different"):
            adapter.synthesize_google(text, voice="en-AU-fixture", language="en-AU", operation_id=self.operation)
        self.assertNotEqual(self.authorizations[0][3], self.authorizations[1][3])
        body = json.dumps(transport.calls[0][2], ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode()
        self.assertEqual(self.authorizations[0][3], hashlib.sha256(body).hexdigest())

    def adapter(self, transport, config=None, authorize=None):
        def token():
            self.tokens.append(True); return "server-fixture-token"
        return GoogleCloudAdapters(config or self.config,
            authorize=authorize or (lambda *request: self.authorizations.append(request)), access_token=token, transport=transport)

    def testChirpPreservesNegationAndSamplesWithNoAnswerHints(self):
        transport = FixtureTransport({"results": [{"alternatives": [{"transcript": "not ATP"}]}, {"alternatives": [{"transcript": "actually ADP"}]}], "totalBilledTime": "1.2s"})
        audio = wav()
        result = self.adapter(transport).transcribe_chirp(audio, language="en-AU", operation_id=self.operation)
        self.assertEqual(result, {"text": "not ATP actually ADP", "usage": {"totalBilledTime": "1.2s"}})
        url, _, body, limits = transport.calls[0]
        self.assertIn("us-speech.googleapis.com/v2/projects/engram-fixture/locations/us/recognizers/_:recognize", url)
        self.assertEqual(body["config"], {"autoDecodingConfig": {}, "languageCodes": ["en-AU"], "model": "chirp_3"})
        self.assertEqual(base64.b64decode(body["content"]), audio)
        self.assertEqual([request[:3] for request in self.authorizations], [(self.operation, "transcription", "chirp_3")])
        self.assertEqual(limits["timeout"], 120)

    def testLongTruncatedAndUnsupportedAudioFailBeforeCredentialsOrNetwork(self):
        transport = FixtureTransport({})
        adapter = self.adapter(transport)
        for audio in (wav(seconds=60), wav()[:-10], b"not audio"):
            with self.assertRaises(ProviderError):
                adapter.transcribe_chirp(audio, language="en-AU", operation_id=self.operation)
        with self.assertRaises(ProviderError):
            adapter.transcribe_chirp(wav(), language="made-up", operation_id=self.operation)
        self.assertEqual(transport.calls, []); self.assertEqual(self.tokens, [])

    def testDisabledAndProductionRejectBeforeAuthorizationOrADC(self):
        transport = FixtureTransport({})
        for config in (replace(self.config, sandbox_enabled=False), replace(self.config, environment="production")):
            with self.assertRaisesRegex(ProviderError, "not-configured"):
                self.adapter(transport, config).transcribe_chirp(wav(), language="en-AU", operation_id=self.operation)
        self.assertEqual(self.authorizations, []); self.assertEqual(self.tokens, []); self.assertEqual(transport.calls, [])

    def testAuthorizationDenialHasNoTokenOrProviderDispatch(self):
        transport = FixtureTransport({})
        def deny(*_): raise RuntimeError("private-user-data")
        with self.assertRaisesRegex(ProviderError, "access-denied") as error:
            self.adapter(transport, authorize=deny).transcribe_chirp(wav(), language="en-AU", operation_id=self.operation)
        self.assertNotIn("private-user-data", str(error.exception))
        self.assertEqual(self.tokens, []); self.assertEqual(transport.calls, [])

    def testVertexUsesConfiguredEndpointBudgetAndHidesThoughts(self):
        transport = FixtureTransport({"candidates": [{"finishReason": "STOP", "content": {"parts": [{"thought": True, "text": "internal"}, {"text": "Explanation"}]}}], "usageMetadata": {"totalTokenCount": 12, "private": "not returned"}})
        result = self.adapter(transport).generate_vertex_text([{"role": "user", "text": "question"}], model="gemini-fixture", instructions="evidence", operation_id=self.operation, max_output_tokens=256)
        self.assertEqual(result, {"text": "Explanation", "usage": {"totalTokenCount": 12}})
        url, _, body, _ = transport.calls[0]
        self.assertEqual(url, "https://aiplatform.googleapis.com/v1/projects/engram-fixture/locations/global/publishers/google/models/gemini-fixture:generateContent")
        self.assertEqual(body["generationConfig"], {"maxOutputTokens": 256})
        self.assertEqual(body["systemInstruction"], {"parts": [{"text": "evidence"}]})

    def testVertexRefusesPartialToolAndMalformedOutput(self):
        for candidate in ({"finishReason": "MAX_TOKENS", "content": {"parts": [{"text": "partial"}]}},
                          {"finishReason": "STOP", "content": {"parts": [{"functionCall": {"name": "delete"}}]}},
                          {"finishReason": "STOP", "content": {"parts": [{"text": "x" * 64001}]}}):
            with self.assertRaises(ProviderError):
                self.adapter(FixtureTransport({"candidates": [candidate]})).generate_vertex_text([{"role": "user", "text": "q"}], model="gemini-fixture", instructions="", operation_id=self.operation)

    def testNoAutomaticRetryAndSecretSafeProviderErrors(self):
        for transport in (FixtureTransport({"error": "server-fixture-token"}, status=403), FixtureTransport(RuntimeError("server-fixture-token"))):
            with self.assertRaises(ProviderError) as error:
                self.adapter(transport).transcribe_chirp(wav(), language="en-AU", operation_id=self.operation)
            self.assertNotIn("server-fixture-token", str(error.exception)); self.assertEqual(len(transport.calls), 1)

    def testUnapprovedModelsMalformedIDsAndEndpointInjectionAreRejected(self):
        transport = FixtureTransport({})
        with self.assertRaises(ProviderError):
            self.adapter(transport).generate_vertex_text([{"role": "user", "text": "q"}], model="other", instructions="", operation_id=self.operation)
        with self.assertRaises(ProviderError):
            self.adapter(transport).transcribe_chirp(wav(), language="en-AU", operation_id="arbitrary",)
        for config in (replace(self.config, project="../../other"), replace(self.config, speech_location="au"), replace(self.config, vertex_location="evil.example/"), replace(self.config, vertex_models=("../model",))):
            with self.assertRaises(ProviderError): self.adapter(transport, config)
        self.assertEqual(transport.calls, []); self.assertEqual(self.tokens, [])

    def testHTTPTransportBoundsReadAndDisablesRedirectsWithoutNetwork(self):
        class Response:
            headers = {"Content-Type": "application/json"}
            status = 200
            def __enter__(self): return self
            def __exit__(self, *_): pass
            def read(self, count): return b"x" * count
        class Opener:
            def open(self, *_args, **_kwargs): return Response()
        with patch("adapters.urllib.request.build_opener", return_value=Opener()) as build:
            with self.assertRaisesRegex(ProviderError, "response-too-large"):
                BoundedHTTPTransport().post("https://fixture.invalid", {}, b"{}", response_limit=20, timeout=1)
            handlers = build.call_args.args
            redirect = handlers[1]
            self.assertIsNone(redirect.redirect_request(None, None, 302, "", {}, "https://another.invalid"))


if __name__ == "__main__":
    unittest.main()
