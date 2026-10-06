# Local fitting workflow

Fitting creates a scoped candidate/report, never an active model. Existing users start with recording disabled and optional models Off. Never fill missing historical mappings or assistance to make a dataset pass.

## Application APIs

1. Construct `StudyService` with `LearnerModelRepository` and current account provider. Explicitly enable recording, review stable content/Q versions and capture before answering.
2. Record measured duration/known assistance. Validated final grades use the existing boundary; corrections retain attempt ID.
3. Use `fitPersonalLearnerModel` for eligible BKT/DAS3H/Rasch history. `fitPermittedLearnerDataset` accepts data already permitted for this purpose; DINA needs supported forms and held-out learners.
4. Inspect fitting design, provenance, task validity, missingness and report. Numerical eligibility is not scientific approval. `reviewLearnerCalibration` records explicit review of an eligible candidate.
5. `switchLearnerModel` prepares compatible history before safe Observe/Active activation. Observe cannot influence ordering. Corrected fitting sources require fresh fit/review.

## Headless Windows fitting

```powershell
./scripts/Fit-LearnerModels.ps1 -InputPath ./permitted-dataset.json -OutputPath ./candidate.json
```

The output must not exist. The runner uses installed tooling/stable `.build`, removes known compiler outputs and performs no network processing. Input has ISO-8601 timestamps and this structure:

```json
{
  "permittedData": true,
  "model": "bkt",
  "account": "00000000-0000-0000-0000-000000000001",
  "library": "default",
  "targetLearner": "00000000-0000-0000-0000-000000000001",
  "evidenceRevision": 0,
  "training": [],
  "validation": []
}
```

Empty arrays fail intentionally. Each row contains `learnerID` and a valid `LearnerEvidence` object: latest accepted attempt revision, explicit unassisted status, binary correctness, reviewed mapping/content identity, actual timestamp and grading provenance. DINA also requires assessment form/session identity. Caller permission is explicit; the CLI does not anonymize data or grant consent.

Models: `das3h`, `bkt`, `dynamicRasch`, `dina`. Optional `options` uses the complete `LearnerFitOptions` schema. Defaults are optimizer/evaluation policies, not fitted coefficients. Default minima are 40 training and 20 validation attempts; counts alone do not establish adequacy. Chronological splits and model-specific support gates may reject larger datasets.

Candidates contain scoped parameters, exact local source revisions and reports with convergence/counts/manifest/split policy/log loss/baseline/Brier/calibration bins. `importLearnerCalibrationCandidate` imports without activation; scope/current-source checks, provenance review and safe switching remain required. Synthetic fits verify the pipeline, not applicability or learning superiority.
