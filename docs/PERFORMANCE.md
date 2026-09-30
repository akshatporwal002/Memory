# Storage and backup performance

Measured 3 September 2026 on Windows 11 build 26200, 16 logical processors, 32 GiB RAM, Swift 6.3.3 release configuration. These are one cold-process sample per synthetic case, not percentiles or an Apple responsiveness claim. File-system cache and host activity were not controlled. No frame timing or process memory high-water was measured.

## Reproduce

From the repository root with the Swift environment initialized:

```powershell
. ./scripts/Enter-SwiftEnvironment.ps1
swift run -c release EngramBenchmark validation/storage-benchmark-local.json
```

The tool creates uniquely named temporary synthetic libraries and removes only those directories afterward. It never opens app-container data. Each basic card has a short question and approximately 320 characters of Unicode answer text. Attachment cases contain 16 MiB of deterministic pseudo-random bytes, representing already-compressed files. Those bytes are not a valid image and are not a media-decoding test. Schedules use the production FSRS adapter and the default daily queue limits. Construction time is excluded.

It measures the initial atomic write, repository reopen, session start, reveal, one grade, complete native backup write and backup read. It requires whole-snapshot equality after durable reopen and native backup restoration, and exactly one saved review event. All four cases passed both equality checks before and after the change.

## Finding and change

The original repository decoded the full disk JSON, including all base64 media, on every commit merely to compare revision/library identity. With 16 MiB of attachments this imposed a multi-second delay on reveal and grade. The repository now retains the exact last-read/written bytes, compares fresh raw file bytes before commit, and updates both the cached bytes and in-memory snapshot only after successful atomic replacement. This also detects external edits which retain the same revision, and external deletion; both defects were reproduced before remediation.

| Library | Grade before | Grade after | Reveal after | Reopen after | Backup write / read after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1,000 cards, no media | 96 ms | 26 ms | 27 ms | 69 ms | 28 / 75 ms |
| 1,000 cards, 16 MiB media | 2,314 ms | 247 ms | 247 ms | 2,176 ms | 423 / 200 ms |
| 10,000 cards, no media | 933 ms | 238 ms | 227 ms | 668 ms | 262 / 724 ms |
| 10,000 cards, 16 MiB media | 3,243 ms | 475 ms | 456 ms | 2,646 ms | 660 / 736 ms |

Raw baseline: `validation/storage-benchmark-baseline-windows.json`. Raw optimized result: `validation/storage-benchmark-windows.json`. Both are retained; the benchmark does not enforce arbitrary machine-specific timing thresholds. The full 62-test regression run is in `validation/persistence-optimized-tests.log`.

## Limits and follow-up

The exact-byte cache retains one extra serialized library in memory: about 31.7 MiB for the largest measured case, in addition to the decoded model and operation temporaries. The cache, freshly read bytes and newly encoded bytes can coexist during a commit. Near the nominal 512-MiB raw-media validation cap, three base64 representations plus decoded media could exceed 2.5 GiB before other overhead. That is not a supported iPhone memory claim; neither peak memory nor the cap was exercised. Raw comparison and JSON encoding still scale with the whole snapshot. Startup still performs full decoding, which is why opening the larger attachment case takes seconds; App opens the repository away from the main actor and shows progress. This is a measured limit, not a claim that all libraries up to the validation caps are responsive.

Independent review found no production rollback/CAS defect but noticed the old moved-directory fault test now stopped at the stronger conflict guard. It was relabelled accurately and a genuine Windows atomic-replacement fault was added: a temporary readable file handle denies DELETE sharing, Foundation returns `NSCocoaErrorDomain` code 513 during write, then releasing the handle permits retry. The test verifies cached state and disk bytes remain unchanged during failure. Evidence: `validation/atomic-replacement-fault-tests.log`. This platform-specific test skips on Apple; equivalent Apple filesystem fault injection remains pending.

The one-process/one-repository-instance contract remains essential. Raw-byte checks detect sequential external modification but do not create an OS-level lock against a different process writing between the check and rename. If an external editor changes/deletes the library, restart Engram to reopen the authoritative file or enter recovery; a normal model refresh reads the existing repository instance.

Before release, measure on baseline iPhone/iPad/Mac hardware, including memory pressure, native scrolling and playback, imports and large histories. The 10,000-card/16-MiB case still takes roughly half a second per save here. A normalized transactional repository and separately stored immutable media are the documented route for substantially larger libraries; introducing those formats requires explicit migrations and the same failure/recovery contracts. This benchmark does not establish worst-case behavior, mobile frame performance, or support for the 250,000-note validation ceiling.
