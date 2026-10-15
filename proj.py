import sys
import os
import subprocess

#Input reading
print("Parsing input...", file=sys.stderr)

chunks = sys.stdin.read().split("\n\n")
filename = os.path.basename(os.readlink("/proc/self/fd/0"))[:-3]
instance = ""

#Parsing number of teams
n = int(chunks[0])
instance += f"nbTeams = {n};\n\npv = [|\n"

#Parsing venue matrix
venue_labels = {"home": 1, "away": 2, "UND": 3}
venues = [label.split(' ') for label in chunks[1].split('\n')]
for host in range(n):
    instance += "  "
    for opponent in range(n):
        l = venues[host][opponent]
        if host == n-1 and opponent == n-1: instance += f"{venue_labels[l]} |];\n\n"
        elif opponent == n-1: instance += f"{venue_labels[l]} |\n"
        else: instance += f"{venue_labels[l]}, "

instance += "cost_per_unit_of_distance = ["

#Parsing cost per unit of distance for each team
costs = chunks[2].split('\t')
for k in range(n):
    if k == n-1: instance += f"{costs[k]}];\n\n"
    else: instance += f"{costs[k]}, "

#Parsing distance matrix
instance += "distance = [|\n"
distances = [distance.split('\t') for distance in chunks[3].split('\n')]
for i in range(n):
    instance += "  "
    for j in range(n):
        v = distances[i][j]
        if i == n-1 and j == n-1: instance += f"{v} |];\n\n"
        elif j == n-1: instance += f"{v} |\n"
        else: instance += f"{v}, "

instance += "budget = ["

#Parsing team budget
budgets = chunks[4].rstrip().split('\t')
for b in range(n):
    if b == n-1: instance += f"{budgets[b]}];\n"
    else: instance += f"{budgets[b]}, "

# Stadium availability
availability = [["true" for _ in range(n - 1)] for _ in range(n)]

# Parse optional stadium unavailability restrictions
if len(chunks) > 5 and chunks[5].strip():
    unavailability = chunks[5].strip().split('\t')

    for info in unavailability:
        team, round = map(int, info.split(','))
        availability[team - 1][round - 1] = "false"

# Generate MiniZinc availability matrix
instance += "\navailable = [|\n"

for t in range(n):
    instance += "  "
    for r in range(n - 1):
        a = availability[t][r]
        if t == n - 1 and r == n - 2: instance += f"{a} |];\n"
        elif r == n - 2: instance += f"{a} |\n"
        else: instance += f"{a}, "

#Creating run file
print("Creating run file...", file=sys.stderr)

with open(f"instances/{filename}.dzn", "w") as ins:
    ins.write(instance)

#Creating CSP model
print("Creating CSP model...", file=sys.stderr)

