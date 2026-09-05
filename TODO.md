# Session 1

1. playability [DONE]
2. Events: Roguelike & RNG

Fight foes by rolling dices. win their alternative dices or make your own stronger.

fight goes like this
(a) roll dices to decide what minigames to play: 比大、比小、對子、奇偶、吹牛、猜結果、比中位數、比標準差、...any simple dice games you can think of
(b) roll dices to decide the points, the numbers.
could be (a) then (b) OR (b) then (a), because sometimes you don't know what you're up against before you start rolling the dices. that's fun.

the key idea here is that the game is arranged into a series of mini-games and decisions and tactics embedded inside this larger meta-game, going from Source Point to Destination Point.

3. procedural generation?

how to foster an environment where fun and unpredictable chain reactions can happen, like in Balatro?

snakes and ladders need to be properly distributed across the map.

non-uniform tile size (visuals only) and non-uniform grid (actual mechanism)?

4. twist and turn continue

end game ask replay or continue. continue makes the dimension goes from D to D+1, and the game continues from that point onward.

---

# Session 2

now the presence of Snakes & Ladders (links) feels a bit weak. we have turned this thing into a game about dices and dimensionals and odds. but what about the funsies of being thwarted back in space? (and time perhaps.)

oh right, the Roamer Foes roll their die to catch you, but they will also be affected by the links.

Skills: passive skills provided by special/rare dies. e.g. can ignore Snakes, attracts to Ladders, has more favorable rolls, etc. simple stuff only. this might seems OP but in case that the later stages gets too difficult or repetitive, which they will, it'll come in handy

the oracle die: a sphere, ask input for what roll of number you want, and gives you exactly that.

the devil's die: no. faces = D, each direction gets a different value. you still pick one axis to move along.

5. roamers should roam, not hunt

playtested: the chaser is diabolical. it follows you to the edge of the world and turns every turn into pressure, which is exactly what the navigation game did not need. it also drags the endgame stall — already the tense part — into being the dangerous part.

replace it with two kinds of thing that stay where they belong:
- **standers**: fixed foes on cells, as now. you choose to walk into them.
- **roamers**: wander their own patch — a plane, a deck, a neighbourhood — and you meet one by being in the wrong place, not by being hunted. no pursuit, no distance readout, no clock.

the point is that the board stays somewhere you can look at and think in.

6. session plan

- **1.5** — undo the damage this session's solutions caused. the chaser above, and whatever else the playtest says is worse than what it replaced.
- **2** — spec, plan, then implement: sane mechanisms for the RNG (what dice appear, how foes are drawn, how gifts are placed) and for map generation (job iii — difficulty curve, reachable snakes, chain reactions).
