"""Generate/validate fixtures using official Anki 26.8.1 in disposable profiles.
Set PYTHONPATH to the separately installed official backend. No user profile is touched.
Usage: python anki_fixture_roundtrip.py generate|verify [fixture-directory]
"""
from __future__ import annotations
import base64, hashlib, io, json, math, struct, sys, tempfile, time, wave, zipfile
from pathlib import Path
from anki.collection import Collection
from anki.import_export_pb2 import ExportAnkiPackageOptions, ImportAnkiPackageOptions, ImportAnkiPackageRequest
from anki import buildinfo

ROOT = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parents[1] / "Tests/AnkiAdapterTests/Fixtures"
ROOT.mkdir(parents=True, exist_ok=True)

def export(col, name, legacy=True, scheduling=True):
    col.export_anki_package(out_path=str(ROOT / name), options=ExportAnkiPackageOptions(with_scheduling=scheduling, with_deck_configs=True, with_media=True, legacy=legacy), limit=None)

def generate():
    with tempfile.TemporaryDirectory(prefix="engram-anki-fixture-") as temporary:
        col = Collection(str(Path(temporary) / "collection.anki2"))
        did = col.decks.id("Science::Biology")
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=")
        sound = io.BytesIO()
        with wave.open(sound, "wb") as audio:
            audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(8000)
            audio.writeframes(b"".join(struct.pack("<h", int(math.sin(i * 2 * math.pi * 440 / 8000) * 2000)) for i in range(800)))
        col.media.write_data("cell.png", png); col.media.write_data("tone.wav", sound.getvalue())
        basic = col.new_note(col.models.by_name("Basic")); basic["Front"] = 'Cell café 日本語<br><img src="cell.png">'; basic["Back"] = "A cell [sound:tone.wav]"
        basic.tags = ["biology", "unicode"]; col.add_note(basic, did)
        reverse = col.new_note(col.models.by_name("Basic (and reversed card)")); reverse["Front"] = "mitochondrion"; reverse["Back"] = "organelle"; col.add_note(reverse, did)
        cloze = col.new_note(col.models.by_name("Cloze")); cloze["Text"] = "{{c1::DNA::molecule}} encodes {{c2::information}}."; cloze["Back Extra"] = "Genetics"; col.add_note(cloze, did)
        cid = basic.cards()[0].id
        stamp = int(time.time()) - 86400
        memory = json.dumps({"s": 12.3, "d": 4.5, "dr": 0.9, "lrt": stamp})
        col.db.execute("UPDATE cards SET type=2, queue=2, due=?, ivl=12, reps=3, lapses=1, data=? WHERE id=?", col.sched.today + 5, memory, cid)
        col.db.execute("INSERT INTO revlog VALUES (?, ?, -1, 3, 12, 5, 488, 1500, 1)", stamp * 1000, cid)
        col.sched.suspend_cards([reverse.cards()[1].id])
        export(col, "anki-26.8.1-legacy.apkg")
        export(col, "anki-26.8.1-sharing.apkg", scheduling=False)
        export(col, "anki-26.8.1-modern.apkg", legacy=False)
        col.export_collection_package(str(ROOT / "anki-26.8.1-legacy.colpkg"), True, True)
        col.reopen()
        col.close()
    with zipfile.ZipFile(ROOT / "anki-26.8.1-legacy.apkg") as source, zipfile.ZipFile(ROOT / "anki-26.8.1-missing-media.apkg", "w", zipfile.ZIP_DEFLATED) as target:
        for name in source.namelist():
            if name != "0": target.writestr(name, source.read(name))
    with zipfile.ZipFile(ROOT / "unsafe-path.apkg", "w") as target: target.writestr("../escape", b"bad")
    record = {"anki_version": buildinfo.version, "generator": "official anki Python backend; disposable collection"}
    record["files"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(ROOT.iterdir()) if p.suffix in {".apkg", ".colpkg"}}
    (ROOT / "provenance.json").write_text(json.dumps(record, indent=2), encoding="utf8")
    print(json.dumps(record, indent=2))

