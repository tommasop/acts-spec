#!/usr/bin/env bash
set -e

# ACTS v2.1 Installer — global binaries (acts + cbm)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --with-cbm         # also install codebase-memory-mcp
#   curl -fsSL ... | bash -s -- --bin-dir "$HOME/.local/bin"
#   curl -fsSL ... | bash -s -- --update           # update acts + cbm
#
# `acts setup` is the recommended project bootstrap (wires AGENTS.md,
# opencode.json, plugins). This installer only manages the binaries.

REPO="tommasop/acts-spec"
VERSION=""
BIN_DIR="${ACTS_BIN_DIR:-}"
WITH_CBM=false
FORCE=false

# Default global bin dir: prefer $HOME/.local/bin (no sudo needed, and it is
# what earlier installs used). Only fall back to /usr/local/bin when the user's
# local bin dir is unwritable so we never leave two copies of acts on PATH.
if [ -z "$BIN_DIR" ]; then
    if [ -w "${HOME}/.local/bin" ]; then
        BIN_DIR="${HOME}/.local/bin"
    elif [ -w "/usr/local/bin" ]; then
        BIN_DIR="/usr/local/bin"
    else
        BIN_DIR="${HOME}/.local/bin"
    fi
fi

detect_platform() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    case "$os" in
        linux) os="linux" ;;
        darwin) os="macos" ;;
        *) echo "Unsupported OS: $os"; exit 1 ;;
    esac
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) echo "Unsupported architecture: $arch"; exit 1 ;;
    esac
    echo "acts-${os}-${arch}"
}

get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

download() {
    local platform="$1"
    local version="$2"
    local dest="$3"
    local url="https://github.com/${REPO}/releases/download/${version}/acts-${version}-${platform#acts-}.tar.gz"

    echo "Downloading ${platform} ${version}..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    curl -fsSL "$url" -o "${tmpdir}/acts.tar.gz"
    tar xzf "${tmpdir}/acts.tar.gz" -C "$tmpdir"

    # Locate the binary inside the archive (release archives ship it at the
    # tar root named `acts-<platform>`; older archives used acts/bin/acts).
    local src
    if [ -f "${tmpdir}/acts/bin/acts" ]; then
        src="${tmpdir}/acts/bin/acts"
    elif [ -f "${tmpdir}/${platform}" ]; then
        src="${tmpdir}/${platform}"
    else
        echo "Error: Downloaded archive has unexpected structure"
        echo "Contents: $(ls "$tmpdir")"
        exit 1
    fi

    # Install atomically: copy to a temp file in the destination dir, then
    # rename over the target. rename() replaces the directory entry even when
    # the target is currently running (unlike cp, which fails with ETXTBSY on
    # a running executable), and never leaves a partial binary on failure.
    mkdir -p "$(dirname "$dest")"
    local tmp="${dest}.tmp.$$"
    cp "$src" "$tmp"
    chmod +x "$tmp"
    mv -f "$tmp" "$dest"

    # Verify the installed binary actually reports the requested version.
    local installed
    installed=$("$dest" version 2>/dev/null | awk '{print $2}' || true)
    if [ -n "$installed" ] && [ "$installed" != "$version" ]; then
        echo "Warning: expected ${version} but installed binary reports ${installed}"
    fi
}

install_cbm() {
    echo ""
    echo "Installing codebase-memory-mcp (cbm) via its official installer..."
    # cbm picks its own canonical location; we just invoke its installer.
    # The installer may exit non-zero when it finds pre-existing agent config,
    # so verify the binary landed rather than treating that as fatal.
    curl -fsSL "https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh" | bash -s -- --skip-config >/dev/null 2>&1 || true
    local cbm
    cbm="$(command -v codebase-memory-mcp 2>/dev/null || true)"
    if [ -n "$cbm" ]; then
        echo "cbm installed at: $cbm"
    else
        echo "Warning: cbm binary not found after install. Run \`acts setup\` to retry."
    fi
}

usage() {
    cat <<EOF
ACTS Installer v2.1.0 — global binaries (acts + cbm)

Usage: install.sh [OPTIONS]

Options:
  --with-cbm       Also install codebase-memory-mcp (cross-repo graph engine)
  --bin-dir PATH   Install acts to PATH (default: ~/.local/bin or /usr/local/bin)
  --version V      Install specific acts version (default: latest)
  --force          Always reinstall, even if already on the requested version
  --update         Update acts to the requested version (replaces even if running)
  --help           Show this help

Examples:
  install.sh                       # Install acts globally
  install.sh --with-cbm            # Install acts + cbm globally
  install.sh --update --with-cbm   # Update both
  install.sh --bin-dir "$HOME/.local/bin"

Project bootstrap (after install):
  acts setup . --github            # Wire AGENTS.md + opencode.json + plugins
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --with-cbm) WITH_CBM=true; shift ;;
            --bin-dir) BIN_DIR="$2"; shift 2 ;;
            --version) VERSION="$2"; shift 2 ;;
            --force) FORCE=true; shift ;;
            --update) FORCE=true; shift ;;
            --help|-h) usage; exit 0 ;;
            *) echo "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    local platform
    platform=$(detect_platform)

    if [ -z "$VERSION" ]; then
        VERSION=$(get_latest_version)
        if [ -z "$VERSION" ]; then
            echo "Error: Could not determine latest version"
            exit 1
        fi
    fi

    local dest="${BIN_DIR}/acts"
    mkdir -p "$BIN_DIR"

    if [ -f "$dest" ] && [ "$FORCE" = false ]; then
        local current_version
        current_version=$("$dest" version 2>/dev/null | awk '{print $2}' || echo "unknown")
        if [ "$current_version" = "$VERSION" ]; then
            echo "acts is already up to date: ${current_version}"
        else
            echo "acts installed: ${current_version} (requested ${VERSION}) — updating"
            download "$platform" "$VERSION" "$dest"
            echo "acts ${VERSION} installed to ${dest}"
        fi
    else
        download "$platform" "$VERSION" "$dest"
        echo "acts ${VERSION} installed to ${dest}"
    fi

    if [ "$WITH_CBM" = true ]; then
        install_cbm
    fi

    echo ""
    echo "Next: run \`acts setup\` in your project to wire AGENTS.md + opencode.json."
    if ! command -v acts &>/dev/null; then
        echo "Note: ${BIN_DIR} is not in your PATH. Add it:"
        echo "  export PATH=\"${BIN_DIR}:\$PATH\""
    else
        # Detect a shadowing install: another `acts` earlier in PATH would be
        # invoked instead of the one we just installed (e.g. a stale v1 copy).
        local resolved
        resolved="$(command -v acts)"
        if [ "$resolved" != "$dest" ]; then
            local shadow_ver
            shadow_ver="$("$resolved" version 2>/dev/null | awk '{print $2}' || echo "unknown")"
            echo "Warning: '$resolved' (v${shadow_ver}) is earlier in PATH and shadows ${dest} (v${VERSION})."
            echo "  Remove '$resolved' (e.g. 'rm $resolved') or reorder PATH so ${BIN_DIR} comes first."
            echo "  Otherwise 'acts' resolves to the stale binary."
        fi
    fi
}

main "$@"
