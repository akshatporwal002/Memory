# Product requirements and user notes — 2 October 2026

Status: recorded for planning. This document does not authorize or claim implementation of the features below. Requirements reflect the user's feedback on the installed app; architecture suggestions and unresolved decisions are labelled separately.

## 1. Design direction to preserve

The user loves the current screen shown after opening a deck: it is close to the original vision for the project. Use that screen as the visual reference for other screens, especially Library.

The overall design now looks “exactly how I envisioned it.” Preserve its cohesive, premium, minimalist character while making the specific adjustments below. Minimalism means clear hierarchy and consistent components, not removing useful functionality.

## 2. Bottom navigation

- Move the navigation bar lower, to the position normally expected for an iPhone bottom navigation bar.
- Reduce icon, label or internal component sizes if necessary to achieve the intended placement.
- Keep the existing glass visual language and visual relationship with the AI entry point.

Acceptance: the bar feels naturally anchored near the bottom, respects the device safe area, and does not look unnecessarily raised or oversized.

## 3. Library

- Redesign Library using the same visual language as the successful deck detail screen.
- Replace the current Gallery presentation, which the user dislikes.
- Carry over the deck screen's restrained surfaces, typography, spacing and hierarchy so Library feels like part of the same app.

Decision still needed: the replacement arrangement of decks, such as a clean list or another minimal layout. The user has requested consistency, not selected a specific replacement layout.

## 4. Activity

- Place Day / Week / Month / All immediately below the graph.
- Use a bar chart as the graph presentation.
- Remove the line-chart option; the user significantly prefers bars.

Acceptance: changing the time range is available directly below the chart, and there is no line-versus-bar toggle.

## 5. Shared notes and account sign-in

Desired capability: users signing in with Google or Apple can access shared notes and collaborate with other people.

Correction confirmed by the user and repository inspection: Supabase is not integrated in Engram. The app currently uses a local file repository. Supabase accounts, synchronization and shared-content permissions are new work, not an extension of an existing integration.

Planning must resolve:

- How users invite people or share a note, notebook or deck.
- Who can view or edit shared content, and how access is revoked.
- Whether collaborators see updates immediately and how conflicting edits are handled.
- How offline edits synchronize and how authorship/history are shown.
- How Google/Apple app identity relates to the separate ChatGPT connection.

Google or Apple sign-in is the intended account entry point; sign-in alone does not define which notes are shared or with whom.

## 6. AI assistant that can act on the learning system

The assistant should be able to perform the actions a human can perform within the app, rather than only returning conversational text. Editing notes is an explicit example.

The assistant must identify which actions a request needs, execute them through the app's capabilities, and reflect the result in the actual learning content. Its scope should extend across the learning system rather than one isolated screen.

Examples to consider during planning: create/edit notes, create or improve questions, organize decks, inspect source material and learning progress, and assist with study workflows. These examples expand the planning scope; they are not a finalized tool inventory.

Architecture ideas raised by the user:

- Model tool calling with structured app actions.
- An MCP-like interface exposing available capabilities.
- Delegation to specialized agents when useful.

These are alternatives to evaluate, not a requirement to adopt MCP or a multi-agent architecture. The intended outcome is broad, useful action capability with minimal friction.

Implementation planning must distinguish read actions, content mutations and scheduling/account/sharing actions; define visible results, failure recovery and undo; and respect the user's access to shared content. It must also decide how to handle ambiguous requests and destructive changes without adding unnecessary approval steps to routine work.

## 7. Model selection inside chat

- Let the user choose an available model from inside the chat interface.
- Make the selected model visible and easy to change without leaving the conversation.
- Populate choices from models available to the connected account/provider.

Decision still needed: whether selection is per conversation or remembered as a default, and how switching models affects conversation context and pending actions.

## 8. Rich rendering in chat and notes

Current problem: AI responses display raw formatting syntax such as `**` and `#`.

- Render Markdown properly in assistant messages: headings, emphasis, lists, links, code and other supported structures.
- Apply the same rich-content support to notes so generated learning material reads naturally.
- Support LaTeX mathematical notation and Mermaid diagrams.
- Keep rendering consistent with the app's typography, colors and spacing.

Acceptance: valid supported syntax becomes readable formatted content; equations and diagrams appear as their intended visuals. Define readable fallback behavior for malformed or unsupported content and how users edit the underlying content.

## 9. ChatGPT connection component

- Improve the Sign in with ChatGPT component so it feels like a polished, premium OAuth connection flow.
- Give it clear hierarchy, restrained styling and consistency with the rest of the app.

Planning should cover disconnected, connecting, connected, expired and failed states, including clear account/model availability and recovery. Exact provider branding and supported authentication behavior need verification during implementation.

## 10. Typed answers and AI grading

Add typed answers as another study input alongside thinking privately and answering by voice. The learner can enter an answer, submit it, and have ChatGPT review and grade it.

The requested feedback sequence:

1. Show the learner's submitted response.
2. Animate supported/correct text turning green.
3. Strike out incorrect or irrelevant text.
4. Animate missing information being typed into the response in red/orange, so the learner can add it.
5. Allow the learner to discuss or challenge the feedback with the assistant.
6. Refine the response through that conversation and store the agreed improvement in memory.

Feedback must distinguish correct, incorrect, irrelevant and missing content rather than treating the entire answer as one undifferentiated mark. Colors, strikes and additions should explain the assessment clearly; the original answer should remain identifiable.

Planning questions:

- Which question types accept typed answers, and how does assessment map to existing scheduling grades?
- Which source material or rubric supports the grading and proposed additions?
- How does partial credit work, and what happens when the assessment is uncertain or disputed?
- Where are corrections added: an annotated answer, an editable revised answer, or both?
- What exactly does “stored in memory” mean: the learner's response history, the card's accepted answer, notebook content, persistent assistant context, or some combination?
- When a disputed answer is revised, does its grade/schedule also change?
- How are annotations and typing animation presented accessibly and with Reduce Motion enabled?

The user wants conversational correction and persistence. Do not silently equate that with overwriting a canonical card answer or changing a review grade; the storage and scheduling behavior remains to be decided.

## 11. Suggested planning order

1. Navigation placement, Library consistency and Activity chart controls.
2. Shared rich-content rendering and the premium ChatGPT connection component.
3. In-chat model selection and a structured action interface for the assistant.
4. Typed-answer grading, annotated feedback, conversational revision and defined memory persistence.
5. Verify Supabase/account integration and design shared-content permissions and synchronization.

This order is a planning recommendation, not a priority ranking supplied by the user. Preserve the successful deck design throughout.
