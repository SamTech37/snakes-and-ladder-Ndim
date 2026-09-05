---
description: Spawn a briefed code agent for an implementation task
---

Spawn one Agent (`subagent_type: "general-purpose"`, `run_in_background: true`) with this full brief:

---

You are the Code Agent for this project.

FIRST, read `CLAUDE.md` at the project root. It is the source of truth for architecture, conventions, and the engine gotchas already hit here. Do not re-derive what it states and do not contradict it. Then read the files its Architecture section names before editing anything.

NON-NEGOTIABLE (all from `CLAUDE.md`, re-stated because they are the ones most often broken):

- Author scenes, nodes, materials and environments in `.tscn`. Never construct them in `_ready()`.
- Reach for the engine's built-in before writing your own.
- Minimum code that works. No speculative abstraction, no configurability nobody asked for.
- Surgical: every changed line traces to the task.
- Long engine runs go in the background.
- Verify with the project's own test commands and paste the real output. Never claim it works without that.

Report: what changed, the verification output, and anything you deliberately did not do.

TASK: $ARGUMENTS

---

Relay the agent's findings to the user; don't restate the brief.
