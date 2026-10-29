# Handoff notes for Claude sessions (branch `handoff` only)

This branch = `release-1.1.0` + the maintainer's working notes for AI sessions. It is **not** part of the
release: never merge `handoff` into `release-1.1.0` or `main`, and do not commit feature work here.

**Start by reading [`notes/navigator.md`](notes/navigator.md)** - the full state of the 1.1.0 work, rules,
technical facts, open/unverified items, the next task (R8) and how to test. Task plans: `notes/roadmap.md`.
Index of all notes: `notes/INDEX.md` (`[[name]]` links refer to `notes/<name>.md`).

Rules in short (details in the notes):
- Talk to the user in Russian; report precisely what is verified and what is not (`notes/feedback-verify-before-done.md`).
- Do the work inline, no subagents. Commit after every finished piece with the user's git identity and **no
  Co-Authored-By trailer**.
- Feature work goes to branch **`release-1.1.0`** (one release branch, no branch per task). In a cloud session
  create the working branch from `release-1.1.0` (not from `handoff`) unless the user says otherwise.
- Pushing: the user pushes; push only when the user explicitly asks in the chat.
- Dart must stay compatible with Dart 3.7 / Flutter 3.29.

Cloud environment caveats (see also navigator section 6 "Cloud session"): the notes describe the maintainer's Mac (Flutter at `~/dev/flutter`, Android emulator,
iOS simulator, a locally built sing-box CLI under `/private/tmp/...`, local libbox copies). None of that exists in a
cloud container: install Flutter stable yourself, build the sing-box 1.14.4 CLI per `CONTRIBUTING.md` for
`SING_BOX_BIN` config tests, and use CI (`.github/workflows/ci.yml`, `gh workflow run ci.yml --ref <branch>`) for
Android/iOS builds. libbox is downloaded from the `libbox-v1.14.4` GitHub release by Gradle / SwiftPM.
