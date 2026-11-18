# Traveling Tournament Problem with Flexible Venues and Budget-Aware Optimization

**CSPLib problem 068 — Traveling Tournament Problem with Predefined Venues (TTPPV)**, originally modeled by Gilles Pesant.

This project extends the original [MiniZinc traveling tournament model](https://www.csplib.org/Problems/prob068/) to schedule a **compact single round-robin tournament** with flexible match venues, home/away balance, stadium closures, explicit travel distances, individual monetary travel budgets, and automatically computed financial travel priorities. It uses **Python 3**, **MiniZinc**, and the **Gecode** constraint solver.

## Problem and implemented extensions

For an even number of teams $n\ge4$, the tournament has $n - 1$ rounds. Every pair meets once, and every team plays one match per round.

1. **Flexible venues:** A match may have a predetermined home team or allow the solver to choose which of its two participants hosts it. A chosen host must be consistent for both teams.
2. **Home/away balance:** Each team $i$ must play a balanced number of home matches:

$$
\left\lfloor\frac{n-1}{2}\right\rfloor \le H_i \le \left\lceil\frac{n-1}{2}\right\rceil
$$

3. **Streak constraint:** A team cannot play four consecutive home matches or four consecutive away matches.
4. **Stadium availability:** Team $i$ cannot host a match in an unavailable round; it may still play away in that round.
5. **Explicit distances:** Travel distances are given by a symmetric, nonnegative matrix with a zero diagonal rather than a circular-distance formula. Teams start at home, travel directly between successive match venues, and return home at the end. They do **not** return home automatically between consecutive away matches.
6. **Team-specific expenses and monetary budgets:** Team $i$ pays $c_i$ per distance unit for all travel legs. Its total expense $E_i = c_i D_i$ cannot exceed its individual positive budget $B_i$.
7. **Budget-aware objective:** The solver penalizes travel more heavily for teams whose travel costs represent a larger proportion of their budgets. All team priorities are calculated automatically from the instance data.

Because stadium closures depend on the round, the model does not apply the original round-reversal symmetry-breaking constraint.

## Requirements and software versions

- **Operating system:** Linux (the script does not depend on Linux `/proc` paths, but Linux is the environment used for this project).
- **Python:** Python 3, using only the standard library (`os`, `re`, `subprocess`, `sys`, `tempfile`). **Exact tested version: [fill in after checking]**.
- **MiniZinc:** Installed and available on `PATH`. **Exact tested version: [fill in after checking]** (2.9.3 was reported earlier; confirm whether it has since been updated).
- **Solver:** Gecode, available through MiniZinc as `gecode`. **Exact Gecode version: [fill in after checking]**.

Check the versions on the computer used for the experiments:

```bash
python3 --version
minizinc --version
minizinc --solvers | grep -i gecode
```

The project uses **Gecode** by default, with a solver time limit of **60 seconds per instance** (`TIME_LIMIT_MS = 60000` in `proj.py`). Adjust that constant in the source to use a different limit. The search strategy described below is part of the MiniZinc model, not a change to the objective function.


## Input format (`.in`)

The program accepts the **input file path as its first command-line argument**. It does **not** read the instance from standard input.

Each `.in` file consists of **five required blocks** and **one optional sixth block**, separated by blank lines. The parser accepts ordinary whitespace between individual entries (spaces, tabs, or line breaks as appropriate).

| Block | Content | Format | Meaning |
|---|---|---|----|
| 1 | Number of teams | A single even integer $n \ge 4$ | Teams are numbered $1$ through $n$. |
| 2 | Venue preferences | $n \times n$ matrix, spacae separated entires | `home`: row team hosts column team; `away`: row team visits column team; `UND`: host chosen by the solver. |
| 3 | Travel costs | $n$ positive integers $c_i$, **tab-separated** | Cost per distance unit for each team. |
| 4 | Stadium distances | Symmetric $n \times n$ matrix, **tab-separated** entries | Nonnegative symmetric distances, zero on the diagonal. |
| 5 | Monetary budgets | $n$ positive integers $B_i$, **tab-separated** | Maximum travel expenses per team. |
| 6 (optional) | Stadium unavailability | **Tab-separated** `team,round` pairs | Rounds in which a team cannot host. If omitted, all stadiums are available. |

For two different teams, venue entries must be `(home, away)`, `(away, home)`, or `(UND, UND)` when viewed from opposite sides of the matrix. The diagonal is ignored. Round numbers range from $1$ to $n-1$.

The current parser expects the specified spaces, tabs, and blank lines. In particular, the travel-cost, distance, budget, and unavailability entries should use **tabs**, not arbitrary whitespace. No optimization weights are provided in `.in` files.

### Example: `4teams_unavailable.in`

```text
4

home home UND UND
away home UND UND
UND UND home UND
UND UND UND home

2 3 4 3

0 1 2 1
1 0 1 2
2 1 0 1
1 2 1 0

20 20 20 20

1,1 2,2 3,3 4,1
```

The last block prohibits team 1 from hosting in round 1, team 2 in round 2, team 3 in round 3, and team 4 in round 1. These are restrictions on **home** matches only.

To allow every stadium in every round, omit the final blank line and sixth block entirely.

## Execution and generated files

Run from the project directory, using input redirection from a regular `.in` file:

```bash
python3 proj.py inputs/4teams_unavailable.in
```

Or, for a six-team instance:

```bash
python3 proj.py inputs/6teams_flex15_original.in
```

The pipeline is:

```text
<instance>.in
    -> Python parser -> instances/<instance>.dzn
    -> MiniZinc model + Gecode (60-second limit)
    -> raw/<instance>.txt (raw solver stdout and stderr)
    -> Python output formatter
    -> outputs/<instance>.out + terminal stdout
```

For an input named `4teams_unavailable.in`, the script produces:

| Generated output | Meaning |
|---|---|
| `instances/4teams_unavailable.in` | Input file with the required input blocks, later parsed to make the `.in` file.  |
| `instances/4teams_unavailable.dzn` | MiniZinc parameter data converted from the `.in` file |
| `TTPFVHBTDMBSA-BA.mzn` | MiniZinc constraint model, generated by `proj.py`. |
| `raw/4teams_unavailable.txt` | Original MiniZinc/Gecode standard output, followed by standard error |
| `outputs/4teams_unavailable.out` | Human-readable tournament schedule and travel statistics |
| Terminal standard output | The same human-readable report printed to the console |


### Reading the output

The formatted output includes:

- **Game Schedule:** Each team's opponents in round order, indicating whether each match is at home (`at home`) or away (`away`).
- **Per-team statistics:** Each team's total distance travelled, amount spent, initial monetary budget, and **travel priority**.
- **Overall Stats:** Total distance travelled and total transportation expenses.

The printed travel priority is the **normalized mathematical weight**, rounded to **two decimal places** for display. It is not the large integer coefficient used internally by Gecode, and the formatted output does not currently print the scaled objective value.

If the solver reports infeasibility, the script prints `No valid schedule exists for this instance`. If the solver reports `=====UNKNOWN=====`, the current formatter prints `No schedule found within 60 seconds` rather than attempting to show an intermediate solution. When the script formats a solution without a proof marker (`==========`), it appends a notice that the best schedule has **not been proven optimal**. The raw solver transcript in `raw/` is the authoritative record for statuses and diagnostics. However, for an explicit optimality check, run MiniZinc directly on a generated instance:

```bash
minizinc --solver gecode TTPFVHBTDMBSA-BA.mzn instances/4teams_un.dzn
```

## Project structure

```text
proj.py                  Main program: input -> data (.dzn) -> MiniZinc -> raw output -> report
TTPFVHBTDMBSA-BA.mzn     MiniZinc model generated by proj.py
inputs/                  Test instances in the proj.py input format (*.in)
instances/               MiniZinc data generated by proj.py for each input (*.dzn)
raw/                     Raw MiniZinc output for each input (*.txt)
outputs/                 Reports produced by proj.py for each input (*.out)
baseline/                Original CSPLib TTPPV model (starting point)
report/                  LaTeX report (report.tex) and its PDF
```


## Internal MiniZinc data

`proj.py` converts the input into these MiniZinc parameters:

| Parameter | MiniZinc type | Description |
|---|---|---|
| `nbTeams` | `int` | Even number of teams. |
| `pv` | `array[Teams,Teams] of 1..3` | Venue choices: `home = 1`, `away = 2`, `UND = 3`. |
| `cost_per_unit_of_distance` | `array[Teams] of int` | Team-specific travel cost per distance unit. |
| `distance` | `array[Teams,Teams] of int` | Pairwise stadium distances. |
| `budget` | `array[Teams] of int` | Individual monetary travel budgets. |
| `available` | `array[Teams,Rounds] of bool` | Whether the team may host in each round. |

The `available` matrix is always generated, including when block 6 is omitted (in that case, every entry is `true`). The MiniZinc model enforces input consistency and the tournament constraints.


## Budget-aware mathematical objective

For each team `i`, define:

- $D_i$: its total travelled distance, including the first departure and final return;
- $c_i$: its monetary travel cost per distance unit;
- $B_i$: its positive travel budget;
- $E_i = c_iD_i$: its actual travel expenditure.

The **hard budget constraint** is $E_i \le B_i$ for every team.

The team's **financial sensitivity to travel** and the mean sensitivity are

$$
s_i = \frac{c_i}{B_i}, \qquad \bar{s}=\frac{1}{n}\sum_{j=1}^{n}s_j.
$$

Since $s_i$ is the fraction of the budget consumed per distance unit, teams with larger $s_i$ are more financially sensitive to additional travel. The automatically calculated **normalized priority** is:

$$
\boxed{w_i=1+\frac{s_i}{\bar{s}}}
$$

and the mathematical objective is

$$
\boxed{\min \sum_{i=1}^{n}w_iD_i}
$$

Equivalently,

$$
\min\left(\sum_i D_i+\frac{1}{\bar{s}}\sum_i\frac{E_i}{B_i}\right)
$$

The `1` gives every team a common distance penalty; $s_i/\bar{s}$ gives a greater penalty to teams whose travel is financially more restrictive. In particular,

$$
\sum_i w_iD_i
=\underbrace{\sum_i D_i}_{\text{total travel distance}}
+\frac{1}{\bar{s}}\underbrace{\sum_i\frac{E_i}{B_i}}_{\text{sum of fractional budget utilizations}}
$$

Thus, the objective combines **total tournament travel distance** with the **sum of fractional budget utilizations**. It does not guarantee minimum total monetary expenditure or equal budget utilization, and the priorities are fixed by the input rather than adjusted to the resulting schedule.


### Exact integer coefficients used by Gecode

Since the weights $w_i$ can be rational, the model optimizes an equivalent integer objective instead of using floating-point decision coefficients:

1. Compute $L=lcm(B_1,\ldots,B_n)$ and $a_i=c_i(L/B_i)$.
2. Compute $A=\sum_j a_j$ and $C_i=A+na_i$, so that $w_i=C_i/A$.
3. Divide all $C_i$ by their greatest common divisor $g$ to obtain integer coefficients $q_i=C_i/g$.
4. Optimize the integer expression:

```minizinc
constraint budgetAwareObjective =
    sum(i in Teams)(priorityCoefficient[i] * teamDistance[i]);

solve :: seq_search([
    int_search(opponent, first_fail, indomain_min),
    int_search(matchHost, input_order, indomain_min)
]) minimize budgetAwareObjective;
```

Here `priorityCoefficient[i] = q_i` and `normalizedPriority[i] = w_i`. Because $q_i=(A/g)w_i$, the integer expression is a **positive constant multiple** of the intended objective and therefore has **exactly the same optimal schedules**, assuming integer arithmetic does not overflow. If an integer objective value $Q$ is obtained from a solver transcript, its original normalized weighted value is $Qg/A$.

**Search optimization:** The `seq_search` annotation instructs Gecode to assign **opponents/scheduling variables first** using `first_fail`, and then **match hosts** using `input_order`. This changes the **search order**, not the objective or feasible solutions. It has substantially reduced solve time for the tested instances, although solver runtime depends on the instance and environment.

**Numerical limit:** The LCM of large, relatively prime budgets may produce coefficients too large for the solver's supported integer range. Test larger instances accordingly.

### Four-team illustration

The data generated from `inputs/4teams_budget_aware.in` contains:

```minizinc
cost_per_unit_of_distance = [2, 3, 4, 3];
budget = [20, 20, 20, 20];
```

Their sensitivities are `[0.10, 0.15, 0.20, 0.15]`, whose mean is `0.15`.

| Team | Sensitivity $s_i$ | Weight $w_i$ | Integer coefficient $q_i$ |
|---|---:|---:|---:|
| 1 | 0.10 | 1.6667 | 5 |
| 2 | 0.15 | 2.0000 | 6 |
| 3 | 0.20 | 2.3333 | 7 |
| 4 | 0.15 | 2.0000 | 6 |

The integer coefficients are exactly three times the rational weights. A previously verified four-team solution with all stadiums available travels **12 distance units** and costs **34**, with scaled objective **70**. The four-team stadium-closure test has a previously computed feasible schedule travelling **14 units** and costing **38**

A valid optimal schedule is:

```text
SCHEDULE
 2 @3 @4
@1 @4  3
 4  1 @2
@3  2  1
```

## Test instances and previous observations

The project includes or has been tested with the following `.in` instances:

| Instance | Description |
|---|---|
| `4teams_budget_aware.in` | Four teams, five flexible venues, all stadiums available |
| `4teams_unavailable.in` | Four teams, five flexible venues, four stadium closures |
| `6teams_fixed_original.in` / `6teams_fixed_relaxed.in` | All fifteen matches have fixed venues |
| `6teams_flex5_original.in` / `6teams_flex5_relaxed.in` | Five of fifteen matches have flexible venues |
| `6teams_flex15_original.in` / `6teams_flex15_relaxed.in` | All fifteen matches have flexible venues |
| `6teams_priority_demo.in` | All fifteen matches flexible, with team 6 having five times higher travel costs |

The six-team **relaxed** cases multiply every original budget by 1.5, leaving normalized weights unchanged while relaxing feasibility constraints.

Previously observed six-team results with **original budgets** were:

| Flexible matches | Total distance | Total travel expenses |
|---|---:|---:|
| 0 of 15 | 258 | 772 |
| 5 of 15 | 258 | 772 |
| 15 of 15 | 231 | 706 |

These are results from prior experiments on the same optimization formulation, **not newly rerun benchmarks of this Python version**. The raw solver output should be retained if formally reporting solve times or proven optimality. For the 15-flexible-match case, the previous objective calculation used the same weights as the current model.
