#!/usr/bin/env bash
set -e

# ACTS Installer v1.1.0
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh | bash
#   curl -fsSL ... | bash -s -- --local        # Install to ./.acts/bin/
#   curl -fsSL ... | bash -s -- --version 1.1.0 # Install specific version
#   curl -fsSL ... | bash -s -- --update        # Update existing installation (with migration)

REPO="tommasop/acts-spec"
INSTALL_DIR="/usr/local/bin"
LOCAL_DIR="./.acts/bin"
VERSION=""
FORCE=false
MIGRATE=true

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

migrate_projects() {
    echo ""
    echo "Checking for ACTS projects to migrate..."

    # Find all .acts/acts.db files in current directory and subdirectories
    local db_files
    db_files=$(find . -name "acts.db" -path "*/.acts/*" 2>/dev/null || true)

    # Also check parent directories up to home
    local dir="$PWD"
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
        if [ -f "$dir/.acts/acts.db" ]; then
            db_files="${db_files:+$db_files
}$dir/.acts/acts.db"
        fi
        dir=$(dirname "$dir")
    done

    if [ -z "$db_files" ]; then
        echo "No existing ACTS projects found."
        return 0
    fi

    local acts_bin="$1"
    local migrated=0

    while IFS= read -r db_path; do
        local project_dir
        project_dir=$(dirname "$(dirname "$db_path")")

        # Check schema version
        local current_version
        current_version=$(sqlite3 "$db_path" "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1;" 2>/dev/null || echo "0")

        if [ "$current_version" -lt 5 ] 2>/dev/null; then
            echo "Migrating project at ${project_dir} (schema v${current_version} -> v5)..."
            cd "$project_dir" && "$acts_bin" migrate && cd - > /dev/null
            migrated=$((migrated + 1))
        else
            echo "Project at ${project_dir} is already up to date (schema v${current_version})."
        fi
    done <<< "$db_files"

    if [ "$migrated" -gt 0 ]; then
        echo ""
        echo "Migrated ${migrated} project(s) to schema v5."
    fi
}

usage() {
    cat <<EOF
ACTS Installer v1.1.0

Usage: install.sh [OPTIONS]

Options:
  --local          Install to ./.acts/bin/ instead of /usr/local/bin
  --version V      Install specific version (default: latest)
  --update         Update existing installation and migrate projects
  --force          Overwrite existing binary
  --no-migrate     Skip project migration (update only)
  --help           Show this help

Examples:
  install.sh                          # System-wide install
  install.sh --local                  # Project-local install
  install.sh --version v1.1.0         # Install specific version
  install.sh --update                 # Update and migrate projects
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
                MIGRATE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --no-migrate)
                MIGRATE=false
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

    # Migrate existing projects
    if [ "$MIGRATE" = true ]; then
        migrate_projects "$dest"
    fi

    # Check if in PATH
    if ! command -v acts &>/dev/null; then
        echo ""
        echo "Note: ${INSTALL_DIR} is not in your PATH"
        echo "Add this to your shell profile:"
        echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
}

main "$@"
