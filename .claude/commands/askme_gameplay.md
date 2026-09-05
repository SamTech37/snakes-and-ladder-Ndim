---
description: Interview the user about a gameplay or design idea, then write a design spec into .claude/
---

The user wants to design: $ARGUMENTS

Read `CLAUDE.md` first so you interview against what already exists — the current rules, what the prototype is trying to answer, and what is deliberately not built yet. Don't ask about anything that file already settles.

Interview them in depth using the AskUserQuestion tool to flesh out a real design before any code is written. This is a game, so the spec has to answer what the player *does* and what makes it interesting — not just what the software contains.

Cover the hard parts they might not have thought through:

- **The decision.** What is the player actually choosing between each turn, and what makes it a choice rather than arithmetic? If there is a dominant option, the mechanic is already broken — say so.
- **Trade-offs over numbers.** Does this add a cost as well as a gain? A mechanic that only adds a bigger number is a numbers game, not a design. Push back when a proposal is stat-stacking wearing a costume.
- **Feedback loops.** Which loops does this create or close — reinforcing or balancing? What behaviour emerges when two of them interact, and where does it bifurcate into a runaway or a stalemate? Most of the interesting behaviour comes from combining few loops, so name them explicitly.
- **Legibility.** Can the player see the state they need in order to decide well? A good decision made blind is a coin flip. What must be on screen, and what is deliberately hidden?
- **Feel and pacing.** Turn length, session length, how a run ends, what the player remembers afterward.
- **Failure.** What losing looks like, whether it's recoverable, and whether a wasted turn reads as tension or as the game wasting the player's time.
- **Scope.** What's explicitly *not* in v1, and what would have to be true before it earns a place.

Skip obvious questions. If you can guess the answer with high confidence, don't ask — state your assumption and move on. Dig into ambiguity, surface trade-offs the user hasn't named, and push back when a stated requirement conflicts with another or with a rule already in `CLAUDE.md`.

Ask in rounds: a few focused questions per turn, then incorporate the answers before the next round. Stop when you have enough to write a real spec — not before, not long after.

When done, write a complete spec into `.claude/` with a descriptive kebab-case filename ending in `-spec.md` (e.g. `.claude/channel-switching-spec.md`) — never `SPEC.md`, never repo root. Cover:

- **Pitch** — one paragraph: what the player does, and why that is interesting
- **Core loop** — the turn, moment to moment
- **The decision** — what is being traded against what, and why no option dominates
- **Systems & feedback loops** — each loop named, its polarity, and what emerges when they interact
- **Legibility** — what the player can see, what is hidden, how the UI carries it
- **Design decisions** — the choices made and why, including the ones rejected
- **Open questions** — what only playtesting can settle
- **Out of scope for v0** — deferred, with the condition that would earn each one in