model = r"""
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Traveling Tournament Problem with Flexible Venues, Home/Away Balance,
% Travel Distances, Monetary Travel Budgets, Stadium Availability,
% and Budget-Aware Weighted Optimization (TTPFVHBTDMBSA-BA)
%
% Extension of Gilles Pesant's TTPPV (CSPLib problem 068).
% Teams and rounds are indexed from 1, as in the original MiniZinc model.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

include "globals.mzn";

int: nbTeams;
int: nbRounds = nbTeams - 1;

set of int: Teams = 1..nbTeams;
set of int: Rounds = 1..nbRounds;
set of int: Travels = 1..nbRounds+1;

% pv[i,j] = 1: team i hosts j; 2: team j hosts i;
%           3: flexible (solver chooses the host).
% the diagonal is ignored.
array[Teams,Teams] of 1..3: pv;

% distances between team venues (symetric).
array[Teams,Teams] of int: distance;

% each team's monetary cost per unit of travel distance.
array[Teams] of int: cost_per_unit_of_distance;

% maximum travel budget each team has.
array[Teams] of int: budget;

% true when team i can host a match in round k.
% false does not prevent team i from playing away in that round.
array[Teams,Rounds] of bool: available;

int: maxDistance = max([distance[i,j] | i,j in Teams]);
int: digs = ceil(log(10.0, int2float(nbTeams)));

% ---------------------- Instance validation -----------------------
constraint assert(nbTeams >= 4 /\ nbTeams mod 2 = 0,
    "nbTeams must be even and at least 4");

constraint assert(
    forall(i,j in Teams where i < j)(
        (pv[i,j] = 3 /\ pv[j,i] = 3) \/
        (pv[i,j] = 1 /\ pv[j,i] = 2) \/
        (pv[i,j] = 2 /\ pv[j,i] = 1)
    ),
    "pv must use (1,2), (2,1) or (3,3) for each match"
);

constraint assert(
    forall(i,j in Teams)(
        distance[i,j] >= 0 /\ distance[i,j] = distance[j,i] /\
        (i != j \/ distance[i,j] = 0)
    ),
    "distance must be symmetric, nonnegative, and zero on the diagonal"
);

constraint assert(forall(i in Teams)(budget[i] > 0),
    "monetary travel budgets must be strictly positive");
constraint assert(forall(i in Teams)(cost_per_unit_of_distance[i] > 0),
    "cost per unit must be strictly positive");

% ---------------------- Decision variables ------------------------
% opponent of team i in round k.
array[Teams,Rounds] of var Teams: opponent;

% host of the match between teams i and j. Same host from both sides.
array[Teams,Teams] of var Teams: host;

% 1 = home, 2 = away, according to the chosen host.
array[Teams,Rounds] of var 1..2: venue;

% travel for the first journey, between rounds, and the return home.
array[Teams,Travels] of var 0..maxDistance: travel;

% distance between teams and monetary expense
array[Teams] of var 0..((nbRounds+1)*maxDistance): teamDistance;
array[Teams] of var 0..max(budget): teamExpense;

% ------------------------ Venue selection -------------------------
constraint forall(i,j in Teams where i != j)(
    (pv[i,j] = 1 -> host[i,j] = i) /\
    (pv[i,j] = 2 -> host[i,j] = j) /\
    (host[i,j] in {i,j})
);

constraint forall(i in Teams)(host[i,i] = i);
constraint forall(i,j in Teams where i < j)(host[i,j] = host[j,i]);

constraint forall(i in Teams, k in Rounds)(
    (venue[i,k] = 1) <-> (host[i,opponent[i,k]] = i)
);

% home/away balance for a compact single round-robin tournament.
constraint forall(i in Teams)(
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        >= nbRounds div 2 /\
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        <= (nbRounds + 1) div 2
);

% no team may host when its stadium is unavailable
constraint forall(i in Teams, k in Rounds)(
    not available[i,k] -> venue[i,k] = 2
);

% ----------------------- Round-robin rules ------------------------
constraint forall(i in Teams, k in Rounds)(opponent[i,k] != i);
constraint forall(i in Teams, k in Rounds)(
    opponent[opponent[i,k],k] = i
);
constraint forall(i in Teams)(
    alldifferent([opponent[i,k] | k in Rounds])
);
constraint forall(k in Rounds)(
    alldifferent([opponent[i,k] | i in Teams])
);

% no four consecutive home games or four consecutive away games
int: nbStates = 7;
set of int: States = 1..nbStates;
array[States,1..2] of int: delta =
    [| 2, 5
     | 3, 5
     | 4, 5
     | 0, 5
     | 2, 6
     | 2, 7
     | 2, 0 |];
constraint forall(i in Teams)(
    regular([venue[i,k] | k in Rounds], nbStates, 2, delta, 1, States)
);

% note: no round-reversal symmetry breaking
% stadium availability depends on the round, so reversing a schedule need not preserve feasibility

% ---------------------- Travel calculation ------------------------
% start at home before round 1.
constraint forall(i in Teams)(
    (venue[i,1] = 1 -> travel[i,1] = 0) /\
    (venue[i,1] = 2 -> travel[i,1] = distance[i,opponent[i,1]])
);

% travel directly between successive match venues.
constraint forall(i in Teams, k in 1..nbRounds-1)(
    (venue[i,k] = 1 /\ venue[i,k+1] = 1 ->
        travel[i,k+1] = 0) /\
    (venue[i,k] = 2 /\ venue[i,k+1] = 1 ->
        travel[i,k+1] = distance[opponent[i,k],i]) /\
    (venue[i,k] = 1 /\ venue[i,k+1] = 2 ->
        travel[i,k+1] = distance[i,opponent[i,k+1]]) /\
    (venue[i,k] = 2 /\ venue[i,k+1] = 2 ->
        travel[i,k+1] = distance[opponent[i,k],opponent[i,k+1]])
);

% return home after the final round.
constraint forall(i in Teams)(
    (venue[i,nbRounds] = 1 -> travel[i,nbRounds+1] = 0) /\
    (venue[i,nbRounds] = 2 ->
        travel[i,nbRounds+1] = distance[opponent[i,nbRounds],i])
);

% expenses depend on which team travels each distance unit:
% two teams can travel the same distance and spend different amounts.
constraint forall(i in Teams)(
    teamDistance[i] = sum(k in Travels)(travel[i,k]) /\
    teamExpense[i] = cost_per_unit_of_distance[i] * teamDistance[i] /\
    teamExpense[i] <= budget[i]
);

% ----------------- Automatic team priorities ---------------------
% Financial sensitivity: s_i = cost_per_unit_of_distance[i] / budget[i].
% Mean sensitivity: s_bar = sum(s_i) / nbTeams.
% Objective:
%
%   minimize sum(i in Teams)((1 + s_i / s_bar) * teamDistance[i])
%
% All s_i and s_bar are fixed instance parameters. To preserve exactness
% with integer CP solvers (like Gecode), we need to clear denominators and
% remove any common factor in the resulting positive coefficients.
%
% lcmBudget / budget[i] is an integer for every team i.
function int: gcd_pos(int: a, int: b) =
    if b = 0 then a else gcd_pos(b, a mod b) endif;

function int: lcm_budget_prefix(int: k) =
    if k = 1 then budget[1]
    else let { int: prev = lcm_budget_prefix(k-1) } in
        (prev div gcd_pos(prev, budget[k])) * budget[k]
    endif;

int: lcmBudget = lcm_budget_prefix(nbTeams);

% s_i = sensitivityNumerator[i] / lcmBudget.
array[Teams] of int: sensitivityNumerator =
    [cost_per_unit_of_distance[i] * (lcmBudget div budget[i])
     | i in Teams];
int: totalSensitivityNumerator = sum(sensitivityNumerator);

% 1 + s_i / s_bar
%   = (totalSensitivityNumerator +
%      nbTeams * sensitivityNumerator[i]) / totalSensitivityNumerator.
array[Teams] of int: coefficientNumerator =
    [totalSensitivityNumerator + nbTeams * sensitivityNumerator[i]
     | i in Teams];

function int: gcd_coefficient_prefix(int: k) =
    if k = 1 then coefficientNumerator[1]
    else gcd_pos(gcd_coefficient_prefix(k-1), coefficientNumerator[k])
    endif;

int: coefficientGCD = gcd_coefficient_prefix(nbTeams);

% integer coefficients with exactly the same minimizers as the formula.
array[Teams] of int: priorityCoefficient =
    [coefficientNumerator[i] div coefficientGCD | i in Teams];

% only for explanatory output; solver optimizes the exact integer objective.
array[Teams] of float: normalizedPriority =
    [int2float(coefficientNumerator[i]) /
     int2float(totalSensitivityNumerator) | i in Teams];

% --------------------------- Objective ----------------------------
var int: totalTravel;
var int: totalExpense;
var int: budgetAwareObjective;
constraint totalTravel = sum(i in Teams)(teamDistance[i]);
constraint totalExpense = sum(i in Teams)(teamExpense[i]);

constraint budgetAwareObjective =
    sum(i in Teams)(priorityCoefficient[i] * teamDistance[i]);

solve minimize budgetAwareObjective;

% ----------------------------- Output -----------------------------
output
    [ (if fix(venue[i,k]) = 1 then " " else "@" endif) ++
      show_int(digs, opponent[i,k]) ++ " " ++
      (if k = nbRounds then "\n" else "" endif)
      | i in Teams, k in Rounds ] ++
    ["\n"] ++
    [show(totalTravel), "\n"] ++
    [show(totalExpense), "\n"] ++
    ["\n"] ++
    [show(teamDistance[i]) ++ "\t" ++
     show(teamExpense[i]) ++ "\t" ++
     show(budget[i]) ++ "\t" ++
     show(normalizedPriority[i]) ++ "\n"
     | i in Teams];
"""

