# Shared check for a live exclusive lease; sourced by srun and s31-exclusive.
# The owner file supplies the ID, while the actual flock proves liveness.
s31_exclusive_valid() {
    local runtime=$1 owner_file=$1/s31-exclusive.owner board_lock=$1/s31-board.lock
    [ "${S31_BOARD_EXCLUSIVE:-0}" = 1 ] || return 1
    [ -n "${S31_EXCLUSIVE_ID:-}" ] || return 1
    [ -r "$owner_file" ] || return 1
    grep -Fqx "request=$S31_EXCLUSIVE_ID" "$owner_file" || return 1
    exec 6>"$board_lock" || return 1
    if flock -s -n 6; then
        flock -u 6
        exec 6>&-
        return 1
    fi
    exec 6>&-
    return 0
}
