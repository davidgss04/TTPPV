
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

% 1 = team i hosts, 2 = team j hosts
% 3 = flexible, the host will decide
array[Teams,Teams] of 1..3: pv;

% Distance between each pair of stadiums
array[Teams,Teams] of int: distance;

% How much each team pays per unit of distance travelled
array[Teams] of int: cost_per_unit_of_distance;

% Most each team can spend on travel
array[Teams] of int: budget;

% False if team i's stadium is closed in round k
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
% Opponent of team i in round k
array[Teams,Rounds] of var Teams: opponent;

% Which team hosts the match between i and j
array[Teams,Teams] of var Teams: host;

% Whether team i plays at home (1) or away (2) in round k
array[Teams,Rounds] of var 1..2: venue;

% Distance of each trip: to round 1, between rounds, and back home
array[Teams,Travels] of var 0..maxDistance: travel;

% Total distance and money spent by each team
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

% Each team should play +- half its games at home and half away
constraint forall(i in Teams)(
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        >= nbRounds div 2 /\
    sum(j in Teams where j != i)(bool2int(host[i,j] = i))
        <= (nbRounds + 1) div 2
);

% No team may host when its stadium is unavailable
constraint forall(i in Teams, k in Rounds)(
    not available[i,k] -> venue[i,k] = 2
);

% ----------------------- Round-robin constraints ------------------------
% No team plays itself, opponents match up, every team meets every
% other team once, and each round pairs everyone up
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

% At most three home or three away games in a row
% The table counts the current streak, 0 means the streak got too long
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


% ---------------------- Travel calculation ------------------------
% Every team starts at home before round 1
constraint forall(i in Teams)(
    (venue[i,1] = 1 -> travel[i,1] = 0) /\
    (venue[i,1] = 2 -> travel[i,1] = distance[i,opponent[i,1]])
);

% Teams go straight from one match to the next without going home
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

% Return home after the final round
constraint forall(i in Teams)(
    (venue[i,nbRounds] = 1 -> travel[i,nbRounds+1] = 0) /\
    (venue[i,nbRounds] = 2 ->
        travel[i,nbRounds+1] = distance[opponent[i,nbRounds],i])
);

% Money spent = distance x the teams own cost per unit. it must fit the budget
constraint forall(i in Teams)(
    teamDistance[i] = sum(k in Travels)(travel[i,k]) /\
    teamExpense[i] = cost_per_unit_of_distance[i] * teamDistance[i] /\
    teamExpense[i] <= budget[i]
);

% ----------------- Automatic team priorities ---------------------
% Teams that spend a lot per km compared to their budget get a higher weight
% the solver tries harder to keep their travel short

% Weight = 1 + (team's cost per km / budget) compared to the average team

% Greatest common divisor
function int: gcd_pos(int: a, int: b) =
    if b = 0 then a else gcd_pos(b, a mod b) endif;

function int: lcm_budget_prefix(int: k) =
    if k = 1 then budget[1]
    else let { int: prev = lcm_budget_prefix(k-1) } in
        (prev div gcd_pos(prev, budget[k])) * budget[k]
    endif;

% Smallest number every budget divides into evenly
int: lcmBudget = lcm_budget_prefix(nbTeams);

% Cost per km divided by budget, scaled up to a whole number
array[Teams] of int: sensitivityNumerator =
    [cost_per_unit_of_distance[i] * (lcmBudget div budget[i])
     | i in Teams];
int: totalSensitivityNumerator = sum(sensitivityNumerator);

% Each team's weight, before simplifying
array[Teams] of int: coefficientNumerator =
    [totalSensitivityNumerator + nbTeams * sensitivityNumerator[i]
     | i in Teams];

function int: gcd_coefficient_prefix(int: k) =
    if k = 1 then coefficientNumerator[1]
    else gcd_pos(gcd_coefficient_prefix(k-1), coefficientNumerator[k])
    endif;

int: coefficientGCD = gcd_coefficient_prefix(nbTeams);

% Final weights divided down to the smallest whole numbers
array[Teams] of int: priorityCoefficient =
    [coefficientNumerator[i] div coefficientGCD | i in Teams];

% Same weights as decimals for display only
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

% Host of each match
array[int] of var Teams: matchHost = [host[i,j] | i,j in Teams where i < j];

% Search the schedule first, then the hosts, everything else follows
solve :: seq_search([
    int_search(opponent,  first_fail,  indomain_min),
    int_search(matchHost, input_order, indomain_min)
]) minimize budgetAwareObjective;

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
     show_float(0, 2, normalizedPriority[i]) ++ "\n"
     | i in Teams];