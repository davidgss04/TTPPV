import os
import re
import subprocess
import sys
import tempfile

MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "TTPFVHBTDMBSA-BA.mzn")
SOLVER = "gecode"
TIME_LIMIT_MS = 60000
VENUE_CODES = {"home": 1, "away": 2, "UND": 3}
LINE = "=" * 40


# ------------------------- Input to .dzn --------------------------

def dzn_array(values):
    return "[" + ", ".join(values) + "]"


def dzn_matrix(rows):
    return "[|\n  " + " |\n  ".join(", ".join(row) for row in rows) + " |]"


def build_dzn(text):
    blocks = re.split(r"\n\s*\n", text.strip())

    n = int(blocks[0])
    pv = [[str(VENUE_CODES[v]) for v in row.split()] for row in blocks[1].splitlines()]
    cost = blocks[2].split()
    distance = [row.split() for row in blocks[3].splitlines()]
    budget = blocks[4].split()

    # Every stadium is open except the "team,round" pairs in the optional block
    available = [["true"] * (n - 1) for _ in range(n)]
    if len(blocks) > 5:
        for pair in blocks[5].split():
            team, rnd = map(int, pair.split(","))
            available[team - 1][rnd - 1] = "false"

    return (f"nbTeams = {n};\n"
            f"pv = {dzn_matrix(pv)};\n"
            f"cost_per_unit_of_distance = {dzn_array(cost)};\n"
            f"distance = {dzn_matrix(distance)};\n"
            f"budget = {dzn_array(budget)};\n"
            f"available = {dzn_matrix(available)};\n")


# --------------------------- MiniZinc -----------------------------

def run_minizinc(dzn):
    with tempfile.NamedTemporaryFile("w", suffix=".dzn", delete=False) as f:
        f.write(dzn)
    try:
        return subprocess.run(
            ["minizinc", "--solver", SOLVER, "--time-limit", str(TIME_LIMIT_MS), MODEL, f.name],
            capture_output=True, text=True)
    finally:
        os.remove(f.name)


# ------------------------ Output to report ------------------------

def format_report(stdout):
    schedule, totals, stats = stdout.split("----------")[0].strip().split("\n\n")

    out = ["GAME SCHEDULE:", LINE]
    for team, row in enumerate(schedule.splitlines(), 1):
        out.append(f"Team {team}:")
        for game in row.split():
            where = "away" if game.startswith("@") else "at home"
            out.append(f"  - vs Team {game.lstrip('@')}, {where}")
        out.append(LINE)

    out += ["", "TEAM TRAVEL DISTANCE AND EXPENSES:", LINE]
    for team, row in enumerate(stats.splitlines(), 1):
        distance, spent, budget, priority = row.split("\t")
        out += [f"Team {team}:",
                f"  Distance travelled: {distance}",
                f"  Amount spent: {spent}",
                f"  Initial budget: {budget}",
                f"  Travel priority: {priority}",
                LINE]

    total_distance, total_expense = totals.splitlines()
    out += ["", "OVERALL STATS:",
            f"Total travelled distance: {total_distance}",
            f"Total travel expenses: {total_expense}"]
    return "\n".join(out)


def main():
    sys.stdin.reconfigure(encoding="utf-8-sig")
    result = run_minizinc(build_dzn(sys.stdin.read()))

    if result.returncode != 0:
        sys.exit("MiniZinc error:\n" + result.stderr)
    if "=====UNSATISFIABLE=====" in result.stdout:
        print("No valid schedule exists for this instance")
        return

    # Time limit ran out before any schedule was found
    if "=====UNKNOWN=====" in result.stdout:
        print(f"No schedule found within {TIME_LIMIT_MS // 1000} seconds")
        return

    print(format_report(result.stdout))

    if "==========" not in result.stdout:
        print("\nTime limit reached: best schedule found, not proven optimal")


if __name__ == "__main__":
    main()
