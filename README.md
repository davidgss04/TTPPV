# Traveling Tournament Problem with Flexible Venues, Home/Away Balance, Travel Distances, Monetary Travel Budgets, Stadium Availability, and Budget-Aware Weighted Optimization

This project extends Gilles Pesant's Traveling Tournament Problem with Predefined Venues (TTPPV; CSPLib problem 068). It finds a **compact single round-robin** tournament schedule that respects match venues, home/away balance, stadium availability and individual monetary travel budgets. Flexible matches may be hosted by either of their teams.

The objective uses **automatically calculated, team-specific financial priorities**.

## Tournament rules

For an even number `nbTeams = n >= 4`:

1. **Round robin:** Every unordered pair of teams plays exactly once, and every team plays exactly one match in every round.
2. **Venue selection:** Every fixed match is played at its predefined venue. Every flexible match is hosted by exactly one of its two teams, consistently from both teams' perspectives.
3. **Home/away balance:** The number of home games $H_i$ of each team satisfies

   $$
   \left\lfloor\frac{n-1}{2}\right\rfloor \le H_i \le
   \left\lceil\frac{n-1}{2}\right\rceil.
   $$
4. **Home/away streaks:** No team plays four consecutive home matches or four consecutive away matches.
5. **Stadium availability:** Team $i$ cannot play at home in a round $r$ with $A_{i,r}=0$.
6. **Explicit distance matrix.** `distance[i,j]` is a nonnegative symmetric distance between stadiums (zero diagonal). Teams begin and finish at home and travel directly between consecutive match venues, including between successive away games.
7. **Team-dependent travel expenditure.** Team `i` pays a constant `cost_per_unit_of_distance[i]` credits for each unit it personally travels. The rate is applied to **all legs**, including travel to the first match and the return home. Budgets now limit **money**, not distance.
8. Each team begins at home, travels directly between its consecutive match venues and returns home after its last match. A team does *not* return home automatically between consecutive away games.
9. **Team travel Budget:** Monetary transportation expenses cannot exceed each team's budget.
10. **Budget-aware weighted optimization:** Each team $i$ is assigned an automatically calculated weight based on its travel cost per distance unit $c_i$ and monetary budget $B_i$. Teams with higher costs relative to their budgets receive greater priority in the optimization. The weight $w_i$ is defined as:

    $$
    w_i = 1 + \frac{c_i/B_i}{\frac{1}{n}\sum_{j=1}^{n}c_j/B_j}
    $$

    The objective is to minimize the total weighted travel distance:

    $$
    \boxed{\min \sum_{i=1}^{n} w_i D_i}
    $$

    where $D_i$ represents the total distance traveled by team $i$. This approach minimizes overall travel distance while accounting for each team's financial constraints, without requiring manually specified weights.

Stadium distances are supplied as a symmetric, nonnegative matrix with zero diagonal; they need not be circular.

## Input data

| Input | MiniZinc type | Meaning |
|---|---|---|
| `nbTeams` | `int` | Even number of teams (at least four), numbered `1..n`. |
| `pv` | `array[Teams,Teams] of 1..3` | `1`: row team hosts column team; `2`: row team visits column team; `3`: flexible venue. |
| `distance` | `array[Teams,Teams] of int` | Pairwise stadium distances. |
| `cost_per_unit_of_distance` | `array[Teams] of int` | Each team's **positive** expense in credits per distance unit. |
| `budget` | `array[Teams] of int` | Each team's **positive** maximum monetary travel expense in credits. |
| `available` | `array[Teams,Rounds] of bool` | Whether the team can host a match in that round. |

For a fixed match, the opposite matrix entries must be `(1,2)` or `(2,1)`; for a flexible match, they must be `(3,3)`. The diagonal is ignored. Both rates and budgets are strictly positive to make the financial sensitivity well-defined. **There are no manually chosen weights in the `.dzn` files.**

## Budget-aware objective

Let:

- `D_i` be the total distance traveled by team `i`, including its first and final journey;
- `c_i` be its cost per unit of distance;
- `E_i = c_i D_i` be its total travel expense;
- `B_i` be its monetary travel budget.

The model always enforces **`E_i <= B_i`**.

Each team's financial sensitivity is the fraction of its budget spent **per distance unit**:

\[
s_i = \frac{c_i}{B_i}, \qquad \bar{s} = \frac{1}{n}\sum_{j=1}^n s_j.
\]

The automatically derived priority for team `i` is:

\[
p_i = 1 + \frac{s_i}{\bar{s}}.
\]

Thus, the objective is exactly

\[
\boxed{\min\sum_{i=1}^{n}\left(1 + \frac{c_i/B_i}{\frac1n\sum_{j=1}^{n}c_j/B_j}\right)D_i}.
\]

