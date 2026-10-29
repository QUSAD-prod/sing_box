---
name: sing-box-plugin-rewrite
description: Rewrite of the sing_box Flutter plugin (version 1.0.0, sing-box/libbox 1.14.4) — branch, state, next steps
metadata:
  node_type: memory
  type: project
  originSessionId: 2d85b7d9-f4a5-4690-ad79-8e086b900161
  modified: 2026-10-28T15:56:23.817Z
---

Historical (1.0.0). Current work = 1.1.0 on branch `release-1.1.0`, see [[navigator]].

Full rewrite of the `sing_box` Flutter plugin onto sing-box v1.14.4 libbox, started 2026-10-27, in worktree
`.claude/worktrees/singbox-flutter-plugin-review-22aa2f`. Package version **1.0.0** (the user chose it over 1.1.0
since 0.0.1 was the last release); branch names must not contain "claude"; the user pushes
([[feedback-commits-and-push]]).
Talk to the user in Russian.
2026-10-28: the user merged `1.0.0` into `main` (PR #1); the main folder `/Users/qusadprod/projects/sing_box` is on
`main` (the user's VS Code). Session work goes on separate branches in the worktree (e.g. `fix-ci`: Node 24 actions +
fast libbox-release check job) so the user's folder is untouched; a branch can be checked out in one folder only.
The libbox release `libbox-v1.14.4` was published on 2026-10-28 at the user's request (assets verified with
`scripts/verify_libbox_release.sh`); never replace its assets.

Where things are (the repo docs replaced the old internal `doc/HANDOFF.md`, removed 2026-10-28 for the public release):
`CONTRIBUTING.md` (layout, tests, design rules, libbox facts), `doc/releasing.md` / `doc/releasing.ru.md` (release
instruction written for the user), `doc/platform_channel.md` (native contract), `doc/android.md`, `doc/ios.md`.
The old HANDOFF and the flutter_vless study are in git history: `git show 0742ae2:doc/HANDOFF.md`,
`git show 0742ae2:doc/agent_notes/flutter_vless_research.md`.

State (2026-10-28): all suites pass — 251 unit tests with `SING_BOX_BIN`, Android e2e 8/8 + 1/1, manual Android
lifecycle scenarios, iOS simulator smoke 5/5, APK/IPA builds; pana 150/160 only until `main` has the new pubspec.
Decisions by the user: license **GPL-3.0-or-later** (was MIT; native code adapted from SFA/SFI), keep the name
`sing_box` but ask the sing-box author for consent (naming clause) before publishing.

CI on main is fully green since 2026-10-28 (PR #2 `fix-ci` merged: Node 24 actions, `libbox release` check job).

2026-10-28: 1.0.0 is already on pub.dev (pana score was still pending). Competitor study (flutter_sing_box 3.0.3,
flutter_singbox_client 1.1.0) written to `competitor-analysis.ru.md` in worktree
`flutter-singbox-competitor-analysis-b4d5cd` (uncommitted); our main gaps: Flutter ≥3.44 minimum, no subscription
download by URL (`subscription-userinfo`), no Clash YAML, no proxy-only mode, no desktop.
Open / next (full plan in [[roadmap]]): iOS tunnel test on a real iPhone (needs the user's paid team); macOS/desktop or
proxy-only mode — undecided.

**Why:** the published 0.0.1 never compiled on Android and its iOS framework was only LFS pointers; the user wants a
working, fully featured plugin with pub.dev-level docs (previously used `flutter_vless`, which lacked features).

**How to apply:** commit after every finished piece (session limits interrupt work); no subagents
([[feedback-no-subagents]]); environment quirks in [[libbox-build-environment]].
