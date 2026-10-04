# Overnight decisions — 5 October 2026

This document supersedes older approval statuses, not the original requirements.

## Approved question types

| ID | Type | Scope |
| --- | --- | --- |
| Q1 | Rearrange order | Reorder stable, shuffled steps |
| Q2 | Multiple-select | Select all applicable choices |
| Q3 | Matching | Pair items with descriptions |
| Q4 | Classification | Assign items to categories |
| Q5 | Multiple blanks | Answer independently identified blanks |
| Q6 | Numeric answer | Numbers, fractions and declared tolerances |
| Q7 | Number with units | Value and unit, with explicit conversion rules |
| Q8 | Equation answer | Full mathematical input keyboard; no CAS solver |
| Q9 | Spot errors | Identify faulty code, grammar or other passages |
| Q10 | Correct errors | Edit faulty code or sentences |

Q11 image occlusion, Q12 diagram labeling and all remaining catalogue types stay deferred. Approval is not a claim that these ten types are already implemented. Implement and validate them in separate stages, preserving existing study layouts and scheduling semantics.

## Tutor pilot

- Begin implementation; pilot includes all ages.
- Tutors see assigned-work progress and explicitly shared misconception summaries only.
- Never expose exact answers, audio, private conversations, unrelated learning memory or source PDFs.
- Retain the provisional A$3/month, five-active-student planning target; no live charge or entitlement yet.
- For learners requiring guardian consent, keep hosted sharing disabled until the consent and verification workflow is configured. Do not infer consent from age/profile text.
- Start with permission contracts, versioned assignment snapshots and deterministic progress. AI reports remain disabled until their budget is agreed.

## Credentials, cloud and purchases

- User is enrolled in Apple's paid developer program. Verify Engram in App Store Connect, then configure sandbox products. No production purchase.
- The user created the separate Engram project `engram-510613`, and its API dashboard was verified in Chrome. LearnLens (`learnlens-508804`) is explicitly excluded: do not configure or use it. Do not activate paid APIs or test calls. Available Google trial credits have not yet been verified.
- Open the OpenAI API-key page in Chrome for the user to create/store their own secret. Never put secrets in chat, Git, logs or screenshots.
- Pay first, then use credits. No automatic top-ups. Paid API testing stays disabled until explicitly funded and bounded.
- OpenAI prepaid cutoff can be delayed, so prepaid balance is not an absolute no-overrun guarantee. Do not claim otherwise.
- Keep managed credits, personal provider keys and ChatGPT plan usage distinct. Keep sandbox and production ledgers separate.

## Delivery and outstanding setup

Preserve minimalist phone layouts and design a separate landscape arrangement for iPad/Mac. Validate permissions and scheduling before hosted activation. App Store Connect login and GCP billing selection remain user setup steps. Record actual product IDs and project ID only after verification, not as guessed deployed values.

If a PC stay-awake helper is needed, the user authorizes it. Track its process and stop that exact helper before finishing; do not kill a recycled PID or change system sleep settings permanently.
