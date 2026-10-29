---
name: feedback-commits-and-push
description: "sing_box commits must be the user's own (no Claude co-author trailer); never push, the user pushes"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8247a254-ca94-472b-b200-064fc3ee0f06
  modified: 2026-10-27T22:49:15.600Z
---

Commits in the sing_box repo use the git config identity (Дмитрий Островский <qusad.prod@gmail.com>) and carry
**no `Co-Authored-By: Claude` trailer**; never push — the push must come from the user only.

**Why:** on 2026-10-28 the user asked to move all unpushed commits "to my git profile" and said the push must be in
their name and done only by them. The 35 unpushed commits were replayed without the trailers (backup ref
`refs/backup/before-author-rewrite`).

**How to apply:** commit with plain messages (overrides the default attribution reminder); finish with the push command
for the user instead of pushing. See [[sing-box-plugin-rewrite]].
