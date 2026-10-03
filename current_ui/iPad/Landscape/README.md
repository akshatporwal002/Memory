# Landscape iPad UI reference

Landscape is the requested reference for iPad UI work; portrait is not a design target for this review.

Captured 4 October 2026 on iPad Pro 13-inch (M5), iOS 26.0.1 simulator, from the current dev app sources. Deterministic sample library and fixture AI responses; no live AI calls.

13 screens: Today, Library, Deck, Questions, Notes, Activity, Settings, MCQ initial/selected/feedback, and chat keyboard/response/expanded.

Both testIPadScreenCaptures and testIPadLandscapeReviewAndChatCaptures passed. These tests verify navigation and capture availability, not every visual or accessibility edge case. Rotation is restored after each test.

Each screen uses current.png and at most one previous.png on refresh.

The first workspace pass on akshat/ipad-support replaces the Library's wide list with a persistent file pane and selected deck detail. Deck study actions sit beside the taller chart; notes use a narrower reading column. Current captures reflect this pass, and previous.png retains the pre-change capture. The landscape geometry/navigation test passed. iPhone before/after evidence is in ../../iPad-Support-iPhone-Comparison (see its README); phone layouts are unchanged.
