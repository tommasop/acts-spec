.PHONY: install install-local uninstall update clean test build release cross

# Default: install system-wide
install:
	@echo "Installing ACTS system-wide..."
	@bash install.sh

# Install to project-local .acts/bin/
install-local:
	@echo "Installing ACTS to ./.acts/bin/..."
	@bash install.sh --local

# Update to latest version
update:
	@bash install.sh --update

# Uninstall
uninstall:
	@echo "Removing ACTS..."
	@rm -f /usr/local/bin/acts
	@rm -f $(HOME)/.local/bin/acts
	@rm -f ./.acts/bin/acts
	@echo "Done"

# Build from source
build:
	cd acts-core && zig build

test:
	cd acts-core && zig build test

release:
	cd acts-core && zig build release

cross:
	cd acts-core && zig build cross

# Clean build artifacts
clean:
	cd acts-core && rm -rf zig-out .zig-cache

# Generate release archives
package: cross
	@mkdir -p dist
	@for bin in acts-linux-x86_64 acts-linux-aarch64 acts-macos-x86_64 acts-macos-aarch64; do \
		tmpdir=$$(mktemp -d); \
		mkdir -p "$$tmpdir/acts/bin" "$$tmpdir/acts/.acts/review-providers"; \
		cp "acts-core/zig-out/bin/$$bin" "$$tmpdir/acts/bin/acts"; \
		cp .acts/acts.json "$$tmpdir/acts/.acts/"; \
		cp .acts/review-providers/hunk.json "$$tmpdir/acts/.acts/review-providers/"; \
		cp README.md LICENSE "$$tmpdir/acts/" 2>/dev/null || true; \
		tar czf "dist/$${bin}.tar.gz" -C "$$tmpdir" acts; \
		rm -rf "$$tmpdir"; \
		echo "Created dist/$${bin}.tar.gz"; \
	done
