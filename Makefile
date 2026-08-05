.PHONY: install install-local uninstall update build test release cross clean package

# Default: install acts + cbm globally
install:
	@echo "Installing ACTS (acts + cbm) globally..."
	@bash install.sh --with-cbm

# Install acts only, globally
install-acts:
	@echo "Installing ACTS globally..."
	@bash install.sh

# Install to a project-local .acts/bin/
install-local:
	@echo "Installing ACTS to ./.acts/bin/..."
	@mkdir -p .acts/bin
	@cp acts-core/zig-out/bin/acts .acts/bin/acts 2>/dev/null || (echo "build first: make build" && exit 1)

# Update to latest version
update:
	@bash install.sh --update --with-cbm

# Uninstall
uninstall:
	@echo "Removing ACTS..."
	@rm -f /usr/local/bin/acts
	@rm -f $(HOME)/.local/bin/acts
	@rm -f $(HOME)/.local/bin/codebase-memory-mcp
	@rm -f ./.acts/bin/acts
	@echo "Done"

# Build from source
build:
	cd acts-core && zig build

test:
	cd acts-core && zig build test

release:
	cd acts-core && zig build release

# Cross-compile for all supported targets (host build only; CI does per-target)
cross:
	@echo "Cross-compilation is handled by CI (release.yml matrix)."
	@echo "Local host build: make release"

# Clean build artifacts
clean:
	cd acts-core && rm -rf zig-out .zig-cache

VERSION ?= dev

# Generate release archives (host build, acts/bin layout). The canonical
# release artifacts are produced by CI (release.yml), not committed.
package: release
	@mkdir -p dist
	@platform="$$(uname -s | tr '[:upper:]' '[:lower:]')-$$(uname -m | sed 's/x86_64/x86_64/;s/arm64/aarch64/')"; \
	tmpdir=$$(mktemp -d); \
	mkdir -p "$$tmpdir/acts/bin"; \
	cp acts-core/zig-out/bin/acts "$$tmpdir/acts/bin/acts"; \
	cp README.md LICENSE "$$tmpdir/acts/" 2>/dev/null || true; \
	tar czf "dist/acts-$(VERSION)-$$platform.tar.gz" -C "$$tmpdir" acts; \
	rm -rf "$$tmpdir"; \
	echo "Created dist/acts-$(VERSION)-$$platform.tar.gz"