def verify():
    results = []
    source_fixture = Path(__file__).resolve().parents[1] / "Tests/AnkiAdapterTests/Fixtures/anki-26.8.1-legacy.apkg"
    with tempfile.TemporaryDirectory(prefix="engram-anki-baseline-") as temporary:
        baseline = Collection(str(Path(temporary) / "collection.anki2"))
        baseline.import_anki_package(ImportAnkiPackageRequest(package_path=str(source_fixture), options=ImportAnkiPackageOptions(with_scheduling=True, with_deck_configs=True)))
        source_notes = {row[0]: row[1:] for row in baseline.db.all("SELECT guid,flds,tags FROM notes")}
        source_history = baseline.db.all("SELECT id,ease,ivl,lastIvl,factor,time,type FROM revlog ORDER BY id")
        source_cards = {(row[0], row[1]): row[2:] for row in baseline.db.all("SELECT n.guid,c.ord,c.type,c.queue,c.ivl,c.data,c.due FROM cards c JOIN notes n ON n.id=c.nid")}
        source_today = baseline.sched.today
        source_media = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(baseline.media.dir()).iterdir() if p.is_file()}
        baseline.close()
    for path in sorted(ROOT.glob("engram-*.apkg")):
        with tempfile.TemporaryDirectory(prefix="engram-anki-verification-") as temporary:
            col = Collection(str(Path(temporary) / "collection.anki2"))
            col.import_anki_package(ImportAnkiPackageRequest(package_path=str(path), options=ImportAnkiPackageOptions(with_scheduling=True, with_deck_configs=True)))
            notes = col.db.all("SELECT id,guid,flds,tags FROM notes ORDER BY id")
            cards = col.db.all("SELECT id,nid,ord,type,queue,due,ivl,data FROM cards ORDER BY id")
            history = col.db.all("SELECT id,cid,ease,ivl,lastIvl,factor,time,type FROM revlog ORDER BY id")
            assert len(notes) == 3 and len(cards) == 5, (path.name, notes, cards)
            assert any("日本語" in row[2] for row in notes)
            assert (Path(col.media.dir()) / "cell.png").exists()
            assert (Path(col.media.dir()) / "tone.wav").exists()
            if "created" in path.name:
                assert sorted(row[2:] for row in notes) == sorted(source_notes.values())
            else: assert {row[1]: row[2:] for row in notes} == source_notes
            assert {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(col.media.dir()).iterdir() if p.is_file()} == source_media
            if "sharing" in path.name:
                assert not history and all(row[3] == 0 and row[4] == 0 for row in cards)
            else:
                assert len(history) >= 1
                assert sum(row[4] == -1 for row in cards) == 1
                actual_history = col.db.all("SELECT id,ease,ivl,lastIvl,factor,time,type FROM revlog ORDER BY id")
                assert all(row in actual_history for row in source_history)
                if "reviewed" in path.name:
                    assert len(history) == 2 and any(row[2] == 4 for row in history)
                else: assert actual_history == source_history
                for row in col.db.all("SELECT n.guid,c.ord,c.type,c.queue,c.ivl,c.data,c.due FROM cards c JOIN notes n ON n.id=c.nid"):
                    expected = source_cards[(row[0], row[1])]
                    if "reviewed" not in path.name or expected[0] == 2: assert row[2:5] == expected[:3], (row, expected)
                    if expected[0] == 2:
                        actual_memory, original_memory = json.loads(row[5]), json.loads(expected[3])
                        assert abs(actual_memory["s"] - original_memory["s"]) < 0.0001
                        assert abs(actual_memory["d"] - original_memory["d"]) < 0.0001
                        assert actual_memory["lrt"] == original_memory["lrt"]
                        assert row[6] - col.sched.today == expected[4] - source_today
            # Repeating a transfer must not create extra notes/cards/history.
            counts = [len(notes), len(cards), len(history)]
            col.import_anki_package(ImportAnkiPackageRequest(package_path=str(path), options=ImportAnkiPackageOptions(with_scheduling=True, with_deck_configs=True)))
            assert [col.db.scalar("SELECT count(*) FROM notes"), col.db.scalar("SELECT count(*) FROM cards"), col.db.scalar("SELECT count(*) FROM revlog")] == counts
            results.append({"file": path.name, "notes": notes, "cards": cards, "history": history, "passed": True})
            col.close()
    assert results, "Swift tests must first create engram-*.apkg artifacts in the requested directory"
    (ROOT / "roundtrip-results.json").write_text(json.dumps({"anki_version": buildinfo.version, "results": results}, indent=2), encoding="utf8")
    print("Verified", len(results), "Engram exports in disposable Anki collections.")

if __name__ == "__main__":
    if sys.argv[1] == "generate": generate()
    elif sys.argv[1] == "verify": verify()
    else: raise SystemExit("Expected generate or verify")
