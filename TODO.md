# TODO

Status: ~~struck~~ = done · **HALF** = partly built · **RETOOL** = built wrong, needs redesign

## Session 1

1. ~~playability~~ **DONE**

2. **Events: roguelike & RNG** — **HALF, parts RETOOL**
   - ~~fight foes by rolling dice, win their dice~~
   - ~~minigames: 比大 比小 奇偶(odd/even call)~~ · 對子 吹牛 猜結果 比中位數 & multi-dice games (more than two), not built
   - ~~(a)-then-(b) and (b)-then-(a) as foe traits~~ — only the two _known_ orders (OPEN, TELL). Blind orders not built.
   - cf. 切蛋糕賽局：我先切你先選
   - **RETOOL** — the meta-game is now two games fighting each other for the screen. Fights interrupt navigation and share its dice.

3. **Procedural generation** — **not started**
   - links, foes and gifts are all uniform rejection sampling
   - no difficulty curve, no guarantee a snake is reachable, no chain reactions
   - non-uniform tile size / non-uniform grid: untouched

4. **Twist and turn: D → D+1** — **HALF**
   - ~~beat the boss, climb a dimension, keep the kit~~
   - ~~animated transition~~
   - no replay/continue _choice_ at the end — it just climbs
   - **open**: per-axis extent shrinks 10→6→4→3 as D rises, to hold a floor's crossing cost constant while cells multiply. That is why 5D is nine 3×3 squares with nothing to look at. Never revisited after boards became floors.

## Session 1.5 — undo what this session broke

5. **Roamers should roam, not hunt** — **RETOOL**
   - the chaser follows you to the edge of the world; every turn becomes pressure, and the endgame stall goes from tense to fatal
   - **standers**: fixed foes on cells, as now — you choose to walk into them
   - **roamers**: wander their own patch (a plane, a deck, a neighbourhood). You meet one by being somewhere, not by being hunted. No pursuit, no distance readout, no clock.
   - roamers roll their die to move, and links carry them too

6. **Links feel weak** — **open**
   - the game became dice, dimensions and odds; being thwarted back through space (and time?) is what snakes and ladders were for

7. **Whatever else the playtest condemns** — the verdict is that the whole is worse than the navigation game it was built on

## Session 2 — spec, plan, then build

8. **Sane RNG mechanisms** — which dice appear, how foes are drawn, how gifts are placed
9. **Map generation** — item 3 above, properly specced first

## Later

10. **Skills** — passive effects on rare dice: ignore snakes, attract to ladders, favourable rolls. Simple only. Reserve for when later floors get repetitive.
11. **Oracle die** — a sphere; name the roll you want and get it
12. **Devil's die** — faces = D, distinct values for each direction; you still pick the axis to move along
13. **d1** — deletes the endgame if handed over early; unlock material
14. **Platonic Solid** — I imagine it would look kick-ass. perhaps not that useful in this case. need to figure out the map size issues first. but if we only adopted the visual and disregard the count in relation to the dice faces, it'd be fine.
15. **Dice Roll Animation** — now the dice rolls feels dry, especially in fights. add the animation, and click-clack dice sounds for SFX, then we're talking.
16. **Blind commit orders** — commit first, learn after. Only a bet once the vocabulary exists.
17. **CC0 synthwave BGM** — hook is in, no track sourced
18. **Reference art half used** — `ideas/sketch.png` deck arrangement is built; the perspective-warped and wave-displaced grids in the other plates are not
