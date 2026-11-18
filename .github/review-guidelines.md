# Review guidelines for bynk-dev

These are the maintainers' notes for reviewing a pull request here.
The repository is `bynk-dev`, the action that serves a Bynk project with
`bynk dev`, waits until every context answers, runs a script against it (or
smoke-tests every route with `bynk test --smoke`) and shuts it down. It is the
end-to-end half of a Bynk app's CI.

It's a composite GitHub Action that other repositories pin by commit, so a
mistake here reaches every workflow that uses it, often in a run nobody is
watching. Skip what CI already enforces: the test workflow
(`.github/workflows/test.yml`) across its runners, and the canary at each new
Bynk release.

## What matters most

- **Untrusted input in shell.** An input or a value from the event reaches a
  script through `env:`, and the script quotes it. Flag a new `run:` that
  interpolates `${{ inputs.… }}`, `${{ github.event.… }}` or another
  step's output straight into the command line, where a crafted value
  becomes shell.
- **Pinned dependencies.** Every action this one uses is pinned to a full
  commit SHA, with its version in a comment for Dependabot. Downloaded tools
  are pinned to a version and verified where a checksum is published. Flag a
  floating tag, `@main`, or an unverified download.
- **Tokens and secrets.** A token is used only for the calls that need it,
  never echoed, and a secret value is masked (`::add-mask::`) before anything
  could print it. Flag a token or secret that reaches a log, an output, an
  artefact or a file left in the workspace.
- **Callers rely on the interface.** An input or output that's renamed or
  removed, a default that changes, or behaviour a workflow depends on that
  changes, is a breaking change: it needs a new major version, and the README
  says how to migrate. Flag one slipped into a minor or patch change.
- **Failing loudly.** A step that fails must fail the action, with a message
  that says what to do. `set -euo pipefail` (or its equivalent) stays on, and
  an error isn't swallowed by `|| true` without a reason in a comment.
- **Runners.** It runs on Linux and macOS. A change to a script must work on
  each, with the shells and tools they have (GNU and BSD `sed`, `sha256sum`
  and `shasum`, paths with spaces), or say why it doesn't need to.

## This action

- **Teardown always happens.** The server is stopped whether the script
  passed or not, by signalling its whole process group, so no `workerd`
  child outlives the action. Flag a path that can leave a server running or
  a port held.
- **Readiness.** The script starts only once every context answers on
  `ready-path`, within `ready-timeout`; a timeout fails with the server's
  log. Flag a change that can start the script early.
- **The script's environment.** `BYNK_DEV_URL`, `BYNK_DEV_PORTS`,
  `BYNK_DEV_URL_<WORKER>` and `BYNK_DEV_LOG` are part of the interface, as
  the README's table has them.
- **The workarounds in the README's Notes** (`--inspect`, Wrangler installed
  up front, the process group) are there for a reason. A change that drops
  one says why it's no longer needed.

## Tests

- A change of behaviour comes with a case in the test workflow, against the
  fixtures in `test/`: the success, and the failure it should report.
- Look for missing cases: an input left empty, an input that's invalid, a
  version that doesn't exist, a failing command in the middle, and each
  runner the change touches.

## Documentation and versions

- The README is the action's documentation. A new or changed input, output,
  default or behaviour updates its table or section in the same pull request,
  and the usage examples stay pinned by commit, with the version in a comment.
- `BYNK_VERSION` is moved by the org canary's pull request, once the tests
  pass at the new release. A hand-edited pin needs a reason.
- British English throughout: in comments, the README and messages the action
  prints ("behaviour", "organisation", "licence" as a noun).

## Severity here

- **Blocking:** a server or child process left running, untrusted input
  reaching a shell, a token or secret exposed, an unpinned or unverified
  dependency, or a breaking change without a new major version.
- **Should fix:** a missing test case, a failure that's swallowed or
  explained badly, a runner left broken, or a README out of step with
  `action.yml`.
- **Nit:** wording, naming and small style points. Keep these few.
