---
name: feedback-one-release-branch
description: "sing_box roadmap tasks go into the current release branch (release-1.1.0), not a new branch per task"
metadata:
  node_type: memory
  type: feedback
  originSessionId: d9c180bf-96e1-4c7b-aa7c-6cb3a0e68d03
  modified: 2026-10-29T10:08:50.574Z
---

Do roadmap tasks (R4 and on) in the existing release branch `release-1.1.0`; do not create a new branch per task.
Everything lands in the next update (1.1.0).

**Why:** on 2026-10-29 I created branch `routing` for R4 and the user objected sharply: "в той же ветке делай, не в
новой, это всё в обнове будет".

**How to apply:** before starting a task, `git switch release-1.1.0` (the worktree may sit on an app-made `claude/...`
branch); commit there per finished piece; the version stays 1.1.0 and its CHANGELOG section grows. Overrides the
"one task per branch" rule in [[roadmap]]. See [[navigator]].
