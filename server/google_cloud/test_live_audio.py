import asyncio
import base64
import unittest
import uuid

from adapters import ProviderError
from live_audio import LiveAudioBridge, LiveConfiguration


class Session:
    def __init__(self):
        self.sent, self.messages = [], []
        self.failure = None

    async def send_realtime_input(self, **value):
        self.sent.append(value)
        if self.failure: raise self.failure

    async def receive(self):
        for message in self.messages:
            yield message


class Context:
    def __init__(self):
        self.session = Session()
        self.opens = self.closes = 0

    async def __aenter__(self):
        self.opens += 1
        return self.session

    async def __aexit__(self, *args):
        self.closes += 1


def output(audio=b"\x01\x00", **flags):
    return {"serverContent": {"modelTurn": {"parts": [{"inlineData": {"mimeType": "audio/pcm;rate=24000", "data": base64.b64encode(audio).decode()}}]}, **flags}}


class LiveTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.context = Context()
        self.config = LiveConfiguration(("live-fixture",), True)
        self.connections, self.authorization = [], []

    def bridge(self, config=None, authorize=None):
        def connect(model, config):
            self.connections.append((model, config)); return self.context
        return LiveAudioBridge(config or self.config, authorize=authorize or (lambda *args: self.authorization.append(args)), connect=connect)

    async def open(self, bridge):
        await bridge.open(operation_id=str(uuid.uuid4()), model="live-fixture")

    async def testDisabledProductionAndDeniedDoNotConnect(self):
        for config in (LiveConfiguration(), LiveConfiguration(("live-fixture",), True, "production")):
            with self.assertRaises(ProviderError): await self.open(self.bridge(config))
        def denied(*args): raise ValueError("secret account information")
        with self.assertRaisesRegex(ProviderError, "live-access-denied"):
            await self.open(self.bridge(authorize=denied))
        self.assertEqual(self.connections, [])

    async def testRawAudioAndProvisionalTranscriptNeverCreateGradesOrTools(self):
        bridge = self.bridge(); await self.open(bridge)
        await bridge.send_audio(b"\x01\x00")
        await bridge.end_audio()
        self.assertEqual(self.context.session.sent, [{"audio": {"data": b"\x01\x00", "mime_type": "audio/pcm;rate=16000"}}, {"audio_stream_end": True}])
        self.context.session.messages = [output(inputTranscription={"text": "No, I don't know."}, outputTranscription={"text": "Let's review it."}, turnComplete=True)]
        events = [event async for event in bridge.receive_turn()]
        self.assertEqual([event.kind for event in events], ["input-transcript-provisional", "spoken-response-transcript", "audio", "turn-complete"])
        self.assertEqual(events[0].text, "No, I don't know.")
        self.assertNotIn("tools", self.connections[0][1])
        self.assertEqual([entry[1] for entry in self.authorization], ["live-connect", "live-audio-input", "live-audio-end", "live-output"])
        await bridge.close()
        self.assertEqual(self.context.closes, 1)

    async def testLocalBargeInSuppressesStaleAudioUntilServerAcknowledgement(self):
        bridge = self.bridge(); await self.open(bridge)
        interrupt = bridge.user_started_speaking()
        self.assertEqual(interrupt.kind, "interrupt-playback")
        self.assertEqual(bridge.normalize(output()), [])
        events = bridge.normalize(output(interrupted=True))
        self.assertEqual([event.kind for event in events], ["interrupt-playback"])
        fresh = bridge.normalize(output())
        self.assertEqual(fresh[0].kind, "audio")
        self.assertGreater(fresh[0].generation, interrupt.generation)
        await bridge.close()

    async def testInvalidChunksAndToolsDoNotReachPlaybackOrExecution(self):
        bridge = self.bridge(); await self.open(bridge)
        for invalid in (b"", b"x", b"\0" * 32002):
            with self.assertRaises(ProviderError): await bridge.send_audio(invalid)
        self.assertEqual(self.context.session.sent, [])
        for message in ({"toolCall": {"functionCalls": [{"name": "award_grade"}]}}, output(b"x"), {"serverContent": {"modelTurn": {"parts": [{"functionCall": {"name": "delete_deck"}}]}}}):
            with self.assertRaises(ProviderError): bridge.normalize(message)
        await bridge.close()

    async def testSendFailureClosesWithoutRetryAndCannotReopen(self):
        bridge = self.bridge(); await self.open(bridge)
        self.context.session.failure = ValueError("private SDK message and key")
        with self.assertRaisesRegex(ProviderError, "live-send-uncertain"):
            await bridge.send_audio(b"\0\0")
        self.assertEqual(len(self.context.session.sent), 1)
        self.assertEqual(self.context.closes, 1)
        with self.assertRaises(ProviderError): await self.open(bridge)
        self.assertEqual(len(self.connections), 1)

    async def testCancellationStopsTheSessionAndRejectsFutureAudio(self):
        bridge = self.bridge(); await self.open(bridge)
        self.context.session.failure = asyncio.CancelledError()
        with self.assertRaises(asyncio.CancelledError): await bridge.send_audio(b"\0\0")
        self.assertEqual(self.context.closes, 1)
        with self.assertRaises(ProviderError): await bridge.send_audio(b"\0\0")

    async def testOutputAuthorizationCanRevokeAnAlreadyOpenSession(self):
        def authorize(*args):
            if args[1] == "live-output": raise ValueError("revoked")
        bridge = self.bridge(authorize=authorize); await self.open(bridge)
        self.context.session.messages = [output()]
        with self.assertRaisesRegex(ProviderError, "live-access-denied"):
            _ = [event async for event in bridge.receive_turn()]
        self.assertEqual(self.context.closes, 1)

    async def testLateOutputAfterCloseCannotReachPlaybackOrTranscript(self):
        bridge = self.bridge(); await self.open(bridge)
        async def receive():
            await bridge.close()
            yield output(inputTranscription={"text": "late answer"})
        self.context.session.receive = receive
        self.assertEqual([event async for event in bridge.receive_turn()], [])
        with self.assertRaises(ProviderError): bridge.normalize(output())

    async def testRevokedInputClosesAnOpenSessionBeforeSending(self):
        def authorize(*args):
            if args[1] == "live-audio-input": raise ValueError("revoked")
        bridge = self.bridge(authorize=authorize); await self.open(bridge)
        with self.assertRaisesRegex(ProviderError, "live-access-denied"):
            await bridge.send_audio(b"\0\0")
        self.assertEqual(self.context.session.sent, [])
        self.assertEqual(self.context.closes, 1)

    async def testReceiveFrameAndDurationLimitsCloseInsteadOfContinuing(self):
        bridge = self.bridge(); await self.open(bridge)
        bridge.frames = 4096
        self.context.session.messages = [output()]
        with self.assertRaisesRegex(ProviderError, "live-session-limit"):
            _ = [event async for event in bridge.receive_turn()]
        self.assertEqual(self.context.closes, 1)


if __name__ == "__main__":
    unittest.main()
