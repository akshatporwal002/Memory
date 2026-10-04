# Equation entry: initial implementation

Status: source implemented, Mac compilation and visual validation pending. SSH connectivity timed out; Swift is unavailable in this Windows shell. The previous 246-test pass predates this stage. No phone installation or screenshot update was performed.

## Scope and interaction

Existing typed-answer entry has a restrained **Equation** action. Its editor offers a mathematical preview, editable named slots, categorized notation controls and Previous/Next slot movement. iPhone stacks fields and palettes; wide iPad/Mac layouts place them side by side, falling back to a single column for accessibility text sizes. Controls use theme tokens, plain text and 44-point interaction areas rather than heavy boxed keys.

Notation includes fractions, powers, roots, brackets, inequalities, trigonometry, logarithms, derivatives, partial derivatives, definite/indefinite integrals, limits, sums/products, a 2×2 matrix, vectors, sets, piecewise forms and probability. Probability includes factorials, permutations/combinations, conditional probability and binomial/normal/Poisson distribution notation. A separate Greek palette supplies lower-case letters and commonly used capitals.

The tree editor supports nested templates and stable slot identities. Core insertion preserves text on both sides of a grapheme-based cursor offset. Input is bounded by slot/depth/text/source limits; rejected edits leave the document intact. Trusted template markers are never interpreted inside the learner's inserted values. Raw backslashes and special characters are escaped so fields cannot introduce arbitrary LaTeX commands. Preview uses the existing isolated rich-content renderer.

Insert produces inline portable LaTeX in the existing answer. It does not create a new question type, evaluate an expression, invoke a solver, reveal an answer or mark an attempt assisted. Existing manual/evidence-backed grading remains available; no new claim of mathematical-equivalence grading is made.

## Remaining work and limits

- Initial UI uses named slots and inserts templates at the end of the selected slot. Core offsets exist, but native text caret/selection tracking and direct cursor hit-testing in the visual formula are not yet integrated. Do not claim a finished Symbolab-like editing experience.
- The current matrix is fixed at 2×2 and piecewise form has two cases. Variable-size structural editing, removing a template while retaining its content, and editor-level undo/redo remain to implement.
- Exercise keyboard navigation, nested templates, preview sizing, dark/light/mono contrast, accessible slot labels and long expressions on actual iPhone and landscape iPad.
- Capture before/after typed-answer and equation views; update current_ui only from verified renders, keeping one preceding image. The existing iPad screenshot surface/orientation problem remains unresolved.
- Optional Off/Basic/Scientific evaluative calculator settings and permitted-tool-use history remain separate work. This editor is notation input, not that calculator.
- All new numeric/ordering/multiple-select/debugging question formats still await explicit individual approval.

Four package tests cover fraction output, Unicode cursor preservation and nested entry, all template slots, and command/recipe-marker isolation plus oversized-edit rejection. iPhone and landscape iPad UI tests exercise fraction insertion into an existing answer and capture before/after. These tests are written but unexecuted.
