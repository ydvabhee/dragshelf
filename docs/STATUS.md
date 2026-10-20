# DragShelf — Status

## M0 Skeleton — DONE (tag `m0-skeleton`)
- T-01 menu bar app, SwiftPM build (ADR-013: xcodebuild broken on this Mac).

## M1 Shelf — DONE (tag `m1-shelf`)
- T-02 model + cache. T-03 floating Liquid Glass panel. T-04 drop in: files, folders, links, text, images. T-05 drop in: file promises (Mail, Photos, browsers).
- 18 unit tests. Real drags not run (no GUI access for agents) → manual checks in `docs/QA.md` T-03..T-05.

## Next
- M2: T-06 drag out, T-07 manage items (+ carried: Esc hide, promise-after-Clear race).
- M3: T-08 auto-show on drag, T-09 hotkey. M4: T-10 settings, T-11 a11y polish.
- M5: T-12 BLOCKED on Developer ID.

## Risks
- Drag delivery into the non-activating panel verified only by code review + fake-NSDraggingInfo test.
- Glass/vibrancy look not verifiable offscreen; user must eyeball light/dark.
