%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Traveling Tournament Problem with Flexible Venues,
% Monetary Travel Budgets and Stadium Availability (TTPFVBSA-BA)
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
% The diagonal is ignored.
array[Teams,Teams] of 1..3: pv;

% Explicit, symmetric, nonnegative venue-to-venue distances.
array[Teams,Teams] of int: distance;

% Each team's monetary cost per unit of travel distance.
array[Teams] of int: cost_per_unit_of_distance;

% Maximum monetary travel expenses for each team (credits).
array[Teams] of int: budget;

% True when team i can host a match in round k.
% False does not prevent team i from playing AWAY in that round.
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
% Opponent of team i in round k.
array[Teams,Rounds] of var Teams: opponent;

% Host of the match between teams i and j. Same host from both sides.
array[Teams,Teams] of var Teams: host;

% 1 = home, 2 = away, according to the chosen host.
array[Teams,Rounds] of var 1..2: venue;

% Travel for the first journey, between rounds, and the return home.
array[Teams,Travels] of var 0..maxDistance: travel;

% Per-team distance and monetary expense (derived from travel legs).
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

% Home/away balance for a compact single round-robin tournament.
constraint forall(i in Teams)(
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        >= nbRounds div 2 /\
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        <= (nbRounds + 1) div 2
);

% No team may host when its stadium is unavailable.
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

% No four consecutive home games or four consecutive away games.
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

% IMPORTANT: No round-reversal symmetry breaking! Stadium availability
% depends on the round, so reversing a schedule need not preserve feasibility.

% ---------------------- Travel calculation ------------------------
% Start at home before round 1.
constraint forall(i in Teams)(
    (venue[i,1] = 1 -> travel[i,1] = 0) /\
    (venue[i,1] = 2 -> travel[i,1] = distance[i,opponent[i,1]])
);

% Travel directly between successive match venues.
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

% Return home after the final round.
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
% The desired objective is EXACTLY:
%
%   minimize sum(i in Teams)((1 + s_i / s_bar) * teamDistance[i])
%
% All s_i and s_bar are fixed instance parameters. To preserve exactness
% with integer CP solvers (including Gecode), clear denominators and
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

% Integer coefficients with EXACTLY the same minimizers as the formula.
array[Teams] of int: priorityCoefficient =
    [coefficientNumerator[i] div coefficientGCD | i in Teams];

% Only for explanatory output; solver optimizes the exact integer objective.
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
output ["SCHEDULE\n"] ++
    [ (if fix(venue[i,k]) = 1 then " " else "@" endif) ++
      show_int(digs, opponent[i,k]) ++ " " ++
      (if k = nbRounds then "\n" else "" endif)
      | i in Teams, k in Rounds ] ++
    ["total travel distance = ", show(totalTravel), "\n"] ++
    ["total travel expenses = ", show(totalExpense), " credits\n"] ++
    ["scaled budget-aware objective = ", show(budgetAwareObjective), "\n"] ++
    ["\nTEAM DISTANCE / COST PER UNIT / EXPENSE / BUDGET / PRIORITY\n"] ++
    ["team " ++ show(i) ++ ": " ++
     show(teamDistance[i]) ++ " / " ++
     show(cost_per_unit_of_distance[i]) ++ " / " ++
     show(teamExpense[i]) ++ " / " ++
     show(budget[i]) ++ " / " ++
     show(normalizedPriority[i]) ++ "\n"
     | i in Teams];/* ++
    ["\nFLEXIBLE MATCH HOSTS\n"] ++
    ["match " ++ show(i) ++ "-" ++ show(j) ++ ": team " ++
     show(host[i,j]) ++ "\n"
     | i,j in Teams where i < j /\ pv[i,j] = 3];*/
