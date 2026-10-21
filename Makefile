GO ?= go

project := appium-agent
default-version := $(shell $(GO) tool over < semver.ascii)
resolved-version := $(or $(version),$(default-version))
build-output-dir := $(CURDIR)/bin
install-prefix := $(or $(FSDS_PREFIX),/opt/fsds)
build-install-dir := $(install-prefix)/bin
ldflags := -X main.Version=$(resolved-version)

.PHONY: all build appium-agent install check deploy version clean

all: build

appium-agent: build

build:
	$(GO) build -trimpath -ldflags "$(ldflags)" -o "$(build-output-dir)/$(project)" .

install: build
	install -d "$(build-install-dir)"
	install -m 0755 "$(build-output-dir)/$(project)" "$(build-install-dir)/$(project)$(resolved-version)"
	ln -sfn "$(project)$(resolved-version)" "$(build-install-dir)/$(project)"

check:
	$(GO) test ./...
	$(GO) vet ./...
	@for script in run/libexec/*.zsh; do zsh -n "$$script" || exit; done
	@for test in run/libexec/*_test.zsh; do zsh "$$test" || exit; done
	sh internal/script/deploy_test.sh

deploy: check build
	@test "$$($(GO) tool over "$(resolved-version)")" = "$(resolved-version)"
	sh internal/script/deploy.sh "$(install-prefix)" "$(resolved-version)" "$(build-output-dir)/$(project)"

version:
	@printf '%s\n' '$(resolved-version)'

clean:
	rm -f "$(build-output-dir)/$(project)"
