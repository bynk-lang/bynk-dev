#!/usr/bin/env bash
# Boot `bynk dev`, wait until it answers, run the caller's script against it,
# and tear everything down. Configured by INPUT_* environment variables set
# from action.yml. See README.md.
set -euo pipefail

: "${INPUT_RUN:?the run input is required}"
workdir="${INPUT_WORKING_DIRECTORY:-.}"
base_port="${INPUT_BASE_PORT:-8787}"
ready_path="${INPUT_READY_PATH:-/}"
ready_timeout="${INPUT_READY_TIMEOUT:-120}"
tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
log="${INPUT_LOG_FILE:-$tmp/bynk-dev.log}"

case "$base_port" in '' | *[!0-9]*) echo "::error::base-port must be an integer, got '$base_port'" >&2; exit 2 ;; esac
case "$ready_timeout" in '' | *[!0-9]*) echo "::error::ready-timeout must be an integer, got '$ready_timeout'" >&2; exit 2 ;; esac

# --inspect gives each context its own inspector port. Without it, every
# wrangler asks for the default 9229 at once, and with two or more contexts
# the losers die with "Address already in use".
args=(--base-port "$base_port" --inspect)
# Whitespace-separated, no shell quoting (as bynk-deploy's extra-args).
for c in ${INPUT_CONTEXT:-}; do args+=(--context "$c"); done
if [ -n "${INPUT_WRANGLER_ARGS:-}" ]; then
  args+=(--)
  # shellcheck disable=SC2206
  args+=(${INPUT_WRANGLER_ARGS})
fi

# Job control makes the background job its own process group, so the whole
# tree (bynk, wrangler and the workerd children) can be signalled together.
# `bynk dev` does not reap workerd when it is signalled on its own.
set -m
cd "$workdir"
: >"$log"
bynk dev "${args[@]}" >"$log" 2>&1 </dev/null &
dev_pid=$!

stopped=false
stop() {
  $stopped && return
  stopped=true
  kill -TERM -- "-$dev_pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$dev_pid" 2>/dev/null || return 0
    sleep 1
  done
  kill -KILL -- "-$dev_pid" 2>/dev/null || true
}
trap stop EXIT

show_log() {
  echo "::group::bynk dev log"
  tail -n 200 "$log" || true
  echo "::endgroup::"
}

# Ready is any answer below 500: a 404 or 401 means the server is up. A 5xx
# or no answer means not yet, which also covers the first call across a
# Service Binding, which fails until the binding has connected.
answers() {
  local code
  code=$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' "http://localhost:$1$ready_path") || return 1
  [ "$code" -ge 100 ] && [ "$code" -lt 500 ]
}

# `bynk dev` reports the contexts it serves, one `<worker>  http://localhost:<port>`
# line each, before wrangler starts. Read the ports from there, so the caller
# need not say how many contexts there are.
deadline=$((SECONDS + ready_timeout))
fail() {
  echo "::error::$1" >&2
  show_log
  exit 1
}
check_alive() { kill -0 "$dev_pid" 2>/dev/null || fail "bynk dev exited before it was ready"; }
check_time() { ((SECONDS < deadline)) || fail "$1 within ${ready_timeout}s"; }

until grep -q '^bynk dev: serving' "$log"; do
  check_alive
  check_time "bynk dev did not report the contexts it serves"
  sleep 1
done

ports=()
urls=()
while read -r worker port; do
  ports+=("$port")
  var="BYNK_DEV_URL_$(printf '%s' "$worker" | tr 'a-z-.' 'A-Z__')"
  urls+=("$var=http://localhost:$port")
done < <(sed -n 's|^  \([^ ][^ ]*\)  *http://localhost:\([0-9][0-9]*\)$|\1 \2|p' "$log")
if [ "${#ports[@]}" -eq 0 ]; then ports=("$base_port"); fi

for port in "${ports[@]}"; do
  until answers "$port"; do
    check_alive
    check_time "nothing answered on port $port"
    sleep 1
  done
done
echo "bynk dev is ready (${#ports[@]} context(s); ports ${ports[*]})"

script="$tmp/bynk-dev-run.sh"
printf '%s\n' "$INPUT_RUN" >"$script"
set +e
env ${urls[@]+"${urls[@]}"} \
  BYNK_DEV_URL="http://localhost:${ports[0]}" \
  BYNK_DEV_PORTS="${ports[*]}" \
  BYNK_DEV_LOG="$log" \
  bash -eo pipefail "$script"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "::error::the run script exited with status $status" >&2
  show_log
fi
exit "$status"
