# bynk-dev

Serve a Bynk project locally with `bynk dev`, run a script against it, and shut
it down, or smoke-test every route with `bynk test --smoke`. It is the end-to-end half of a Bynk app's CI: `bynk-ci` shows the
project builds and its unit tests pass, and this shows the running app answers
the way it should.

The action installs Bynk (through [setup-bynk](https://github.com/bynk-lang/setup-bynk))
and Node, starts `bynk dev`, waits until every context answers, runs your
script with the server's addresses in the environment, then stops the server
whether the script passed or not. `bynk dev` runs `wrangler dev` in local
mode, so Workers, Durable Objects, KV and Service Bindings are simulated and
nothing is provisioned.

**It needs Bynk 0.512.9 or later** (setup-bynk v2 installs `bynk` and `bynk-lsp`, not `bynkc`). Pin an earlier bynk-dev release for older Bynk versions.

## Usage

```yaml
name: E2E
on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: bynk-lang/bynk-dev@v1
        with:
          version: 0.377.2
          run: |
            test "$(curl -fsS "$BYNK_DEV_URL/hello/Ada")" = '"Hello, Ada!"'
```

The script runs under `bash -eo pipefail`, so the first failing command fails
the step. On a failure the action prints the last 200 lines of the server log.

A string a handler returns comes back as a JSON string, quotes included.

### Several contexts

`bynk dev` serves every context, wires the Service Bindings between them, and
gives each its own port from `base-port` up, in sorted order. The action reads
the ports from `bynk dev`'s own report, so you do not say how many there are.

```yaml
- uses: bynk-lang/bynk-dev@v1
  with:
    ready-path: /answer   # a route that crosses a Service Binding
    run: |
      test "$(curl -fsS "$BYNK_DEV_URL_SHOP_WEB/orders/1")" = '"placed"'
```

The first call across a Service Binding fails until the binding has connected,
so point `ready-path` at a route that crosses one. The action keeps polling
while it gets a 5xx, and starts your script on the first answer below 500.

### Auth, secrets and cron

Anything after `--` on the `wrangler dev` command line goes in `wrangler-args`:

```yaml
- uses: bynk-lang/bynk-dev@v1
  with:
    wrangler-args: --var AUTH_JWT_SECRET:test-secret --test-scheduled
    run: |
      curl -fsS "$BYNK_DEV_URL/__scheduled?cron=*/5+*+*+*+*"
```

`--var` supplies a secret a `Bearer` or `Signature` actor reads, so the script
can sign its own token. `--test-scheduled` lets you fire a cron handler by hand.

### Smoke-testing every route

`smoke: true` runs `bynk test --smoke --against dev`. It calls every `from http`
route with arguments `Val` fabricates, and needs no script:

```yaml
- uses: bynk-lang/bynk-dev@v1
  id: smoke
  with:
    smoke: true
    smoke-format: json
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: smoke
    path: ${{ steps.smoke.outputs.smoke-report }}
```

A case fails on a 5xx, on a route with a JSON body that accepts a malformed
one, or on a route behind an actor that accepts a call with no credential. The
step fails if any case does. A route whose arguments `Val` cannot fabricate,
such as a `String where Matches(…)` parameter, is skipped and named. The check
stays current as routes are added. See
[Smoke-testing every route](https://bynk-lang.org/docs/bynk-cli/#smoke-testing-every-route)
for what each case sends.

`bynk test --against dev` starts and stops its own `bynk dev`, so under `smoke`:

- **Every context is served**, with the Service Bindings wired. `context`
  narrows the routes called (`--suite`), by their dotted names.
- **Ports and readiness are its own.** `base-port`, `ready-path` and
  `ready-timeout` apply only to `run`.
- **Every declared secret is set to a test value**, which the smoke signs
  with. `wrangler-args` does not reach it. Set alone with `smoke`, it fails
  the step rather than being dropped.

Give `run` as well and the script runs first, against the action's own
`bynk dev`, then the smoke. `smoke` needs a Bynk release with
`bynk test --smoke`; an older one fails the step and says so.

## Inputs

| Input               | Default        | Description |
| ------------------- | -------------- | ----------- |
| `run`               | `""`           | The script to run once the app answers. Give this, `smoke`, or both. |
| `smoke`             | `false`        | `true` runs `bynk test --smoke --against dev`, after `run` if both are given. |
| `smoke-format`      | `rich`         | The smoke's `--format`: `rich`, `json` or `ndjson`. |
| `version`           | `latest`       | Bynk version (forwarded to setup-bynk). |
| `version-file`      | `""`           | A file holding an exact version, such as `BYNK_VERSION`, relative to the workspace. Use this or `version`, not both. |
| `repository`        | `bynk-lang/bynk` | Release repository. |
| `working-directory` | `.`            | Project root, the directory that holds `bynk.toml`. |
| `context`           | empty          | Serve only these contexts (`--context`), whitespace-separated. Empty serves all. |
| `base-port`         | `8787`         | The first context's port (`--base-port`). |
| `wrangler-args`     | empty          | Forwarded to `wrangler dev` after `--`, split on whitespace (no shell quoting). |
| `ready-path`        | `/`            | The path polled on every context's port. Any answer below 500 is ready. |
| `ready-timeout`     | `120`          | Seconds to wait for every context. |
| `node-version`      | `22`           | Node.js for Wrangler. The driver needs 22 or later. |
| `wrangler-version`  | `4`            | Wrangler to install globally first. Empty leaves it to `bynk dev`'s `npx`. |
| `github-token`      | `${{ github.token }}` | Token for setup-bynk. |

## Outputs

| Output         | Value |
| -------------- | ----- |
| `smoke-report` | The file holding the smoke's output, in `smoke-format`, when `smoke` is true. |

## Environment for the script

| Variable | Value |
| -------- | ----- |
| `BYNK_DEV_URL` | The first context's base URL, such as `http://localhost:8787`. |
| `BYNK_DEV_PORTS` | Every served context's port, space-separated, in sorted order. |
| `BYNK_DEV_URL_<WORKER>` | One per context: the worker name upper-cased with `-` and `.` as `_`, such as `BYNK_DEV_URL_SHOP_WEB`. |
| `BYNK_DEV_LOG` | The server log file. |

The first context in sorted order is not necessarily the one with the HTTP
routes, so with more than one context prefer `BYNK_DEV_URL_<WORKER>`.

## Notes

- **`--inspect` is always on.** With two or more contexts, `bynk dev` without it
  starts every `wrangler dev` on the default inspector port at once, and all but
  one die with "Address already in use". `--inspect` gives each its own port.
- **TypeScript is installed for the smoke.** `bynk test` compiles its runner
  with `tsc` (or runs it with `tsx`), so with `smoke` the action installs
  `typescript` globally unless one of them is already on `PATH`.
- **Wrangler is installed up front.** Left to itself, `bynk dev` fetches Wrangler
  with `npx`, and with two or more contexts the parallel installs race in npm's
  cache (`ENOTEMPTY`), so a context dies at boot. Installing it once puts it on
  `PATH`, where `bynk dev` finds it.
- **Teardown kills the process group.** `bynk dev` does not stop its `workerd`
  children when it is signalled on its own, so the action starts it in its own
  process group and signals the group.
- **Mind the baseline.** Pin `version` on pushes and pull requests, so a red
  build means your change broke it. Let the
  [canary](https://github.com/bynk-lang/.github/blob/main/canary/README.md)
  pass a newer one. See the starter workflow there for how a repository's own
  jobs feed its result in as `upstream-result`.

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE) at
your option.
