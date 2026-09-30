# Notebook workflow

The notebook is now an editable page, rather than a read-only copy of deck creation text.

## Writing and editing

- New deck from Today or Library opens the same full-page document composer on iPhone, iPad, and Mac.
- Write prose and headings normally. Prefer `question: answer` (colon plus space). Existing `question → answer` and `question -> answer` lines still work. Incomplete lines are reported before creation. URLs, times, and `AWS::Compute` folder paths are not colon separators; use a leading backslash to keep an ordinary colon-space sentence as prose.
- Creating the deck opens its notebook directly. Use **Open notebook** inside an existing deck, or the phone gallery’s deck menu.
- Saved notebooks contain writing and linked question/answer blocks. Each block can be edited, moved, removed, or followed by another block through its menu.
- A writing block’s **Create cards from Q&A lines** action converts colon or arrow lines into questions while retaining the surrounding prose.
- Editing a supported card from a document-backed deck opens its notebook at that question. The notebook resolves current card content rather than showing the original creation copy.

## Saving

Unfinished notebook drafts are retained on this device when leaving the page and after restarting. **Save** commits the notebook and cards together. Draft retention does not change study cards until Save succeeds.

Existing linked cards keep their IDs, schedules, tags, and history when their wording or block order changes. Added questions receive new cards. Saving removed questions requires confirmation and retires their cards while retaining historical records.

Individual card edits, moves, and deletions also refresh stored notebook text. Legacy creation documents resolve their original generated note IDs, so changed wording does not break links and deleted cards are not recreated from the original copy.

If the notebook changed elsewhere while a draft was open, saving stops instead of overwriting it. Unrelated library changes can proceed when the original notebook content still matches. **Notebook options → Reload saved notebook** explicitly discards the local draft and loads the latest saved version.

## Navigation

Deck creation, notebook editing, ordinary card editing, Settings, and Review are navigation pages in the main app. Existing standalone views used by previews/captures retain their own navigation containers. Short rename and destructive-confirmation dialogs remain dialogs. Import/export remains a separate task.

The creation page has no keyboard Done button or fixed draft footer. Bottom tabs hide while writing. Folder selection, writing help, and draft actions live in Notebook options; the main page shows a title, a short syntax hint, and the writing area. Card count appears only when questions exist.

## AWS practice notebook

From an empty New notebook page, choose **Notebook options → Load AWS sample**, then **Create**. This loads 24 original practice prompts and explanatory prose based on the user-supplied AWS Certified Cloud Practitioner Slides v44. The source page references are included in the notebook. Loading is disabled when a draft already contains writing, so the sample cannot replace an unfinished notebook accidentally.

The same content is available as `Sources/Features/Resources/AWS-Cloud-Practitioner-Sample.txt` for copying into another device. Libraries remain local to each installation.

## Current boundaries

The notebook supports basic plain-text questions, including multiline fields in saved blocks. Cloze, formatted, and media notes remain in the card interface and are preserved; they are not flattened into the notebook. This is a native block editor, not yet a rich-text word processor with inline formatting, attachments, or slash commands. Question/answer card changes use an explicit Save; unfinished writing is saved separately as a draft.

## Verification — 7 September 2026

- Swift suite after the colon-format cleanup: 95 tests executed, one skipped, zero failures.
- iOS Simulator build: passed, including iPhone/iPad target compilation.
- macOS app build: passed.
- Native Mac inspection: New deck opens full-page; Back returns to Today; an existing deck opens the notebook page; sidebar navigation returns to Today. No real card content was changed during UI inspection.
- Cleanup verification: both Apple builds passed; the simplified creation screen and bundled sample loader were inspected on Mac. The user-requested **AWS Cloud Practitioner · Practice** notebook was created in the Mac library and reopened with 24 linked questions. Existing decks were not edited.
- New tests cover legacy/current content reconciliation, card identity/schedule preservation, block reordering/addition/removal, incomplete conversion, atomic failure, stale writes, unrelated revisions, backup round trips, cross-deck protection, editor routing, and draft persistence.
- iPhone/iPad runtime, large text, VoiceOver, populated notebook layout, and full keyboard editing remain to be verified. Simulator computer-use access timed out.
