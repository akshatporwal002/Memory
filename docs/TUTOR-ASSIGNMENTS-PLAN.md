# Tutor assignments and evidence-based insights

Status: specification only. No tutor subscription, permissions or student data access has been activated. A complete tutor platform is outside the initial implementation; this document defines its future boundaries.

## Product and price

The agreed planning target is A$3 per tutor per month total, with five active students. Student study remains available without buying the tutor tier. This is a provisional price, not an App Store product or a verified commercial margin. Use the actual localized StoreKit price after product configuration and validate proceeds, hosting and AI cost before activation.

One tutor account has one plan and up to five accepted active memberships. Pending invitations have a separate bounded limit; they do not silently consume a paid student slot. Accepting an invitation reserves capacity transactionally, so simultaneous acceptance cannot exceed five. Paid status is verified server-side; client settings cannot grant capacity. No tutor feature grants unlimited voice usage or unlimited AI analysis.

## Assignment workflow

1. Tutor creates a workspace and invites a student through an expiring, single-use, revocable link. The link opens a preview naming the tutor and requested access. The student accepts after authenticating; eligible minors follow the configured guardian workflow before progress sharing starts.
2. Tutor chooses a deck, due date and instructions. An assignment publishes a versioned copy/snapshot of the assigned content, with source attribution and rights preserved. It never automatically exposes the tutor's entire library or full private source PDFs.
3. Student adds the assignment to their learning workspace and reviews using their own schedules/settings. Personal attempts remain private; only the explicit assigned-work progress projection is shared.
4. Tutor sees assigned completion, last activity, due/overdue work and evidence-supported topic difficulties. Changes to assigned content create a new assignment revision; student progress is not silently reset.
5. Student/tutor can inspect which assignment evidence contributed to an insight. Tutor can dismiss an incorrect suggestion or record a pedagogical note. AI does not message students or change grades/assignments automatically.

Assignments need draft, published, active, completed, withdrawn and archived states. Define per-student acknowledgement and submission state separately. Withdrawal removes future assigned access without deleting a learner's unrelated library. New content revisions apply between questions; stale presentations do not receive automatic grades.

## Data and authorization

Keep these server entities distinct from personal libraries:

| Entity | Purpose and access |
| --- | --- |
| Tutor workspace | Owner, plan status and capacity; owner manages it |
| Invitation | Hashed token, expiry and role; only targeted acceptance and owner revocation |
| Student membership | Accepted consent scope and status; visible to its student and workspace owner |
| Assignment/revision | Published content and instructions; tutor and assigned accepted students |
| Assignment progress | Minimal student-specific projection; that student and the assigning tutor |
| Insight run/flag | Versioned evidence references and generated suggestions; authorized tutor, with an explanation of student data used |
| Access audit | Invitations, acceptance, withdrawal and permission changes; protected administrative records |

RLS and server operations must require the exact workspace membership and assignment relationship. Tutor role alone never gives access to all students. Personal conversations, unrelated review history, private learning memory, personal files, original PDFs and other tutors' assignments remain inaccessible. Retrieval uses only authorized assignment evidence at execution time. AI tools run under the same permissions as human actions.

Progress projections can include assignment question IDs, reviewed counts, outcome categories, timestamps and relevant accepted misconception summaries. Exact free-text answers or audio are not included by default. If a later feature needs answer sharing, obtain explicit scoped consent and explain its retention first. Never share raw recordings.

## Insights and bounded costs

Start with one weekly workspace report covering at most five active students, using changed assignment evidence only. Permit a bounded manual refresh from the same allowance, not unlimited extra generations. Cache by assignment/content/evidence versions. Enforce allowance and per-run token/evidence limits on the backend; a client preference cannot bypass them.

Before launch, choose a capped monthly provider-spend budget below the verified net subscription proceeds after hosting/support allocation. When allowance or quota is reached, retain deterministic progress views and show the next report date. Do not silently increase cost, switch provider or bill a student. Tutor insights are a separate entitlement from voice credits/subscriptions.

Potential flags include repeated difficulty on the same assigned concept, lack of practice approaching a deadline, and contradictory answers suggesting a misconception. Each flag cites assigned evidence, its timeframe and its uncertainty. Missing activity means insufficient evidence, not a claim that a student is incapable. Reports are pedagogical suggestions, not diagnoses, and never infer protected personal characteristics.

## Removal, expiry and consent

- A student may revoke sharing or leave a workspace. Revoke membership and pending invites transactionally; stop retrieval, future writes and AI runs under the revoked scope. Clear cached shared progress on reconnect.
- Removing a student frees capacity; it does not erase their personal study library. Retain only the agreed administrative/audit minimum. Determine deletion and archive retention before launch.
- Subscription expiry pauses new invitations, assignments and AI insights. Students retain their own content/progress. Define a clearly disclosed grace/read-only period rather than silently deleting learning data.
- Failed/pending purchase, renewal, refund and revocation use verified backend entitlement state. Workspace access cannot be restored by importing an old backup.
- Decide permitted ages, applicable consent requirements, guardian verification and exact retention periods before hosting student data. Until configured, keep invitations disabled for accounts needing guardian consent; do not infer age or guardian authorization from profile text.
- Exported or downloaded copies cannot be remotely recalled. Explain that at sharing/revocation rather than promising impossible deletion.

## iPhone and iPad layouts

iPhone: a compact tutor workspace list, student rows, assignment list and detail screens. Put assignment creation and invitation actions in the existing add menu; avoid dashboard card grids and oversized buttons. Use a text-led progress summary, restrained bars and expandable evidence.

iPad landscape/Mac: sidebar for workspace/students/assignments; a middle assignment/student list; one detail pane for progress or evidence. Preserve the phone layout and study UI. Keep the contextual assistant beside existing navigation, scoped to the selected workspace/student/assignment. Bulk selections and keyboard navigation may be added without making phone controls denser.

## Acceptance before activation

Test owner/student/outsider access, a student in two tutor workspaces, revoked membership while offline, expired/simultaneously accepted invitations, the five-student capacity race, content revisions during review, plan expiry/refund, report caching and AI allowance exhaustion. Confirm no personal chat/memory/source-PDF leakage through database queries, exports, retrieval or tool calls. Review accessibility, compact phone controls and landscape panes using current screenshots. Validate actual cost and consent configuration before enabling the hosted pilot.

Open release decisions: App Store product/pricing, final AI spending cap, grace/retention periods, age/guardian requirements and the exact student-facing consent wording. These do not block the current local app work.
