#!/usr/bin/env bash
set -e

# ACTS Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --local        # Install to ./.acts/bin/
#   curl -fsSL ... | bash -s -- --version 1.0.0 # Install specific version
#   curl -fsSL ... | bash -s -- --update        # Update existing installation

REPO="tommasop/acts-spec"
INSTALL_DIR="/usr/local/bin"
LOCAL_DIR="./.acts/bin"
VERSION=""
FORCE=false

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
    local url="https://github.com/${REPO}/releases/download/${version}/${platform}.tar.gz"

    echo "Downloading ${platform} ${version}..."
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    curl -fsSL "$url" -o "${tmpdir}/acts.tar.gz"
    tar xzf "${tmpdir}/acts.tar.gz" -C "$tmpdir"

    # The archive contains acts/bin/acts
    if [ -f "${tmpdir}/acts/bin/acts" ]; then
        mkdir -p "$(dirname "$dest")"
        cp "${tmpdir}/acts/bin/acts" "$dest"
        chmod +x "$dest"
    else
        echo "Error: Downloaded archive has unexpected structure"
        exit 1
    fi
}

usage() {
    cat <<EOF
ACTS Installer

Usage: install.sh [OPTIONS]

Options:
  --local          Install to ./.acts/bin/ instead of /usr/local/bin
  --version V      Install specific version (default: latest)
  --update         Update existing installation
  --force          Overwrite existing binary
  --help           Show this help

Examples:
  install.sh                          # System-wide install
  install.sh --local                  # Project-local install
  install.sh --version v1.0.0         # Install specific version
  install.sh --update                 # Update to latest
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local)
                INSTALL_DIR="$LOCAL_DIR"
                shift
                ;;
            --version)
                VERSION="$2"
                shift 2
                ;;
            --update)
                FORCE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
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

    local dest="${INSTALL_DIR}/acts"

    # Check if already installed
    if [ -f "$dest" ] && [ "$FORCE" = false ]; then
        local current_version
        current_version=$("$dest" version 2>/dev/null || "$dest" --version 2>/dev/null || echo "unknown")
        echo "ACTS is already installed: ${current_version}"
        echo "Use --update or --force to reinstall"
        exit 0
    fi

    # Create directory if needed
    if [ "$INSTALL_DIR" = "$LOCAL_DIR" ]; then
        mkdir -p "$LOCAL_DIR"
    elif [ ! -w "$(dirname "$dest")" ]; then
        echo "Need sudo to install to ${INSTALL_DIR}"
        INSTALL_DIR="${HOME}/.local/bin"
        dest="${INSTALL_DIR}/acts"
        mkdir -p "$INSTALL_DIR"
    fi

    download "$platform" "$VERSION" "$dest"

    echo "ACTS ${VERSION} installed to ${dest}"

    # Verify
    "$dest" version 2>/dev/null || "$dest" --version 2>/dev/null || true

    # Check if in PATH
    if ! command -v acts &>/dev/null; then
        echo ""
        echo "Note: ${INSTALL_DIR} is not in your PATH"
        echo "Add this to your shell profile:"
        echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
}

main "$@"
