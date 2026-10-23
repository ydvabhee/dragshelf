# DragShelf

Native macOS floating drag-and-drop shelf: drag something onto the shelf, switch to the
target app at your own pace, then drag it out of the shelf into that app.

## Agent workflow
`engineering-manager` → `product-architect` (PRD, architecture, tasks) → `mac-developer`
(one task) → `qa-engineer` (verify) → back to the manager.

Start a session with `claude --agent engineering-manager`.

Token rule: agent-to-agent reports use caveman full, docs use caveman lite, and code,
commits, and security notes are written normally.

## Git
- Remote: `origin` = `git@github.com:ydvabhee/dragshelf.git` (GitHub user `ydvabhee`). Auth uses the
  repo-local `core.sshCommand` with `~/.ssh/id_ed25519_ydvabhee`; don't change it or the global SSH config.
- "Ship a step" = commit only. **The user pushes**; never run `git push` yourself. Never force-push.
- Identity is set in the repo config (`Abhishek Yadav <yk.abhee@gmail.com>`). Never change it,
  and never use `--global`.
- Every agent commits its own changes at the end of each step. Conventional Commits, with the
  task id in the subject, e.g. `feat(T-03): accept file drops on shelf`.
- Commit messages follow open-source standard: short imperative subject (≤ 72 chars) with a
  proper type (`feat`, `fix`, `docs`, `test`, `chore`, `refactor`, `perf`), optional short body.
  **No `Co-Authored-By` trailers, no AI or Claude references of any kind** in messages,
  trailers, or author/committer fields.
- Stage specific paths, never `git add -A` blindly. Never rewrite history (no amend, rebase,
  reset --hard, or force) unless the user asks.
- Every commit leaves the build green. Commit WIP only to a `wip/<task-id>` branch.

## Versioning and releases
- The version lives in `VERSION` (SemVer). `scripts/build-app.sh` stamps it into `CFBundleShortVersionString`; the build number is the git commit count.
- Every user-visible `feat` or `fix` commit adds one line under `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog: Added, Changed, Fixed, Removed).
- Bumps: `fix` only → patch; any `feat` → minor; breaking change or first stable → major (1.0.0 = first notarized release).
- Release steps, only when the user asks:
  1. Move Unreleased to `## [X.Y.Z] - YYYY-MM-DD` and update the compare links.
  2. Bump `VERSION`.
  3. Commit `chore(release): vX.Y.Z` and tag `vX.Y.Z`.
  4. Run `scripts/make-dmg.sh`.
  5. Ask the user to push `main` and the tag.
  6. After the user pushes: `gh release create vX.Y.Z build/DragShelf.dmg --title "DragShelf X.Y.Z" --notes "<changelog section>"`. This needs `gh` signed in as **ydvabhee**.
- The asset name is always `DragShelf.dmg`, so the README link `releases/latest/download/DragShelf.dmg` keeps working.

## Source of truth
- `docs/PRD.md`: scope and acceptance criteria
- `docs/ARCHITECTURE.md`: stack and ADRs
- `docs/TASKS.md`: ordered tasks and their status
- `docs/QA.md`: test plan and manual drag/drop matrix
- `docs/STATUS.md`: milestone progress
