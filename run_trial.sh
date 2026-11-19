#!/bin/bash
# run_trial.sh <trial> [main.py path]
# Runs one practice trial against the env server and scores it.
# Usage: run_trial.sh 0
#        run_trial.sh 1 /path/to/main.py
set -u
KIT=/home/hatch/workspace/makefun-agent/bounties/tiny-chess-01-kit
TRIAL=${1:-0}
MAINPY=${2:-/home/hatch/workspace/makefun-agent/bounties/tiny-chess-engine/main.py}
WORK=/tmp/tiny-chess-trial-$TRIAL
rm -rf "$WORK"
mkdir -p "$WORK/state" "$WORK/scores"
PORT=$(( 8080 + TRIAL ))

echo "=== trial $TRIAL, engine: $MAINPY ==="
echo "=== starting env server on port $PORT ==="
MAKEFUN_ENV_DATA_DIR="$KIT/practice/trial-$TRIAL/input/env" \
MAKEFUN_STATE_DIR="$WORK/state" \
MAKEFUN_ENV_PORT="$PORT" \
MAKEFUN_ENV_HOST="127.0.0.1" \
node "$KIT/program/env/server.mjs" > "$WORK/env.log" 2>&1 &
ENV_PID=$!
# wait for ready file
for i in $(seq 1 30); do
  [ -f "$WORK/state/ready" ] && break
  sleep 0.5
done
if [ ! -f "$WORK/state/ready" ]; then
  echo "ERROR: env server did not become ready"
  cat "$WORK/env.log"
  kill $ENV_PID 2>/dev/null
  exit 1
fi
echo "env ready: $(cat "$WORK/state/ready")"

echo "=== running engine (timeout 1750s) ==="
cd "$(dirname "$MAINPY")"
START=$(date +%s)
MAKEFUN_ENV_URL="http://127.0.0.1:$PORT" \
MAKEFUN_TRIAL_SEED="practice-$TRIAL" \
timeout 1750 python3 "$MAINPY" > "$WORK/engine.log" 2> "$WORK/engine.err"
RC=$?
END=$(date +%s)
echo "engine exit: $RC, wall: $((END-START))s"
cat "$WORK/engine.err"

echo "=== stopping env server (writes export/state.json) ==="
kill -TERM $ENV_PID 2>/dev/null
sleep 2
kill -9 $ENV_PID 2>/dev/null
ls -la "$WORK/state/export/" 2>&1

echo "=== scoring ==="
MAKEFUN_OUTPUT_DIR="$WORK/state/export" \
MAKEFUN_REFERENCE_DIR="$KIT/practice/trial-$TRIAL/reference" \
MAKEFUN_SCORES_DIR="$WORK/scores" \
node "$KIT/program/scorer/score.mjs"
echo ""
echo "scores.json:"
cat "$WORK/scores/scores.json" 2>&1
echo ""
echo "work dir: $WORK"
