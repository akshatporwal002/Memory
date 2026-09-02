# Source-grounded tutor foundation

This branch introduces a provider-neutral tutor contract. It does not include a provider SDK, a chatbot screen, a model key, a network request, or a way for an answer to change scheduling, cards, grades, or mastery.

`TutorQuestion` carries source excerpts with a stable resource ID, title, locator, and optional version. A provider returns only a draft answer and source IDs. `GroundedTutor` accepts an answer only when it includes at least one reference to an input source; it replaces the IDs with the original inspectable source records. Missing evidence, invented citations, empty drafts, and provider failures remain explicit outcomes instead of a guessed answer.

## Composition direction

The application composition root should select a `TutorProvider` only after a privacy policy and explicit user choice determine whether a local or cloud provider is allowed. The provider should receive the minimum user-selected excerpts. Credentials belong in a platform secret store, never a library export or note. A future SwiftUI chat feature should render source title and locator alongside each answer and leave all review actions in the normal study workflow.

Grounded sources lower hallucination risk; they do not prove an answer correct. The tutor should state uncertainty when sources conflict or do not answer the question.
