# Equation entry: initial implementation

Status: the foundation compiled in the 269-test Mac package run, and iPhone fraction/matrix interaction tests passed with inspected captures. The latest native-caret extension and its three new tests remain unexecuted because SSH is timing out again. iPad interactions reached their functional assertions but actual landscape screenshot validation still fails. No phone installation is claimed.

## Scope and interaction

Existing typed-answer entry has a restrained **Equation** action. Its editor offers a mathematical preview, editable named slots, categorized notation controls and Previous/Next slot movement. iPhone stacks fields and palettes; wide iPad/Mac layouts place them side by side, falling back to a single column for accessibility text sizes. Controls use theme tokens, plain text and 44-point interaction areas rather than heavy boxed keys.

Notation includes fractions, powers, roots, brackets, inequalities, trigonometry, logarithms, derivatives, partial derivatives, definite/indefinite integrals, limits, sums/products, a 2×2 matrix, vectors, sets, piecewise forms and probability. Probability includes factorials, permutations/combinations, conditional probability and binomial/normal/Poisson distribution notation. A separate Greek palette supplies lower-case letters and commonly used capitals.

The tree editor supports nested templates and stable slot identities. Core insertion preserves text on both sides of a grapheme-based cursor offset. Input is bounded by slot/depth/text/source limits; rejected edits leave the document intact. Trusted template markers are never interpreted inside the learner's inserted values. Raw backslashes and special characters are escaped so fields cannot introduce arbitrary LaTeX commands. Preview uses the existing isolated rich-content renderer.

Insert produces inline portable LaTeX in the existing answer. It does not create a new question type, evaluate an expression, invoke a solver, reveal an answer or mark an attempt assisted. Existing manual/evidence-backed grading remains available; no new claim of mathematical-equivalence grading is made.

## Remaining work and limits

- UI uses named slots. Native TextSelection tracking is now connected on iOS 18+/macOS 15+: symbols and templates use the cursor or replace the selected text, preserving unselected text and one-step undo. Selections are tied to the exact source and reject stale or broken-grapheme ranges. Earlier OS versions retain end-of-slot insertion. This extension still needs compilation/runtime validation; direct cursor hit-testing in the visual formula and older-OS native selection remain outstanding. Do not claim a finished Symbolab-like editing experience. See [Apple TextSelection](https://developer.apple.com/documentation/swiftui/textselection).
- Matrix entry now selects 1–6 rows and columns; piecewise entry selects 1–6 cases. The Structure menu resizes the nearest existing matrix/cases ancestor, retaining entries by row/column and preserving nested expressions and field IDs. New cells are empty. Shrinking requires confirmation when it removes entered content or nested templates, and Undo restores the removed values and identities. Bounds checks reject invalid or oversized resizing without mutation. Structural removal preserves arguments, separating contents rather than merging numbers. Editor undo/redo retains up to 50 snapshots and clears redo after a new edit.
- Exercise keyboard navigation, nested templates, preview sizing, dark/light/mono contrast, accessible slot labels and long expressions on actual iPhone and landscape iPad.
- Capture before/after typed-answer and equation views; update current_ui only from verified renders, keeping one preceding image. The existing iPad screenshot surface/orientation problem remains unresolved.
- Optional Off/Basic/Scientific evaluative calculator settings and permitted-tool-use history remain separate work. This editor is notation input, not that calculator.
- All new numeric/ordering/multiple-select/debugging question formats still await explicit individual approval.

Ten foundation package tests passed in the Mac run, covering fraction output, Unicode cursor preservation and nested entry, all template slots, command/recipe-marker isolation plus oversized-edit rejection, undo/redo/removal, matrix/piecewise dimensions, coordinate-preserving resize, shrink consent with Undo restoration, nearest nested resizing and the overall slot limit. Three additional selection tests are written but unexecuted. iPhone fraction insertion/matrix resizing UI flows passed; screenshots are retained under current_ui/iphone. iPad tests remain failed on screenshot aspect, without weakening that assertion.

Update 4 October 2026: all three native selection regression tests passed in the isolated Mac package run (274 tests, one skipped, zero failures). Latest iPhone/iPad runtime validation remains pending because SSH became unreachable before the iOS build launched; existing captures predate this selection extension.
