# Testing library

Status: local import and UI entry implemented; Mac compilation, UI traversal, captures and phone installation are pending because SSH to mac.modem timed out. The previous 246-test result does not validate this new stage.

## Content

Library's add menu now includes **Testing samples** on iPhone and iPad; the Mac Library add menu provides the same action. The compact import sheet names the active destination and contains three notebooks under Testing:

- AWS · Multiple choice: four original questions, including long prompt/options and responsibility/service distinctions.
- AWS · Short answer: six recall questions covering edge delivery, origins, EC2 security responsibility, monitoring and auditing.
- Maths · Text input: three existing text-answer cards for fractions, definite integral notation and binomial probability notation. These add no new question schema or solver. Equivalent notation requires manual/evidence-backed feedback when automatic equivalence is unsupported.

AWS references were inspected on 4 October 2026: [CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html), [shared responsibility](https://aws.amazon.com/compliance/shared-responsibility-model/), [CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html), and [CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html). They support each reference answer; these are practice questions, not official exam material.

Stable identities are scoped to the selected library. One repository transaction creates all missing samples. A repeat import does not overwrite notes, schedules, notebook edits or renamed decks, and does not resurrect deleted samples. Name collisions with unrelated notebooks fail the entire transaction and ask for a rename. No imported sample replaces the current study presentation. Normal repository synchronization applies after account connection; raw SQL seeding is not used.

Read-only inspection of the app's configured Supabase project `heedprsusmrwxasdixbt` returned zero registered auth users. Consequently, account import remains deferred. Do not write to an unrelated project or invent a placeholder user. Once the user authenticates, verify account ownership and use normal application/sync operations with the agreed initial-library upload choice.

## Manual exercise guide

Use the AWS short-answer deck to try these variants without changing the reference cards:

- Paraphrase: describe edge delivery in your own words.
- Partial response: name edge locations but omit the caching/delivery mechanism.
- Negation/misconception: claim AWS patches the customer's EC2 guest operating system.
- Self-correction: begin with that mistaken claim, then explicitly correct yourself.
- Irrelevant speech: include unrelated material after a valid answer.
- Provider failure: cancel during transcription, reopen and explicitly retry; verify no invented grade.
- Long content: use the long MCQ in portrait/landscape and larger text sizes.

Wrong/partial test responses are deliberately not embedded in the library's factual retrieval sources. Each MCQ retains its canonical correct option; randomized visible letters resolve through the existing MCQ renderer.

## Pending verification

Three package tests cover repeat import after edits/reviews, deleted content and separate-library identities, and atomic collision failure. Two UI flows capture Library before/after and test import/reimport on iPhone and landscape iPad. They are written but not executed. The iPad test also checks actual screenshot aspect ratio; the earlier simulator portrait-surface issue remains unresolved. Update current_ui only from accepted new screenshots, retaining one previous capture per view.