The `1` gives every team a common distance penalty; the second term emphasizes teams whose travel is more expensive relative to their budgets. For instance, reducing the distance traveled by a financially sensitive team has more impact on the objective than an identical reduction for a less sensitive team.

Equivalent interpretation:

\[
\min\left[\sum_i D_i + \frac{1}{\bar s}\sum_i\frac{E_i}{B_i}\right].
\]

This is a **single centralized weighted optimization objective**, not a game-theoretic model and not an objective that directly minimizes the maximum individual burden. Team priorities depend only on input data, *not* on the chosen schedule. A team with a higher priority coefficient does not necessarily end up traveling less; all constraints and competing interests still matter.

### Exact integer optimization for Gecode and Chuffed

The objective uses rational, *fixed* coefficients. Rather than optimize using floating-point decision variables, `TTPFVHBTDMBSA-BA.mzn` clears the denominators and minimizes an **exactly equivalent integer objective**:

1. Let `L = lcm(B_1,...,B_n)` and `a_i = c_i * (L div B_i)`.
2. Let `A = sum(a_i)`.
3. Then `p_i = (A + n*a_i)/A`.
4. Remove the greatest common divisor of `A+n*a_i` from all coefficients. The remaining positive integers are `priorityCoefficient[i]`.
5. Minimize `sum(priorityCoefficient[i] * D_i)`.

Multiplying all objective values by one positive constant does not change the minimizing schedules. The program prints the **scaled integer score**, not the numerical value of the boxed rational expression. The printed score can be converted to the original rational value using `scaled_score * coefficientGCD / A`.

**Limit:** Exact integer scaling can create very large coefficients when many budgets have large, pairwise-coprime values. This may cause integer overflow or slower solving. The supplied 4- and 6-team tests use moderate budgets; for larger instances, check coefficient magnitudes or consider a documented bounded-precision approximation.

## Four-team example

`instances/4teams_budget_aware.dzn` uses:

```minizinc
cost_per_unit_of_distance = [2, 3, 4, 3];
budget = [20, 20, 20, 20];
```

Their sensitivities are `[0.10, 0.15, 0.20, 0.15]`, whose mean is `0.15`.

| Team | Sensitivity | Mathematical priority | Exact scaled coefficient |
|---|---:|---:|---:|
| 1 | 0.10 | 1.6667 | 5 |
| 2 | 0.15 | 2.0000 | 6 |
| 3 | 0.20 | 2.3333 | 7 |
| 4 | 0.15 | 2.0000 | 6 |

The simplified coefficients are `[5,6,7,6]` (equal to the mathematical priorities times 3). A valid optimal schedule is:

```text
SCHEDULE
 2 @3 @4
@1 @4  3
 4  1 @2
@3  2  1
```

Team distances `[4,4,2,2]` imply a total distance of `12` and expenses `[8,12,8,6]` (total **34 credits**). The exact *scaled* objective is **70**; the boxed expression evaluates to `70/3 ≈ 23.3333` for this schedule. Independent exhaustive enumeration confirms that **70 is the minimum scaled objective** for this instance; four schedules attain it. MiniZinc should print `==========` when it proves optimality itself.

## Six-team instances

- `instances/6teams_fixed_budget_aware.dzn`: all venues fixed.
- `instances/6teams_flex5_budget_aware.dzn`: five of 15 matches flexible.

Both retain the previous monetary budgets, travel costs, stadium closures and distance matrix. The previously verified feasible six-team reference schedule travels `258` units and costs `772` credits. With the new automatic priorities, its scaled score is **106641717**; this is only a *feasible benchmark*, not a claimed optimum.

## Run the model

From this folder:

```bash
minizinc --solver gecode TTPFVHBTDMBSA-BA.mzn instances/4teams_budget_aware.dzn

minizinc --solver gecode TTPFVHBTDMBSA-BA.mzn instances/6teams_fixed_budget_aware.dzn

minizinc --solver gecode TTPFVHBTDMBSA-BA.mzn instances/6teams_flex5_budget_aware.dzn
```

Use `python3 verify_4teams.py` for an independent, MiniZinc-free exhaustive check of the first instance.

`==========` means optimality was proved. `=====UNKNOWN=====` indicates an unfinished search, such as a timeout; report its result as the best solution found, **not** the proven optimum.

## Suggested experiments

Compare the new budget-aware model against a distance-only baseline (`minimize totalTravel`) and an expense-only baseline (`minimize totalExpense`), **keeping every constraint and each instance the same**. Record travel distance, actual expenditure, maximum budget utilization, scaled budget-aware score, time to solution, and optimality status. You can also vary the number of flexible matches or modify the cost/budget ratios to investigate when team-specific priorities alter the schedule.

**Validation status:** The 4-team optimum was checked independently by exhaustive enumeration. MiniZinc is not installed in this working environment, so compilation and solver performance of the generated `.mzn` must be checked locally.
