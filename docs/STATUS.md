# DragShelf — Status (2026-10-20)

## v1: feature-complete, ship blocked on user (T-12)
| Milestone | Tasks | Tag |
|---|---|---|
| M0 Skeleton | T-01 | `m0-skeleton` |
| M1 Shelf | T-02..T-05 | `m1-shelf` |
| M2 Manage | T-06, T-07 | `m2-manage` |
| M3 Auto-show | T-08, T-09, T-13 | `m3-autoshow` |
| M4 Polish | T-10, T-11, T-14, T-15 | `m4-polish` |
| M5 Ship | T-12 | BLOCKED |

- 54 unit tests; debug + release builds clean, zero warnings. Idle: 0% CPU, ~19 MB footprint.
- User-driven changes: top-center auto-show (T-08), responsive scroll + movable shelf + O(1) dedupe, no item limit (T-13), ⌘-drag move (T-15), remote promo line (T-14).
- Notable catches: release-only compiler crash (fixed, release build now required in dev/QA), Quick Look out-of-range crash, ⌘-drag rejected by copy-only apps, stuck empty shelf after failed promise.

## Blocked on user (T-12 ship)
- Apple Developer ID Application cert + notarytool credentials.
- OQ-26: promo feed URL + allowlisted host (placeholder `example.com`).

## Manual QA still owed (agents have no GUI)
- `docs/QA.md` manual steps per task: real drags (Finder, Safari/Chrome, Mail, Photos, Slack), Liquid Glass look light/dark, VoiceOver, multi-display, notch, idle memory with 50 items.

## Next
- v2 backlog (M6): V2-01 Zip, V2-02 Share/AirDrop, V2-03 Convert/resize images, V2-04 Rename.
