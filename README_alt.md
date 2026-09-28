# Traveling Tournament Problem with Travel Budgets (TTPTB)

The TTPTB consists of finding an optimal compact single round robin schedule for a sport event. Given a set of $n$ teams, each team has to play against every other team exactly once. In each round, a team plays either at home or away, however no team can play more than three consecutive times at home or away. The sum of the traveling distance of each team has to be minimized.

The particularity of this problem resides on the venue of each game and on the travel budget of each team. If team $a$ plays against team $b$, it is already known whether the game is going to be held at $a$'s home or at $b$'s home. In addition, each team $a$ has a maximum travel budget $B_a$. The total distance traveled by team $a$ must not exceed $B_a$.

Unlike the original TTPPV, the distances between teams are not defined by a circular distance formula. Instead, the instance provides an arbitrary symmetric distance matrix. For every pair of teams $a$ and $b$,

$$
 d_{ab} = d_{ba}.
$$

The diagonal is defined as $d_{aa}=0$.

A schedule is feasible if every pair of teams plays exactly once, every team plays exactly once in every round, no team plays more than three consecutive home or away games, and every team's total travel distance is within its travel budget. Among all feasible schedules, the objective is to minimize the total travel distance of all teams.

For each team, the total travel distance is the distance traveled between successive match venues, with the team starting at and returning to its own home venue. A home match leaves the team at its own home venue, so no travel is required for that match.

For example, if team $a$ has the following sequence of venues during the tournament:

```text
home  @3  @5  home  @2  home  @4
```

then its travel distance is

$$
 d_{a3} + d_{35} + d_{5a} + d_{a2} + d_{24} + d_{4a}.
$$

The `@` prefix means that the team is playing away. For example, `@3` means that the team is playing an away match at team 3's home venue.

Each team has an individual travel budget. For team $a$ with budget $B_a$, its total travel distance $T_a$ must satisfy

$$
T_a \leq B_a.
$$

The objective is therefore to find a feasible schedule minimizing

$$
\sum_{a=1}^{n} T_a.
$$
