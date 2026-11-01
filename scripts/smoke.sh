#!/usr/bin/env bash
# Smoke-test every `from http` route with `bynk test --smoke --against dev`,
# which starts and stops its own `bynk dev`. Configured by INPUT_* environment
# variables set from action.yml. See README.md.
set -euo pipefail

workdir="${INPUT_WORKING_DIRECTORY:-.}"
format="${INPUT_SMOKE_FORMAT:-rich}"
tmp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

die() { echo "::error::bynk-dev: $*" >&2; exit 2; }

case "$format" in
  rich) ext=txt ;;
  json | ndjson) ext=$format ;;
  *) die "smoke-format must be rich, json or ndjson, got '$format'" ;;
esac
report="${INPUT_REPORT_FILE:-$tmp/bynk-smoke.$ext}"
# `--against dev` starts `bynk dev` itself, on ports it picks, and passes it
# only a test value for each declared secret. Nothing else can reach it, so
# wrangler-args with no run script is a mistake, not something to drop.
[ -n "${INPUT_RUN:-}" ] || [ -z "${INPUT_WRANGLER_ARGS:-}" ] \
  || die "wrangler-args does not reach the smoke: \`bynk test --against dev\` starts its own \`bynk dev\` and sets every declared secret to a test value. Leave wrangler-args empty, or give a run script for it to apply to"

if ! bynk test --help 2>/dev/null | grep -q -- '--smoke'; then
  die "smoke needs a Bynk release with \`bynk test --smoke\` (bynk-lang/bynk#2666); $(bynk --version 2>/dev/null || echo 'this bynk') does not have it"
fi

# A smoke suite is named after its context, so `context` narrows by suite.
# `bynk dev` still serves every context, so the Service Bindings are wired.
args=(test . --smoke --against dev --format "$format" --output "$tmp/bynk-smoke-out")
for c in ${INPUT_CONTEXT:-}; do args+=(--suite "$c"); done

cd "$workdir"
echo "bynk ${args[*]}"
set +e
bynk "${args[@]}" | tee "$report"
status=${PIPESTATUS[0]}
set -e

if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "smoke-report=$report" >>"$GITHUB_OUTPUT"; fi
if [ "$status" -ne 0 ]; then
  echo "::error::the smoke failed (bynk test exited with status $status)" >&2
fi
exit "$status"
