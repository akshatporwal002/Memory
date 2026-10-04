from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
import uuid

from voice_ledger import LedgerError, Rate, VerifiedTopUp, VoiceLedger


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = str(Path(self.directory.name) / "sandbox.sqlite")
        self.account = str(uuid.uuid4())
        self.rate = Rate("openai", "transcribe-fixture", "transcription", "fixture-v1", 2)
        self.purchase = VerifiedTopUp(self.account, "123456", "fixture.credit", "sandbox", 100)
        self.verifications = []

    def ledger(self, *, enabled=True, account=None, purchase=None, rate=None, environment="sandbox"):
        def verify(signed):
            self.verifications.append(signed)
            return purchase or self.purchase
        return VoiceLedger(self.path, authenticate=lambda: account or self.account, verify_purchase=verify, rates=(rate or self.rate,), enabled=enabled, environment=environment)

    def reserve(self, ledger, operation=None, maximum=20):
        operation = operation or str(uuid.uuid4())
        ledger.reserve(operation, provider="openai", model="transcribe-fixture", purpose="transcription", rate_version="fixture-v1", maximum_usage=maximum)
        return operation

    def funded(self):
        ledger = self.ledger(); ledger.accept_purchase("fixture-signed-not-Apple-JWS")
        return ledger

    def testDisabledProductionAndUnauthenticatedCannotMintOrReserve(self):
        ledger = self.ledger(enabled=False)
        with self.assertRaises(LedgerError): ledger.accept_purchase("fixture")
        self.assertEqual(self.verifications, [])
        for environment in ("production", "other"):
            with self.assertRaises(LedgerError): self.ledger(environment=environment)
        ledger = self.ledger(account="not-a-verified-account")
        with self.assertRaisesRegex(LedgerError, "unauthenticated"): ledger.available()

    def testPurchaseReplayIsDurableAndCannotMoveToAnotherAccount(self):
        ledger = self.funded()
        self.assertFalse(ledger.accept_purchase("same-signed-transaction"))
        self.assertEqual(ledger.available(), 100)
        self.assertEqual(self.ledger().available(), 100)
        other = str(uuid.uuid4())
        with self.assertRaisesRegex(LedgerError, "purchase-conflict"):
            self.ledger(account=other, purchase=replace(self.purchase, account=other)).accept_purchase("same-transaction")
        self.assertEqual(self.ledger(account=other).available(), 0)

    def testVerifiedPurchaseBindingAndAmountAreRequired(self):
        for purchase in (replace(self.purchase, account=str(uuid.uuid4())), replace(self.purchase, environment="production"), replace(self.purchase, credit_units=True), replace(self.purchase, credit_units=-1)):
            with self.assertRaises(LedgerError): self.ledger(purchase=purchase).accept_purchase("fixture")
        self.assertEqual(self.ledger().available(), 0)

    def testReserveReplayAndPartialSettlementChargeExactlyOnce(self):
        ledger = self.funded(); operation = self.reserve(ledger)
        self.reserve(ledger, operation)
        self.assertEqual(ledger.available(), 60)
        ledger.begin_dispatch(operation, payload_hash="a" * 64)
        self.assertEqual(ledger.settle(operation, actual_usage=10), 20)
        self.assertEqual(self.ledger().settle(operation, actual_usage=10), 20)
        self.assertEqual(ledger.available(), 80)
        with self.assertRaisesRegex(LedgerError, "settlement-conflict"): ledger.settle(operation, actual_usage=11)

    def testCrashOrTimeoutCannotRedispatchOrReleaseHeldProviderUsage(self):
        ledger = self.funded(); operation = self.reserve(ledger)
        ledger.begin_dispatch(operation, payload_hash="b" * 64)
        ledger = self.ledger()  # Re-open after a process crash.
        for payload in ("b" * 64, "c" * 64):
            with self.assertRaisesRegex(LedgerError, "dispatch-already-started"): ledger.begin_dispatch(operation, payload_hash=payload)
        ledger.mark_uncertain(operation); ledger.mark_uncertain(operation)
        with self.assertRaises(LedgerError): ledger.release(operation)
        self.assertEqual(ledger.available(), 60)
        self.assertEqual(ledger.settle(operation, actual_usage=15), 30)
        self.assertEqual(ledger.available(), 70)

    def testUnusedReservationReleaseDoesNotExpirePurchasedCredits(self):
        ledger = self.funded(); operation = self.reserve(ledger)
        ledger.release(operation); ledger.release(operation)
        self.assertEqual(self.ledger().available(), 100)
        with self.assertRaises(LedgerError): ledger.begin_dispatch(operation, payload_hash="a" * 64)

    def testSimultaneousReservationsCannotOverspendAcrossConnections(self):
        self.funded()
        def reserve():
            try:
                self.reserve(self.ledger(), maximum=40)
                return "reserved"
            except LedgerError as error:
                return str(error)
        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(lambda _: reserve(), range(2)))
        self.assertCountEqual(outcomes, ["reserved", "insufficient-credit"])
        self.assertEqual(self.ledger().available(), 20)

    def testFrozenRatesAndReservationBoundsCannotChangeSilently(self):
        ledger = self.funded(); operation = self.reserve(ledger)
        with self.assertRaisesRegex(LedgerError, "rate-version-conflict"):
            self.ledger(rate=replace(self.rate, credit_units_per_usage_unit=3))
        with self.assertRaisesRegex(LedgerError, "operation-conflict"):
            self.reserve(ledger, operation, maximum=21)
        ledger.begin_dispatch(operation, payload_hash="a" * 64)
        with self.assertRaisesRegex(LedgerError, "usage-exceeds-reservation"):
            ledger.settle(operation, actual_usage=21)
        self.assertEqual(ledger.available(), 60)

    def testForeignAccountCannotDispatchOrSettleAnotherLearnersReservation(self):
        ledger = self.funded(); operation = self.reserve(ledger)
        other = self.ledger(account=str(uuid.uuid4()))
        with self.assertRaises(LedgerError): other.begin_dispatch(operation, payload_hash="a" * 64)
        with self.assertRaises(LedgerError): other.settle(operation, actual_usage=10)
        with self.assertRaises(LedgerError): other.release(operation)


if __name__ == "__main__":
    unittest.main()
