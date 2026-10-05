# Mutation sweep (tests/sweep)

A broad check of how much behaviour the suites pin down: small mechanical changes
("mutants") to the addon, each run against every tests*.lua suite. Not part of run.sh
(an hour or more for 600 mutants on two cores).

    rm -rf /tmp/rl_snap && cp -r ../../RunBook /tmp/rl_snap        # (a fixed copy to mutate)
    SWEEP_SRC=/tmp/rl_snap python3 gen.py 3 600                   # seed, count -> mutants.json
    SWEEP_SRC=/tmp/rl_snap J=2 python3 run_mutants.py             # -> results.jsonl (resumable)
    python3 report.py                                             # survival by file, function, operator

A surviving mutant is either equivalent (can't change behaviour), dead code, or behaviour
no test checks. The first sweep (improvement loop 3, audit 1) and the re-run after its fixes
are summarised in ../../AUDIT_REPORT.md.
