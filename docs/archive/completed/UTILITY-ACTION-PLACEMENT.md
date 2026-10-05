# Utility action placement

> Archived on 5 October 2026 from main `381c917`. This is historical context, not current implementation guidance. Outstanding work is tracked in [the backlog](../../BACKLOG.md); newer requirements take precedence.

- Root screen toolbar contains only Settings.
- Import/export is available in Library, including the desktop Library view.
- Screenshot all pages is the final Settings section, retaining loading/busy safeguards.
- Screenshot capture still opens its native review screen before capturing or saving anything.

Validation: the focused simulator route test passed in `/tmp/engram-utility-routes.xcresult`, checking removal of old toolbar controls, Library access, Settings footer reachability and screenshot review presentation. Screenshots were inspected and rotated in `current_ui`. The signed update installed and launched on the paired iPhone at 20:49 on 3 October 2026.
