# Landscape iPad UI reference

Landscape is the requested reference for iPad UI work; portrait is not a design target for this review.

Captured 4 October 2026 on iPad Pro 13-inch (M5), iOS 26.0.1 simulator, from the current dev app sources. Deterministic sample library and fixture AI responses; no live AI calls.

13 screens: Today, Library, Deck, Questions, Notes, Activity, Settings, MCQ initial/selected/feedback, and chat keyboard/response/expanded.

Both testIPadScreenCaptures and testIPadLandscapeReviewAndChatCaptures passed. These tests verify navigation and capture availability, not every visual or accessibility edge case. Rotation is restored after each test.

Each screen uses current.png and at most one previous.png on refresh.
