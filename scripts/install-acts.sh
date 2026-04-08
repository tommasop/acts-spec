#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# install-acts.sh — Install ACTS protocol in a git repository
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/tommasop/acts-spec/main/scripts/install-acts.sh | bash
#
# This script handles both fresh repositories and existing codebases.
# It downloads ACTS from GitHub and sets up:
#   - .acts/ directory (operations, schemas, etc.)
#   - .story/ directory structure
#   - AGENTS.md (creates or appends)
#   - Optional GitHuman installation
# ─────────────────────────────────────────────

TEMP_DIR=$(mktemp -d)
CLEANUP=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

cleanup() {
  if [ "$CLEANUP" = true ] && [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  log_error "Not in a git repository. Run this script inside a git repository."
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

log_info "Installing ACTS protocol in $(basename "$REPO_ROOT")..."

# Determine ACTS source - download from GitHub or use local files
# First, try downloading from GitHub API
log_info "Downloading ACTS from GitHub..."
ACTS_ARCHIVE_URL="https://api.github.com/repos/tommasop/acts-spec/tarball/main"

if curl -L -s --fail "$ACTS_ARCHIVE_URL" -o "$TEMP_DIR/acts-spec.tar.gz" 2>/dev/null; then
  if tar -xzf "$TEMP_DIR/acts-spec.tar.gz" -C "$TEMP_DIR" 2>/dev/null; then
    ACTS_SOURCE=$(ls -d "$TEMP_DIR"/tommasop-acts-spec-* | head -1)
    log_info "Downloaded ACTS from GitHub successfully"
  else
    log_warn "Failed to extract download, falling back to local files"
    ACTS_SOURCE=""
  fi
else
  log_warn "Failed to download from GitHub, falling back to local files"
  ACTS_SOURCE=""
fi

# If download failed, check if we have local files (we might be in acts-spec repo)
if [ -z "$ACTS_SOURCE" ] || [ ! -d "$ACTS_SOURCE/.acts" ]; then
  if [ -f "acts-v0.4.0.md" ] && [ -d ".acts" ]; then
    log_info "Using local ACTS files from current repository"
    ACTS_SOURCE="$REPO_ROOT"
  else
    log_error "Could not find ACTS files. Please ensure:"
    echo "  - You have an internet connection, OR"
    echo "  - You're running this from the acts-spec repository with .acts/ directory"
    exit 1
  fi
fi

# Handle .acts directory
if [ -d ".acts" ]; then
  log_info "Backing up existing .acts to .acts.backup"
  rm -rf .acts.backup
  cp -r .acts .acts.backup
fi

log_info "Installing .acts/ directory..."
# Copy to temp dir first to avoid "same file" error
cp -r "$ACTS_SOURCE/.acts" "$TEMP_DIR/acts-copy"
mv "$TEMP_DIR/acts-copy" ./.acts

# Create .story directory structure
log_info "Creating .story/ directory structure..."
mkdir -p .story/{tasks,sessions,reviews/{active,archive}}

# Handle AGENTS.md
log_info "Setting up AGENTS.md..."
if [ ! -f "AGENTS.md" ]; then
  PROJECT_NAME=$(basename "$REPO_ROOT")
  sed "s/\[Project Name\]/$PROJECT_NAME/g" "$ACTS_SOURCE/docs/templates/agents-minimal.md" > AGENTS.md
  log_info "Created AGENTS.md from template"
else
  if grep -q "## ACTS Integration" AGENTS.md; then
    log_warn "AGENTS.md already contains ACTS Integration section. Skipping."
  else
    chmod +x "$ACTS_SOURCE/scripts/append-acts.sh"
    "$ACTS_SOURCE/scripts/append-acts.sh" AGENTS.md
    log_info "Appended ACTS section to AGENTS.md"
  fi
fi

# GitHuman installation
if command -v npm >/dev/null 2>&1; then
  if ! command -v githuman >/dev/null 2>&1; then
    log_info "GitHuman not found. Installing..."
    if npm install -g githuman; then
      log_info "GitHuman installed successfully"
    else
      log_warn "Failed to install GitHuman. Install manually: npm install -g githuman"
    fi
  else
    log_info "GitHuman already installed"
  fi
else
  log_warn "npm not found. Skipping GitHuman installation."
fi

# Gitignore
log_info "Updating .gitignore..."
if [ -f ".gitignore" ]; then
  if ! grep -q "# ACTS Protocol" .gitignore; then
    cat >> .gitignore << 'EOF'

# ACTS Protocol
.story/
.acts/mcp-server/node_modules/
.acts/mcp-server/dist/
EOF
  fi
else
  cat > .gitignore << 'EOF'
# ACTS Protocol
.story/
.acts/mcp-server/node_modules/
.acts/mcp-server/dist/
EOF
fi

log_info "ACTS installation completed!"
echo
echo "Next steps:"
echo "  1. Review AGENTS.md and customize for your project"
echo "  2. Initialize your first story with your AI agent:"
echo "     'Initialize ACTS tracker for PROJ-XXX, title \"Your Feature\"'"
echo "  3. Follow the ACTS workflow: preflight → task-start → session-summary → handoff"
echo
echo "Documentation:"
echo "  - acts-v0.4.0.md (full specification)"
echo "  - docs/minimal-viable-acts.md (quick start)"
echo "  - .acts/operations/ (workflow definitions)"