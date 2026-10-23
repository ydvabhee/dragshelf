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
- "Ship a step" = commit, then `git push` (main + tags). Never force-push; if a push is rejected,
  stop and report to the user.
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

## Source of truth
- `docs/PRD.md`: scope and acceptance criteria
- `docs/ARCHITECTURE.md`: stack and ADRs
- `docs/TASKS.md`: ordered tasks and their status
- `docs/QA.md`: test plan and manual drag/drop matrix
- `docs/STATUS.md`: milestone progress
