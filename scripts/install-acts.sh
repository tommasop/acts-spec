#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# install-acts.sh — Install ACTS protocol in a git repository
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/tommasop/acts-spec/main/scripts/install-acts.sh | bash
#
# This script handles both fresh repositories and existing codebases.
# It downloads the LATEST ACTS from GitHub and sets up:
#   - .acts/ directory (operations, schemas, bin tools, etc.)
#   - .story/ directory structure
#   - AGENTS.md (creates or appends)
#   - Optional lazygit installation (for code review)
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

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  log_error "Not in a git repository. Run this script inside a git repository."
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

log_info "Installing ACTS protocol in $(basename "$REPO_ROOT")..."

# Always download the LATEST ACTS from GitHub
log_info "Downloading latest ACTS from GitHub..."
ACTS_DOWNLOADED=false

for branch in main master; do
  ACTS_TARBALL_URL="https://github.com/tommasop/acts-spec/archive/refs/heads/$branch.tar.gz"
  log_info "Attempting to download from branch: $branch"
  
  if curl -L -s --max-time 30 "$ACTS_TARBALL_URL" -o "$TEMP_DIR/acts-spec.tar.gz"; then
    if tar -xzf "$TEMP_DIR/acts-spec.tar.gz" -C "$TEMP_DIR" 2>/dev/null; then
      ACTS_SOURCE=$(ls -d "$TEMP_DIR"/acts-spec-* | head -1)
      if [ -d "$ACTS_SOURCE/.acts" ]; then
        # Detect the latest version from the downloaded spec file
        LATEST_SPEC=$(ls -1 "$ACTS_SOURCE"/acts-v*.md 2>/dev/null | sort -V | tail -n1)
        if [ -n "$LATEST_SPEC" ]; then
          LATEST_VERSION=$(basename "$LATEST_SPEC" | sed 's/acts-v\(.*\)\.md/\1/')
          log_info "Downloaded ACTS v$LATEST_VERSION from GitHub (branch: $branch)"
        else
          log_info "Downloaded ACTS from GitHub (branch: $branch)"
        fi
        ACTS_DOWNLOADED=true
        break
      fi
    fi
  fi
done

# If download failed, exit with error
if [ "$ACTS_DOWNLOADED" != true ]; then
  log_error "Could not download ACTS from GitHub. Please ensure:"
  echo "  - You have an internet connection"
  echo "  - GitHub is accessible"
  echo "  - The acts-spec repository exists"
  exit 1
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
  sed "s/\[Project Name\]/$PROJECT_NAME/g" "$ACTS_SOURCE/docs/templates/agents-minimal.md" >AGENTS.md
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

# lazygit installation (for code review)
if ! command -v lazygit >/dev/null 2>&1; then
  log_info "lazygit not found. Installing..."
  if command -v brew >/dev/null 2>&1; then
    if brew install lazygit; then
      log_info "lazygit installed successfully"
    else
      log_warn "Failed to install lazygit. Install manually: brew install lazygit"
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    if sudo apt-get install -y lazygit 2>/dev/null || sudo snap install lazygit 2>/dev/null; then
      log_info "lazygit installed successfully"
    else
      log_warn "Failed to install lazygit. Install manually: https://github.com/jesseduffield/lazygit"
    fi
  else
    log_warn "No package manager found. Install lazygit manually: https://github.com/jesseduffield/lazygit"
  fi
else
  log_info "lazygit already installed"
fi

# Gitignore
log_info "Updating .gitignore..."
if [ -f ".gitignore" ]; then
  if ! grep -q "# ACTS Protocol" .gitignore; then
    cat >>.gitignore <<'EOF'

# ACTS Protocol
.acts/mcp-server/node_modules/
.acts/mcp-server/dist/
EOF
  fi
else
  cat >.gitignore <<'EOF'
# ACTS Protocol
.acts/mcp-server/node_modules/
.acts/mcp-server/dist/
EOF
fi

# Get the installed version for display
INSTALLED_VERSION=${LATEST_VERSION:-"latest"}

log_info "ACTS v$INSTALLED_VERSION installation completed!"
echo
echo "Next steps:"
echo "  1. Review AGENTS.md and customize for your project"
echo "  2. Initialize your first story with your AI agent:"
echo "     'Initialize ACTS tracker for PROJ-XXX, title \"Your Feature\"'"
echo "  3. Or discover what to build: 'story-discover' (blank slate → draft spec)"
echo "  4. Follow the ACTS workflow: preflight → task-start → session-summary → handoff"
echo
echo "Tools installed:"
echo "  - .acts/bin/acts-update  (update ACTS framework to latest)"
echo "  - .acts/bin/acts-validate (validate conformance)"
echo
echo "Documentation:"
echo "  - acts-v$INSTALLED_VERSION.md (full specification)"
echo "  - docs/minimal-viable-acts.md (quick start)"
echo "  - docs/updating-acts.md (how to update)"
echo "  - .acts/operations/ (workflow definitions)"
