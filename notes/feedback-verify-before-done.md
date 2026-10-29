---
name: feedback-verify-before-done
description: "Never call a sing_box task done/ready without checking the navigator's open items and real test results"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6e81f1f4-4e4f-462d-8363-f66a9f5d22e8
  modified: 2026-10-29T17:05:48.839Z
---

Before saying a task or platform is "done"/"готов", check the open/failing items in [[navigator]] and the actual test
results (e2e, device runs); state precisely what is verified and what is not.

**Why:** on 2026-10-29 I wrote "R5 на Android готов" although the navigator listed failing Android e2e tests (first
connection reset, outdated test); the user reacted with strong anger ("какой готов для android … всё было указано
тебе в навигаторе"). The user is also impatient during long runs: short progress lines ("идёт сборка, ~2 мин") avoid
"мы просто висим?" messages.

**How to apply:** read the navigator's "Open / unverified" section first; when reporting, separate "проверено" from
"не проверено"; during long builds/tests say what is running and roughly how long, and do useful work meanwhile.
