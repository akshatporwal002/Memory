# iPad landscape support — implementation and safeguards

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

Branch: akshat/ipad-support. Preserve the iPhone layout unless explicitly requested by the user.

## First delivery

- Enable the workspace only for non-phone windows at least 1,100 points wide. iPhone stays on its existing composition, even in landscape.
- Keep primary navigation in the collapsible app sidebar; remove the redundant deck list from that sidebar.
- On wide iPad windows, retain the Library file hierarchy in a 280-point pane beside the selected deck. Folder creation, file/photo imports, drag/drop, search and context actions use their existing operations.
- Use a larger, 260-point retention chart, with study, Questions, Notes and source actions alongside it.
- Keep notes in a 620-point reading column on workspace windows; preserve their 760-point cap and existing phone margins elsewhere.
- Narrow windows and accessibility text fall back to stacked deck actions.

## Verification and evidence

iPhone baseline: native testDeckQuestionsAndNotesNavigation passed before source edits. Paired screenshots are under current_ui/iPad-Support-iPhone-Comparison, with one before.png and after.png per captured view.

Landscape iPad snapshots: current_ui/iPad/Landscape contains current.png and previous.png. Tests use the deterministic sample library and fixture AI responses, not live requests.

The Mac validation source was isolated under ~/Documents/projects/Memory-ipad-support after concurrent feedback/account work began changing the shared source tree. Only this branch's six source files and capture tests were transferred into that checkout. Concurrent local work must not be staged into this delivery.

## Following passes

- Today: compact study hero and contextual upcoming reviews.
- Assistant: width-aware companion panel and keyboard behavior.
- Documents: retain library hierarchy while reading, with optional citations.
- Activity/settings: better landscape composition and Mac-specific navigation.
- Validate 11-inch iPad, narrower windows, Dynamic Type, themes and keyboard/selection preservation before expanding the pilot.

Every subsequent screen change requires its own iPhone before/after captures and a landscape tablet capture. A successful build alone is insufficient evidence of visual compatibility.

Final first-pass validation: isolated landscape iPad navigation/geometry test passed; final iPhone baseline workflow passed with eight before/after pairs saved. The Mac target also compiled. The assistant, Today content composition, Activity content composition and Settings content composition are reserved for later passes; the sidebar update is shared by their wide-window shell.
