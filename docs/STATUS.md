# DragShelf — Status & Handoff (paused 2026-10-20)

## ▶ Resume here (updated 2026-10-26)
1. `cd ~/Documents/Abhishek/MacApps/DragShelf && claude`, then say **"continue DragShelf from docs/STATUS.md"**.
2. `main`: all v1 (except T-12 signing) + v2 V2-01..V2-10 + Folders filter + **V3-01 shelf pet Mochi** (merged cc33e77, QA PASS 9ae6268). Docs synced (d769759); `docs/RELEASE-CHECKLIST.md` exists.
3. Next: **cut the release** (user decides number; suggested v0.2.0 with Mochi as headline): CHANGELOG `[Unreleased]` → `[0.2.0]`, VERSION, `chore(release): v0.2.0`, tag, `scripts/make-dmg.sh`; user pushes + uploads DMG to GitHub Releases (gh must be logged in as ydvabhee).
4. Later: more pets (Penguin, Baby dino, Bee + species picker), T-12 signing (Developer ID), promo feed URL, license; low follow-ups in TASKS.md.

## Build / run
- SwiftPM only (ADR-013; `xcodebuild` broken on this Mac until `sudo xcodebuild -runFirstLaunch`).
- `swift build` · `swift test` · `scripts/build-app.sh [release]` → `build/DragShelf.app` · `open build/DragShelf.app`.
- Dev and QA must also run the release build (an -O-only compiler crash was caught once).
- Agents: `.claude/agents/` (manager, architect, developer, qa). Loop: dev → QA → fix → QA PASS → manager marks DONE. One commit per step; the user pushes to `origin` (github.com/ydvabhee/dragshelf).

## v1 progress
| Milestone | Tasks | Tag |
|---|---|---|
| M0 Skeleton | T-01 | `m0-skeleton` |
| M1 Shelf | T-02..T-05 | `m1-shelf` |
| M2 Manage | T-06, T-07 | `m2-manage` |
| M3 Auto-show | T-08, T-09, T-13 | `m3-autoshow` |
| M4 Polish | T-10, T-11, T-14..T-20 | `m4-polish`, `m4-ui-polish` |
| M5 Ship | T-12 | BLOCKED on user |

- 125 unit tests, zero warnings (debug + release), idle 0% CPU / ~19 MB.
- Crash fixed 2026-10-23: file-promise drops (VS Code, Safari, Mail, Photos) trapped on a Swift 6 isolation check; same bug class fixed in image drawing handlers. QA now audits off-main callbacks every task.
- User-driven changes so far: top-center auto-show (T-08), responsive scroll + movable shelf + O(1) dedupe + no item limit (T-13), ⌘-drag move (T-15), remote promo line (T-14), UI polish + resizable shelf (T-16).

## T-16 (done at pause) — user report
"Outline appears when clicking the shelf; a stray outline on screen; scroll bar looks bad; want drag-to-resize (bottom/right edges)." Scroll bar should sit inset *inside* the rounded shelf. User couldn't screenshot (scroll bar auto-hides; tip: System Settings → Appearance → Show scroll bars: Always). After T-16: ask the user to re-check the look in light + dark.

## Open questions for the user (defaults already applied)
**Needed before release (T-12):**
- Apple Developer ID Application cert + notarytool credentials.
- OQ-26 promo feed URL + allowlisted domain (placeholder `example.com`).
- OQ-02 bundle id `com.abhishekyadav.DragShelf` OK? (cheap to change now, costly after release)
- OQ-06 app icon (none yet).

**v1 behavior (defaults chosen):** OQ-03 items cleared on quit · OQ-04 fixed ⌃⌥⌘D (no custom recorder) · OQ-07 auto-show on every content drag · OQ-10 macOS 14+ · OQ-13 text drags as text only · OQ-14 English only · OQ-15 fix Xcode with sudo? · OQ-27/28/29 promo footer + menu, on by default, no installed-app filtering.

**v2 (Shelf Actions backlog V2-01..V2-04):** OQ-17 rename shelf copy only · OQ-18 zip skips links/text · OQ-19..25 see `docs/OPEN_QUESTIONS.md`.

Answered by user: OQ-01 free · OQ-05 ⌘-drag moves · OQ-08 remove after drag out · OQ-09 top center · OQ-16 merge same image · OQ-30 no item limit.

## Manual QA owed (agents have no GUI)
`docs/QA.md` per task: real drags (Finder, Safari/Chrome, Mail, Photos, Slack), Liquid Glass look light/dark, VoiceOver, multi-display, notch, idle memory with 50 items, promo footer (copy `backend/promos.json` to `~/Library/Caches/com.abhishekyadav.DragShelf/Promos/feed.json`).

## Next after v1
v2 Shelf Actions: V2-01 Zip, V2-02 Share/AirDrop, V2-03 Convert/resize images, V2-04 Rename (specs in PRD/ARCHITECTURE/TASKS).
Other app ideas discussed: per-app volume mixer, presentation keystroke overlay, link router, downloads auto-cleaner, floating scratchpad, screen OCR.
