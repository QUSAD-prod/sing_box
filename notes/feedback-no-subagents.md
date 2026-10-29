---
name: feedback-no-subagents
description: "User wants work done sequentially by the main agent, without spawning subagents, to save tokens"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 74d8003d-46eb-43d7-aed2-deade4eeec8f
  modified: 2026-10-27T17:04:19.226Z
---

Do not spawn subagents for the sing_box plugin work; take their tasks yourself and do them one after another.

**Why:** subagents burned through the usage limit twice (2026-10-27) and were cut off mid-task; the user asked to save tokens.

**How to apply:** work inline, commit after each finished piece (see [[sing-box-plugin-rewrite]]); prioritise studying flutter_vless pitfalls before writing native code.

The user also asked (2026-10-27) to keep the next chat cheap: before ending a session, commit everything and keep
`doc/HANDOFF.md` compact and current instead of long logs; in a new chat read only HANDOFF and the files a task needs.
