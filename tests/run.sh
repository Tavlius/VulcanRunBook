#!/bin/sh
# Runs everything: syntax check, lint (addon + tests), and all test suites.
set -e
cd "$(dirname "$0")"
# The suites test the tree this script is in, wherever it is checked out.
RL_DIR="$(cd .. && pwd)/"
export RL_DIR
echo "tools: $(lua5.1 -v 2>&1 | head -1); $(luacheck --version | head -1); $(python3 --version 2>&1); packager $(sha256sum /usr/local/bin/release.sh 2>/dev/null | cut -c1-12 || echo missing)"
for f in ../*.lua ../Libs/LibDeflate/LibDeflate.lua; do luac5.1 -p "$f"; done
luacheck --config ../.luacheckrc -q ../*.lua
luacheck -q --std lua51 --no-max-line-length --allow-defined-top --no-global --no-self harness.lua tests.lua tests_sync.lua tests_round2.lua tests_round3.lua tests_round4.lua tests_round5.lua tests_round6.lua tests_round7.lua tests_round8.lua tests_round9.lua tests_round10.lua tests_round11.lua tests_round12.lua tests_round13.lua tests_round14.lua tests_round15.lua tests_round16.lua tests_round17.lua tests_round18.lua tests_round19.lua tests_round20.lua tests_round21.lua tests_round22.lua tests_round23.lua tests_round24.lua tests_round25.lua tests_il1.lua tests_il1_duo.lua tests_il2.lua tests_il2_duo.lua tests_il3.lua tests_il3_duo.lua tests_group.lua tests_group_duo.lua tests_source.lua tests_persist.lua tests_release.lua
lua5.1 tests.lua
lua5.1 tests_sync.lua
lua5.1 tests_round2.lua
lua5.1 tests_round3.lua
lua5.1 tests_round4.lua
lua5.1 tests_round5.lua
lua5.1 tests_round6.lua
lua5.1 tests_round7.lua
lua5.1 tests_round8.lua
lua5.1 tests_round9.lua
lua5.1 tests_round10.lua
lua5.1 tests_round11.lua
lua5.1 tests_round12.lua
lua5.1 tests_round13.lua
lua5.1 tests_round14.lua
lua5.1 tests_round15.lua
lua5.1 tests_round16.lua
lua5.1 tests_round17.lua
lua5.1 tests_round18.lua
lua5.1 tests_round19.lua
lua5.1 tests_round20.lua
lua5.1 tests_round21.lua
lua5.1 tests_round22.lua
lua5.1 tests_round23.lua
lua5.1 tests_round24.lua
lua5.1 tests_round25.lua
lua5.1 tests_il1.lua
lua5.1 tests_il1_duo.lua
lua5.1 tests_il2.lua
lua5.1 tests_il2_duo.lua
lua5.1 tests_il3.lua
lua5.1 tests_il3_duo.lua
lua5.1 tests_group.lua
lua5.1 tests_group_duo.lua
lua5.1 tests_source.lua
lua5.1 tests_persist.lua
lua5.1 tests_release.lua
# Fuzz a few seeds (more: for s in $(seq 1 200); do lua5.1 fuzz.lua $s 400; done)
for s in 1 2 3 4 5 6 7 8 9 10; do
  r=$(lua5.1 fuzz.lua $s 300 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
for s in 11 12 13 14 15; do
  r=$(SMALLCAP=1 lua5.1 fuzz.lua $s 300 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# The wider fuzzer (wings, raids, marks, partner messages).
for s in 1 2 3 4 5 118; do
  r=$(lua5.1 fuzz2.lua $s 300 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# The instance-cap fuzzer (real copies vs entries counted).
for s in 1 2 3 4 5; do
  r=$(lua5.1 fuzz_cap.lua $s 300 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# The two-client fuzzer: Tavlius and Mirel's clients wired together (boss counts
# agree, partner gold adds up).
for m in events marks anon; do for s in 1 2 3; do
  r=$(lua5.1 fuzz_duo.lua $s 250 $m 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done; done
# (fuzz_duo also checks no kill is timed for a log whose player wasn't there.)
# The same with every message taking a second to arrive (in order), and two
# seconds without /runbook end/start/new (the fuzzer expects those to act at once).
for m in events marks anon; do for s in 1 2 3; do
  r=$(DELAY=2 W_SLASH=0 lua5.1 fuzz_duo.lua $s 250 $m 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done; done
for m in events marks anon; do for s in 1 2 3; do
  r=$(DELAY=1 lua5.1 fuzz_duo.lua $s 250 $m 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done; done
# Partner gold, gain by gain (each gain counts in the other's log iff they had a run then).
for s in 1 2 3 4 5; do
  r=$(lua5.1 fuzz_gold.lua $s 250 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# Partner drops and notes across both logs.
for s in 1 2 3 4 5; do
  r=$(lua5.1 fuzz_drops.lua $s 250 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# Notes on earlier runs across both logs.
for s in 1 2 3 4 5 6 7 8 9 10; do
  r=$(lua5.1 fuzz_notes.lua $s 250 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# Unreadable difficulty, map ID, wing map or name for a few seconds.
for s in 1 2 3 4 5; do
  r=$(lua5.1 fuzz_unread.lua $s 300 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# No run holds kills from two copies of the dungeon (resets that are seen).
for m in events anon marks; do for s in 1 2 3; do
  r=$(NOUNSEEN=1 lua5.1 fuzz_copy.lua $s 300 $m 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done; done
# Fights whose start and kill are unreadable and only their end names the boss
# (an unnamed kill named later is recorded again, under the same tag).
for m in events anon marks late; do for s in 8 14 25 67; do
  r=$(lua5.1 fuzz_duo_late.lua $s 200 $m 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done; done
for s in 1 2 3; do
  r=$(NOUNSEEN=1 lua5.1 fuzz_copy_late.lua $s 200 late 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
  r=$(lua5.1 fuzz2_late.lua $s 2>&1 | tail -1); echo "$r"; case "$r" in *" ok"*) ;; *) exit 1;; esac
done
# Each guard added in round 25 and improvement loop 1 is caught by its test when removed.
python3 mutate_round25.py tests_round25.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il1.py tests_il1.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il1.py tests_il1_duo.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il2.py tests_il2.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il2.py tests_il2_duo.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il3.py tests_il3.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_il3.py tests_il3_duo.lua | tail -1 | grep -q "all mutations caught" || exit 1
python3 mutate_group.py tests_group.lua | tail -1 | grep -q "all mutations caught" || exit 1
echo "mutation checks ok"
python3 guard_personal.py
# Every commit, tag and ref, once this is a git repository (CI always is).
if git rev-parse --git-dir >/dev/null 2>&1; then python3 guard_personal.py --history
elif [ "$GITHUB_ACTIONS" = true ]; then echo "FAIL personal-data guard: running on CI, but the checkout has no git history to check"; exit 1
else echo "personal-data guard: not a git repository yet, so there is no history to check"; fi
sh prepush_test.sh
sh package_test.sh
python3 release_check_test.py
echo "All RunBook tests passed."
exit 0
