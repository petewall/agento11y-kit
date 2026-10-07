SPEC       ?= spec.yaml
TAG        ?= 0.1.0
# Registry/name to publish the kit under. Override for your own fork:
#   make push IMAGE=ghcr.io/<you>/sbx-agento11y-kit:0.1.0
IMAGE      ?= ghcr.io/petewall/sbx-agento11y-kit:$(TAG)
# The v3 workload kits the mixin layers onto (a mixin can't be the base).
# Each is pinned to the newest tag the local sbx can decode — newer tags carry
# capabilities (e.g. agent-sessions@1) the CLI doesn't know yet and fail with
# "field name not found in type spec.plain". Re-check and bump when sbx is
# upgraded: `sbx kit inspect docker/sbx-kit-<agent>:latest`.
CLAUDE_BASE ?= docker/sbx-kit-claude:2.1.278   # 2.1.285+/latest fail on sbx 0.47.0
CODEX_BASE  ?= docker/sbx-kit-codex:0.159.2    # 0.160.0+ fail on sbx 0.47.0

# Kit + args shared by every run-* target (needs AGENTO11Y_ENDPOINT and
# AGENTO11Y_AUTH_TENANT_ID in the environment; see .envrc).
KIT_ARGS = --kit $(IMAGE) \
	--kit-arg agento11y_endpoint=$(AGENTO11Y_ENDPOINT) \
	--kit-arg agento11y_otlp_endpoint=$(AGENTO11Y_OTLP_ENDPOINT) \
	--kit-arg agento11y_tenant_id="$(AGENTO11Y_AUTH_TENANT_ID)"

# Explicit, stable sandbox names. NOTE: `--kit` only applies when creating a
# new sandbox — if one of these already exists, `sbx rm <name>` it first (or
# re-attach without --kit via `sbx run --name <name>`).
CLAUDE_SANDBOX ?= agento11y-claude
CODEX_SANDBOX  ?= agento11y-codex

.DEFAULT_GOAL := help
.PHONY: help validate build push set-token run-claude run-codex clean

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

validate: ## Build the descriptor through the frontend without producing an artifact (fast check)
	docker buildx build --output type=cacheonly -f $(SPEC) .

build: dist/sbx-agento11y-kit-$(TAG).oci ## Build a local OCI artifact under dist/ (no registry needed)
dist/sbx-agento11y-kit-$(TAG).oci: $(SPEC)
	@mkdir -p dist
	docker buildx build --output type=oci,dest=$@ -f $< .
	@echo "built $@"

PLATFORMS ?= linux/amd64,linux/arm64
push: $(SPEC) ## Build multi-platform with attestations and push to $(IMAGE)
	docker buildx build --push -t $(IMAGE) -f $< --provenance=true --sbom=true --platform=$(PLATFORMS) .
	@echo "pushed $(IMAGE)"

set-token: ## Store AGENTO11Y_ACCESS_TOKEN as the agento11y-token sbx secret
	@test -n "$$AGENTO11Y_ACCESS_TOKEN" || { echo "AGENTO11Y_ACCESS_TOKEN must be set" >&2; exit 1; }
	@printf '%s' "$$AGENTO11Y_ACCESS_TOKEN" | sbx secret set agento11y-token

run-claude: ## Run the mixin on the v3 claude workload
	sbx run --name $(CLAUDE_SANDBOX) $(CLAUDE_BASE) . $(KIT_ARGS)

run-codex: ## Run the mixin on the v3 codex workload
	sbx run --name $(CODEX_SANDBOX) $(CODEX_BASE) . $(KIT_ARGS)

clean: ## Remove built local artifacts
	rm -rf dist
