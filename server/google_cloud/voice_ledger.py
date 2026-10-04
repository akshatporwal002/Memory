"""Sandbox-only durable managed-voice accounting foundation.

Requires verified-session and purchase-verification callbacks. No HTTP endpoint,
Apple verifier, provider dispatch, test credit mint or production activation.
"""
from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import re
import sqlite3
import uuid


class LedgerError(Exception):
    pass


@dataclass(frozen=True)
class Rate:
    provider: str
    model: str
    purpose: str
    version: str
    credit_units_per_usage_unit: int


@dataclass(frozen=True)
class VerifiedTopUp:
    account: str
    transaction: str
    product: str
    environment: str
    credit_units: int


class VoiceLedger:
    def __init__(self, path, *, authenticate, verify_purchase, rates: tuple[Rate, ...], enabled=False, environment="sandbox"):
        if type(enabled) is not bool or environment != "sandbox":
            raise LedgerError("production-unavailable")
        self.path, self.authenticate, self.verify_purchase = path, authenticate, verify_purchase
        self.enabled, self.environment = enabled, environment
        self.rates = {}
        for rate in rates:
            if not isinstance(rate, Rate) or rate.purpose not in ("transcription", "speech-output") or not all(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,100}", value) for value in (rate.provider, rate.model, rate.version)) or type(rate.credit_units_per_usage_unit) is not int or not 0 < rate.credit_units_per_usage_unit <= 1_000_000_000:
                raise LedgerError("invalid-rate")
            key = (rate.provider, rate.model, rate.purpose, rate.version)
            if key in self.rates: raise LedgerError("duplicate-rate")
            self.rates[key] = rate
        with self._database() as connection:
            connection.execute("CREATE TABLE IF NOT EXISTS rates (provider TEXT, model TEXT, purpose TEXT, version TEXT, unit_rate INTEGER NOT NULL, PRIMARY KEY(provider,model,purpose,version))")
            for key, rate in self.rates.items():
                existing = connection.execute("SELECT unit_rate FROM rates WHERE provider=? AND model=? AND purpose=? AND version=?", key).fetchone()
                if existing and existing[0] != rate.credit_units_per_usage_unit: raise LedgerError("rate-version-conflict")
                connection.execute("INSERT OR IGNORE INTO rates VALUES (?,?,?,?,?)", (*key, rate.credit_units_per_usage_unit))
            connection.execute("CREATE TABLE IF NOT EXISTS purchases (environment TEXT, transaction_id TEXT, account TEXT NOT NULL, product TEXT NOT NULL, credits INTEGER NOT NULL, PRIMARY KEY(environment,transaction_id))")
            connection.execute("CREATE TABLE IF NOT EXISTS operations (environment TEXT, account TEXT, operation TEXT, provider TEXT NOT NULL, model TEXT NOT NULL, purpose TEXT NOT NULL, rate_version TEXT NOT NULL, unit_rate INTEGER NOT NULL, maximum_usage INTEGER NOT NULL, reserved INTEGER NOT NULL, state TEXT NOT NULL, payload_hash TEXT, actual_usage INTEGER, charged INTEGER, PRIMARY KEY(environment,account,operation))")

    @contextmanager
    def _database(self):
        connection = sqlite3.connect(self.path, timeout=5)
        connection.row_factory = sqlite3.Row
        try:
            connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.commit()
        except Exception:
            connection.rollback(); raise
        finally:
            connection.close()

    def _account(self):
        if not self.enabled: raise LedgerError("billing-not-configured")
        try:
            value = self.authenticate()
            if not isinstance(value, str) or str(uuid.UUID(value)) != value: raise ValueError()
            return value
        except Exception:
            raise LedgerError("unauthenticated") from None

    @staticmethod
    def _operation(value):
        try:
            if not isinstance(value, str) or str(uuid.UUID(value)) != value: raise ValueError()
        except Exception:
            raise LedgerError("invalid-operation") from None

    def _available(self, connection, account):
        purchased = connection.execute("SELECT COALESCE(SUM(credits),0) FROM purchases WHERE environment=? AND account=?", (self.environment, account)).fetchone()[0]
        spent = connection.execute("SELECT COALESCE(SUM(charged),0) FROM operations WHERE environment=? AND account=? AND state='succeeded'", (self.environment, account)).fetchone()[0]
        held = connection.execute("SELECT COALESCE(SUM(reserved),0) FROM operations WHERE environment=? AND account=? AND state IN ('reserved','dispatching','uncertain')", (self.environment, account)).fetchone()[0]
        return purchased - spent - held

    def available(self):
        account = self._account()
        with self._database() as connection: return self._available(connection, account)

    def accept_purchase(self, signed_transaction: str):
        account = self._account()
        if not isinstance(signed_transaction, str) or not 0 < len(signed_transaction) <= 32000:
            raise LedgerError("invalid-purchase")
        try:
            purchase = self.verify_purchase(signed_transaction)
        except Exception:
            raise LedgerError("purchase-unverified") from None
        if not isinstance(purchase, VerifiedTopUp) or purchase.account != account or purchase.environment != self.environment or not isinstance(purchase.transaction, str) or not re.fullmatch(r"[0-9]{1,40}", purchase.transaction) or not isinstance(purchase.product, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,150}", purchase.product) or type(purchase.credit_units) is not int or not 0 < purchase.credit_units <= 1_000_000_000_000:
            raise LedgerError("purchase-mismatch")
        with self._database() as connection:
            existing = connection.execute("SELECT account,product,credits FROM purchases WHERE environment=? AND transaction_id=?", (self.environment, purchase.transaction)).fetchone()
            expected = (account, purchase.product, purchase.credit_units)
            if existing:
                if tuple(existing) != expected: raise LedgerError("purchase-conflict")
                return False
            connection.execute("INSERT INTO purchases VALUES (?,?,?,?,?)", (self.environment, purchase.transaction, *expected))
            return True

    def reserve(self, operation, *, provider, model, purpose, rate_version, maximum_usage):
        account = self._account(); self._operation(operation)
        rate = self.rates.get((provider, model, purpose, rate_version))
        if rate is None or type(maximum_usage) is not int or not 0 < maximum_usage <= 1_000_000:
            raise LedgerError("unsupported-rate-or-usage")
        cost = maximum_usage * rate.credit_units_per_usage_unit
        values = (provider, model, purpose, rate_version, rate.credit_units_per_usage_unit, maximum_usage, cost)
        with self._database() as connection:
            existing = self._read(connection, account, operation, required=False)
            if existing:
                if tuple(existing[key] for key in ("provider", "model", "purpose", "rate_version", "unit_rate", "maximum_usage", "reserved")) != values:
                    raise LedgerError("operation-conflict")
                return dict(existing)
            if self._available(connection, account) < cost: raise LedgerError("insufficient-credit")
            connection.execute("INSERT INTO operations (environment,account,operation,provider,model,purpose,rate_version,unit_rate,maximum_usage,reserved,state) VALUES (?,?,?,?,?,?,?,?,?,?,?)", (self.environment, account, operation, *values, "reserved"))
            return dict(self._read(connection, account, operation))

    def _read(self, connection, account, operation, required=True):
        row = connection.execute("SELECT * FROM operations WHERE environment=? AND account=? AND operation=?", (self.environment, account, operation)).fetchone()
        if row is None and required: raise LedgerError("operation-unavailable")
        return row

    def begin_dispatch(self, operation, *, payload_hash):
        account = self._account(); self._operation(operation)
        if not isinstance(payload_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", payload_hash): raise LedgerError("invalid-payload-hash")
        with self._database() as connection:
            row = self._read(connection, account, operation)
            if row["state"] != "reserved": raise LedgerError("dispatch-already-started")
            connection.execute("UPDATE operations SET state='dispatching',payload_hash=? WHERE environment=? AND account=? AND operation=?", (payload_hash, self.environment, account, operation))
        # Journal commits before the host calls the provider. A crashed dispatch
        # stays held; the host must reconcile rather than silently send again.

    def mark_uncertain(self, operation):
        account = self._account(); self._operation(operation)
        with self._database() as connection:
            row = self._read(connection, account, operation)
            if row["state"] not in ("dispatching", "uncertain"): raise LedgerError("invalid-operation-state")
            connection.execute("UPDATE operations SET state='uncertain' WHERE environment=? AND account=? AND operation=?", (self.environment, account, operation))

    def settle(self, operation, *, actual_usage):
        account = self._account(); self._operation(operation)
        if type(actual_usage) is not int or actual_usage < 0: raise LedgerError("invalid-usage")
        with self._database() as connection:
            row = self._read(connection, account, operation)
            if row["state"] == "succeeded":
                if row["actual_usage"] != actual_usage: raise LedgerError("settlement-conflict")
                return row["charged"]
            if row["state"] not in ("dispatching", "uncertain"): raise LedgerError("invalid-operation-state")
            if actual_usage > row["maximum_usage"]: raise LedgerError("usage-exceeds-reservation")
            cost = actual_usage * row["unit_rate"]
            connection.execute("UPDATE operations SET state='succeeded',actual_usage=?,charged=? WHERE environment=? AND account=? AND operation=?", (actual_usage, cost, self.environment, account, operation))
            return cost

    def release(self, operation):
        account = self._account(); self._operation(operation)
        with self._database() as connection:
            row = self._read(connection, account, operation)
            if row["state"] == "released": return
            if row["state"] != "reserved": raise LedgerError("dispatched-reservation-cannot-release")
            connection.execute("UPDATE operations SET state='released' WHERE environment=? AND account=? AND operation=?", (self.environment, account, operation))
