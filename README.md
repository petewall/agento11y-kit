# agento11y sandbox kit

<p>
  <img src="assets/docker.svg" alt="Docker" height="44">
  &nbsp;&nbsp;+&nbsp;&nbsp;
  <img src="assets/grafana.svg" alt="Grafana" height="44">
</p>

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) (`sbx`) **mixin kit**
(schema v3) that adds [Grafana Agent Observability](https://github.com/grafana/agento11y)
(agento11y) capture to a coding-agent sandbox. It installs the `agento11y`
binary at container startup, wires the agent so its sessions are exported, and
injects the Grafana Cloud credential **at the proxy** — so the raw token never
has to live in the container environment.

It's a `mixin`, so it layers onto a **workload** kit (e.g.
`docker/sbx-kit-claude`, `docker/sbx-kit-codex`).

## Agent support

| Agent | Captured | Mechanism |
|---|---|---|
| Claude Code | ✅ | `agento11y claude install` hook in `~/.claude` |
| Codex | ✅ | root install-hook that wraps the `codex` binary → `agento11y codex -- …` |
| opencode, cursor | ☑️ best-effort | `agento11y <agent> install` hook (if present on PATH) |
| copilot, pi, vibe | ❌ | not wired by this kit |

## Prerequisites

- **`sbx`** (Docker Sandboxes CLI) — `sbx version`.
- **Docker with `buildx`** — v3 kits are built by the `docker/sandbox-kit:3`
  BuildKit frontend.
- **A container registry** you can push to (e.g. `ghcr.io/<you>`).
- **A Grafana Cloud agento11y token.** For conversations it needs the
  `sigil:write` scope; for the OTLP/analytics pipeline also `metrics:write` +
  `traces:write`. You'll also need the stack/instance id and the endpoints.

## 1. Store the token

`scheme: basic` uses the secret as the HTTP Basic **password**, so store the
**raw** `glc_…` token (not a base64 blob) under the service `agento11y-token`:

```sh
printf '%s' "<glc_token>" | sbx secret set agento11y-token
```

The proxy builds `Authorization: Basic base64("<tenant>:<token>")` and injects
it for the Grafana hosts; the token is never passed to the agent as a value.

## 2. Build & push the kit

```sh
make push                               # → ghcr.io/petewall/sbx-agento11y-kit:0.1.0
# or publish under your own registry:
make push IMAGE=ghcr.io/<you>/sbx-agento11y-kit:0.1.0
```

If the pushed package is **private**, give the sbx daemon a pull credential
(it pulls kit images with its own creds, anonymously by default):

```sh
gh auth token | sbx secret set --registry ghcr.io --username <you> --password-stdin
```

## 3. Run

Export the instance-specific values (or use [direnv](https://direnv.net/) +
`.envrc`), then launch:

```sh
export AGENTO11Y_ENDPOINT=https://agento11y-prod-us-east-0.grafana.net
export AGENTO11Y_AUTH_TENANT_ID=<stack-id>
export AGENTO11Y_OTLP_ENDPOINT=https://otlp-gateway-prod-us-east-2.grafana.net/otlp  # optional

make run-claude     # claude workload + agento11y mixin
make run-codex      # codex workload  + agento11y mixin
```

Inside the sandbox, confirm with `agento11y doctor` (expect `✓ Conversations`,
and `✓ Analytics` if the OTLP endpoint + scopes are set).

The equivalent raw command (what the Makefile runs):

```sh
sbx run docker/sbx-kit-claude:2.1.278 . \
  --kit ghcr.io/petewall/sbx-agento11y-kit:0.1.0 \
  --kit-arg agento11y_endpoint=$AGENTO11Y_ENDPOINT \
  --kit-arg agento11y_tenant_id=$AGENTO11Y_AUTH_TENANT_ID
```

## Configuration

All args are namespaced `agento11y_*` so a global `--kit-arg` can't collide
with the base workload's args. (v3 arg names can't contain hyphens, hence
snake_case.)

| Arg (`--kit-arg`) | Env exported | Default | Purpose |
|---|---|---|---|
| `agento11y_endpoint` | `AGENTO11Y_ENDPOINT` | — (required) | Conversations API URL |
| `agento11y_tenant_id` | `AGENTO11Y_AUTH_TENANT_ID` | — (required) | Grafana Cloud stack/instance id |
| `agento11y_otlp_endpoint` | `AGENTO11Y_OTEL_EXPORTER_OTLP_ENDPOINT` | — (optional) | OTLP endpoint for metrics/traces |
| `agento11y_version` | — | `latest` | agento11y release to install |
| `agento11y_protocol` | `AGENTO11Y_PROTOCOL` | `http` | Client transport |
| `agento11y_auth_mode` | `AGENTO11Y_AUTH_MODE` | `basic` | Auth mode |
| `agento11y_content_capture_mode` | `AGENTO11Y_CONTENT_CAPTURE_MODE` | `full` | Capture scope |
| `agento11y_tags` | `AGENTO11Y_TAGS` | `sandbox=sbx` | Low-cardinality client tags |

The `agento11y-token` secret supplies the credential; it is injected at the
proxy, never passed as a kit-arg.

> `agento11y_content_capture_mode=full` forwards complete prompt + tool content
> to Grafana, including anything sensitive that surfaces in a transcript. Use
> `no_tool_content` / `metadata_only` for stricter environments.

## Development

```sh
make validate     # build the descriptor through the frontend (no push)
make build        # produce a local OCI artifact under dist/
make clean        # remove dist/
make help         # list targets
```

## Notes & caveats

- **Workload base tags are pinned** (`CLAUDE_BASE`, `CODEX_BASE` in the
  Makefile) to the newest tags the local `sbx` can decode — newer workload
  tags can carry capabilities the installed CLI doesn't understand yet and fail
  with `field name not found in type spec.plain`. Re-check with
  `sbx kit inspect docker/sbx-kit-<agent>:latest` after upgrading `sbx`.
- **Codex self-update** overwrites the wrapped binary, so capture is lost until
  the sandbox is recreated (codex still runs — just unobserved).
- **OTLP** uses the same tenant id as conversations here; if Grafana Cloud
  assigns your OTLP endpoint a different instance id, analytics will 401 even
  when conversations succeed.

## License

[Apache License 2.0](./LICENSE).
