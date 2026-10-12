# Traveling Tournament Problem with Flexible Venues and Home/Away Balance (TTPFVHB)

The TTPFVHB consists of finding an optimal compact single round-robin schedule for a sporting event. Given an **even** number $n$ of teams, each team must play against every other team exactly once, over $n-1$ rounds. Each team plays exactly one match per round, either at home or away, and no team can play more than three consecutive matches at home or away. The objective is to minimize the total distance traveled by all teams.

The particularity of this problem resides in the **partial definition of match venues**. In the original Traveling Tournament Problem with Predefined Venues (TTPPV), the home team of every match is fixed in advance. In the TTPFVHB, some matches have predefined venues, while others have **flexible venues**: the solver must decide which of the two teams hosts the match, as well as the round in which it takes place.

For each pair of distinct teams $a$ and $b$, the input specifies one of the following:

- **Fixed at $a$'s venue:** team $a$ must host team $b$.
- **Fixed at $b$'s venue:** team $b$ must host team $a$.
- **Flexible:** either team may host the match.

For example, the match between teams 0 and 1 might be fixed at team 0's venue, while the match between teams 0 and 2 may take place at either team's venue. Regardless of its venue, each pair of teams plays only once.

In addition, the schedule must be **balanced**: every team must play approximately the same number of home and away matches. Let $H_a$ denote the number of home matches played by team $a$. Then

$$
\left\lfloor\frac{n-1}{2}\right\rfloor \leq H_a \leq
\left\lceil\frac{n-1}{2}\right\rceil
\qquad\text{for every team }a.
$$

For example, in an 8-team tournament, each team must play either 3 or 4 matches at home, and the remaining matches away. This restriction applies both to matches with predefined venues and to those whose venues are selected by the solver. Some combinations of predefined venues may therefore make an instance infeasible.

As in the original TTPPV instances, the teams' home venues are arranged on a circle and the travel distances are symmetric. Numbering the teams from $0$ to $n-1$, the distance between venues $a$ and $b$ is

$$
d_{ab} = d_{ba} = \min\bigl(|a-b|,\;n-|a-b|\bigr),
\qquad d_{aa}=0.
$$

For each team, the total travel distance is computed from the sequence of match venues, assuming the team starts at its own home venue and returns home after the final round. Consecutive away matches may involve traveling directly from one opponent's venue to another.

For example, if team $a$ has the following schedule:

```text
home  @3  @5  home  @2  home  @4
```

then its travel distance is

$$
T_a = d_{a3} + d_{35} + d_{5a} + d_{a2} + d_{2a} + d_{a4} + d_{4a}.
$$

The `@` prefix indicates an away match. For example, `@3` means that team $a$ plays at team 3's home venue.

A schedule is feasible if:

1. Every pair of teams plays exactly once.
2. Every team plays exactly one match in each of the $n-1$ rounds.
3. Every match with a predefined venue respects that venue.
4. For each flexible match, the solver chooses exactly one of the two teams as host.
5. No team plays more than three consecutive home or away matches.
6. Every team satisfies the home/away balance constraint.

Among all feasible schedules, the objective is to minimize the total travel distance:

$$
\min \sum_{a=0}^{n-1} T_a.
$$

## Extension over the original TTPPV

Unlike the original TTPPV, where match venues are fully determined by the input, the TTPFVHB requires the solver to **jointly decide match rounds and the venues of flexible matches**. Venue choices affect the teams' travel distances, home/away streaks, and home/away balance, so these decisions cannot be made independently.

The extension can be evaluated by varying the proportion of matches with flexible venues (for example, 0%, 25%, 50%, 75%, and 100%) and comparing the resulting optimal travel distances, solver execution times, and feasibility. Keeping the original circular distances makes these comparisons possible without introducing a separate distance-model extension.
