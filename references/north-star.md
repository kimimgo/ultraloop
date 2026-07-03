# North-star protocol (north-star) — the vertical chain of goals ★

**Problem**: when planning drifts into "feature listing → filler cards", the board fills up but the *why* is gone. Even when
loop faithfully digests the cards, the product drifts. **Solution**: bind every plan item vertically to one final goal, and
make every loop re-read that goal.

```
north star (1 final goal)
  └─ milestone goals (state transitions toward the north star — 1 sentence each + a verdict question)
       └─ cards (1 line of contribution to the milestone goal — if it cannot be written, it is not a card)
```

---

## 1. Fixing the north star (pm chain stage 2 — right after strategy, before the roadmap)

Do not stop at the strategy canvas; distill the final goal with **deep questions**:

- Whose day, once this product is complete, **changes how?** (1 sentence from the user's perspective)
- **How is that change measured?** (≤3 leading indicators — a sentence that cannot be measured is not a north star)
- What will we **not do**? (≤3 anti-goals — the pre-drawn blocking line against scope creep)

Output = **one `north-star`-labeled issue** (title = the 1-sentence north star, body = indicators·anti-goals·rationale).
- It does **not go on the board as a card** — it is a reference point, not work. Pinning recommended.
- Frozen together at user approval. Modified only via pm re-entry (= an event of the same rank as a roadmap change).
- config `mission` is input only — the only canonical original of the fixed version is this issue (consistent with the board-SoT principle).

## 2. Deriving milestone goals (feature bundles ❌ → state transitions ⭕)

A milestone is not a stack of features but an **intermediate state on the way to the north star**. Each milestone description must contain:

```
Goal: when this milestone is done, [the user] can [do what].
Verdict: [1 question answerable Yes/No]
North-star contribution: [1 line on why this state transition moves toward the final goal]
```

A milestone without a goal sentence is unfinished planning. (Write it in the product's working language — per messaging.md, tool names forbidden.)

## 3. Card contribution gate (the filler-card filter)

**Every card body must carry one `Goal-link:` line** — "This card advances [which part] of [the milestone goal]."

- If this one line **cannot be written, do not create the card.** Items that do not trace back to a higher goal via 5 Whys are
  (a) dropped or (b) recorded as anti-goal violations.
- "Nice to have"-type items are not cards — send them to a north-star issue comment (the idea parking lot).
- Together with acceptance criteria and E2E scenarios it forms a 3-piece set — if even one is missing, board registration is forbidden (pm SKILL §3).

## 4. Re-alignment loop (loop side — the mechanism that never forgets the final goal)

The goal is recalled **by structure, not memory**:

1. **Every loop ①**: `regen_progress.sh` redraws the north star + milestone goals from the board **at the head** of PROGRESS.md —
   the final goal is re-injected into the loop context every time (a structure that cannot forget).
2. **Start comment**: when starting a card, quote that card's `Goal-link:` in the comment (in the product's working language).
   If there is no link to quote, do not start.
3. **Alignment check**: when a Ready card is found whose goal link is empty or which conflicts with the anti-goals —
   loop does not judge scope. `blocked` + a reason comment + pm escalation (approval queue).
4. **Milestone close-out**: when the last card goes Done, leave a comment on the milestone answering §2's verdict question
   with Yes/No. If No, it is not Done — record the gap as a new issue (within bug/edge authority) and escalate to pm.

## 5. Boundaries

- **Defining/modifying the north star and milestone goals is pm's authority alone** (loop only reads, quotes, escalates).
- `goal_check.sh` does machine verification only — the Yes/No of the verdict question falls to the agent + human (§4.4).
- v0.10: per-milestone goals DO get a machine counterpart — `engine.goal.scope: "milestone:<title>"`
  scopes the goal gate, the Ready pick, and the deploy marker to that milestone
  (engine-loop-and-goal.md §Run scope). The verdict question stays a human/agent judgment;
  the scope makes the RUN mechanically end where the milestone ends.
- In milestones fallback mode, the north-star issue is excluded from the completion verdict even while open (it is not work).
