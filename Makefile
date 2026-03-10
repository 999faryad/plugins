.DEFAULT_GOAL := all

SHELL := /usr/bin/env bash -o pipefail
TMP := .tmp
DOCKER ?= docker
DOCKER_ORG ?= bufbuild
DOCKER_BUILD_EXTRA_ARGS ?=
DOCKER_BUILDER := bufbuild-plugins
DOCKER_CACHE_DIR ?= $(TMP)/dockercache
GO ?= go
GOLANGCI_LINT_VERSION ?= v2.9.0
GOLANGCI_LINT := $(TMP)/golangci-lint-$(GOLANGCI_LINT_VERSION)

GO_TEST_FLAGS ?= -race -count=1

BUF ?= buf
BUF_PLUGIN_PUSH_ARGS ?= --visibility=public

# GHCR settings - override GHCR_OWNER with your GitHub username/org
GHCR_OWNER ?= $(shell git config user.name 2>/dev/null)
GHCR_REGISTRY := ghcr.io
GHCR_ORG := $(GHCR_REGISTRY)/$(GHCR_OWNER)

# Specify a space or comma separated list of plugin name (and optional version) to build/test individual plugins.
# For example:
# $ make PLUGINS="connectrpc/go connectrpc/es" # builds all versions of connect-go and connect-es plugins
# $ make PLUGINS="connectrpc/go:v1.12.0"       # builds connect-go v1.12.0 plugin
# $ make PLUGINS="all:latest"                   # builds only the latest version of every plugin
export PLUGINS ?=

PLUGIN_YAML_FILES := $(shell PLUGINS="$(PLUGINS)" go run ./internal/cmd/dependency-order -relative . 2>/dev/null)

.PHONY: all
all: build

.PHONY: build
build:
ifeq ($(PLUGINS),)
	@echo "No plugins specified to build with PLUGINS env var."
	@echo "See Makefile for example PLUGINS env var usage."
else
	docker buildx inspect "$(DOCKER_BUILDER)" 2> /dev/null || docker buildx create --use --bootstrap --name="$(DOCKER_BUILDER)" > /dev/null
	$(GO) run ./internal/cmd/dockerbuild -cache-dir "$(DOCKER_CACHE_DIR)" -org "$(DOCKER_ORG)" -- $(DOCKER_BUILD_EXTRA_ARGS) || \
		(docker buildx rm "$(DOCKER_BUILDER)"; exit 1)
	docker buildx rm "$(DOCKER_BUILDER)" > /dev/null
endif

.PHONY: lint
lint: $(GOLANGCI_LINT)
	$(GOLANGCI_LINT) run --timeout=5m
	$(GOLANGCI_LINT) fmt --diff

.PHONY: lintfix
lintfix: $(GOLANGCI_LINT)
	$(GOLANGCI_LINT) run --timeout=5m --fix
	$(GOLANGCI_LINT) fmt


$(GOLANGCI_LINT):
	GOBIN=$(abspath $(TMP)) $(GO) install -ldflags="-s -w" github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)
	ln -sf $(abspath $(TMP))/golangci-lint $@

.PHONY: dockerpush
dockerpush:
	@$(GO) run ./internal/cmd/dockerpush -org "$(DOCKER_ORG)"

.PHONY: test
test: build
	$(GO) test $(GO_TEST_FLAGS) ./...

.PHONY: push
push: build
	for plugin in $(PLUGIN_YAML_FILES); do \
		plugin_dir=`dirname $${plugin}`; \
		PLUGIN_FULL_NAME=`yq '.name' $${plugin_dir}/buf.plugin.yaml`; \
		PLUGIN_OWNER=`echo "$${PLUGIN_FULL_NAME}" | cut -d '/' -f 2`; \
		PLUGIN_NAME=`echo "$${PLUGIN_FULL_NAME}" | cut -d '/' -f 3-`; \
		PLUGIN_VERSION=`yq '.plugin_version' $${plugin_dir}/buf.plugin.yaml`; \
		echo "Pushing plugin: $${plugin}"; \
		if [[ "$(DOCKER_ORG)" = "ghcr.io/bufbuild" ]]; then \
			$(DOCKER) pull $(DOCKER_ORG)/plugins-$${PLUGIN_OWNER}-$${PLUGIN_NAME}:$${PLUGIN_VERSION} || exit 1; \
		fi; \
		$(BUF) beta registry plugin push $${plugin_dir} $(BUF_PLUGIN_PUSH_ARGS) --image $(DOCKER_ORG)/plugins-$${PLUGIN_OWNER}-$${PLUGIN_NAME}:$${PLUGIN_VERSION} || exit 1; \
	done

.PHONY: clean
clean:
	rm -rf $(TMP)

.PHONY: ghcr-login
ghcr-login:
ifndef GHCR_TOKEN
	$(error GHCR_TOKEN is not set. Create a PAT at https://github.com/settings/tokens with write:packages scope)
endif
	@echo "$(GHCR_TOKEN)" | $(DOCKER) login $(GHCR_REGISTRY) -u "$(GHCR_OWNER)" --password-stdin

.PHONY: ghcr-build-latest
ghcr-build-latest:
	docker buildx inspect "$(DOCKER_BUILDER)" 2> /dev/null || docker buildx create --use --bootstrap --name="$(DOCKER_BUILDER)" > /dev/null
	PLUGINS="all:latest" $(GO) run ./internal/cmd/dockerbuild -cache-dir "$(DOCKER_CACHE_DIR)" -org "$(GHCR_ORG)" -- $(DOCKER_BUILD_EXTRA_ARGS) || \
		(docker buildx rm "$(DOCKER_BUILDER)"; exit 1)
	docker buildx rm "$(DOCKER_BUILDER)" > /dev/null

.PHONY: ghcr-push-latest
ghcr-push-latest:
	@PLUGINS="all:latest" $(GO) run ./internal/cmd/dockerpush -org "$(GHCR_ORG)"

.PHONY: ghcr-release-latest
ghcr-release-latest: ghcr-login ghcr-build-latest ghcr-push-latest

