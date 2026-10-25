#!/bin/bash
# Completion-aware variant of srun: wait for a unique marker and board exit rc.
set -u
ROOT=${ESP32S31_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: S31_SESSION=name srun-wait.sh 'command' [timeout_seconds]" >&2
    exit 2
fi
export S31_DONE_MARKER=${S31_DONE_MARKER:-__S31_DONE_$$_$RANDOM}
exec bash "$ROOT/tools/srun.sh" "$@"
