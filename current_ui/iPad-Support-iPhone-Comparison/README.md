# iPhone layout regression evidence

Paired before.png / after.png captures for the iPad support branch, on iPhone 17 Pro (iOS 26.0.1 simulator), 4 October 2026. The baseline was captured before UI source edits; final after captures were generated from the isolated iPad branch after the last refinement.

The native Today → Library → Deck → exam settings → Questions → Notes workflow passed both before and after. It also verifies the compact contents rail interaction and return to deck details.

Pixel comparison excluding the status-bar region found identical app content for Today, Library, Questions, initial Notes, and scrolled Notes. Deck differences were confined to date/forecast content; exam-settings differences were confined to the live chart/date region visible behind its sheet. The notes rail jump differed in the transient contents overlay, without a change to the reading column.

No iPhone layout changes were requested or implemented. Workspace mode is explicitly excluded for the phone idiom, including landscape. This evidence covers the captured 17 Pro workflow; it does not certify every phone size or accessibility setting.