with open("TTPFVHBTDMBSA-BA.mzn", "w") as ml:
    ml.write(model)

#Running the CSP model with Gecode
print("Running CSP model using Gecode...", file=sys.stderr)

output = subprocess.run(["minizinc", "--solver", "gecode", "TTPFVHBTDMBSA-BA.mzn", f"instances/{filename}.dzn"], capture_output=True, text=True)

if output.returncode != 0:
    print(output.stderr, file=sys.stderr)
    sys.exit(output.returncode)

if "=====UNSATISFIABLE=====" in output.stdout:
    print("No solution was found.")
    sys.exit(0)

#Parsing final output
print("Producing final solution...", file=sys.stderr)
working = output.stdout.strip().split('\n\n')

solution = "GAME SCHEDULE:\n===========================================\n"

s = [line.rstrip().split(" ") for line in working[0].split('\n')]
schedule = []
for line in s:
    line = [el for el in line if len(el) != 0]
    schedule.append(line)

for team, matches in enumerate(schedule):
    solution += f"Team {team + 1}:\n"
    for match in matches:
        if match.startswith('@'): solution += f"  - vs Team {match[1:]}, away\n"
        else: solution += f"  - vs Team {match}, at home\n"
    solution += "===========================================\n"

solution += "\nTEAM TRAVEL DISTANCE AND EXPENSES:\n===========================================\n"

stats = working[2].split('\n')
del(stats[-1])
del(stats[-1])
stats = [team.split('\t') for team in stats]

for id, team in enumerate(stats):
    solution += f"Team {id + 1}:\n  Distance travelled: {team[0]}\n  Ammount spent: {team[1]}\n  Initial budget: {team[2]}\n  Normalised minimizing travel priority: {team[3]}\n===========================================\n"

solution += "\nOVERALL STATS:\n"
overall = working[1].split('\n')
solution += f"Total travelled distance: {overall[0]}\nTotal travel expenses: {overall[1]}\n"

with open(f"outputs/{filename}.out", "w") as out:
    out.write(solution)

print("Output:\n")
print(solution, end="")