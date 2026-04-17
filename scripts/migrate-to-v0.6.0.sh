#!/usr/bin/env bash
# migrate-to-v0.6.0.sh — Migrate existing ACTS project to v0.6.0
#
# Usage:
#   # From GitHub (recommended):
#   curl -sL https://raw.githubusercontent.com/tommasop/acts-spec/main/scripts/migrate-to-v0.6.0.sh | bash
#
#   # From local repo:
#   /path/to/acts-spec/scripts/migrate-to-v0.6.0.sh
#
#   # Dry run:
#   curl -sL ... | bash -s -- --dry-run
#
# This script:
#   1. Detects existing ACTS installation
#   2. Creates backup in .acts/backup/
#   3. Migrates framework files to v0.6.0
#   4. Merges acts.json (preserves project config)
#   5. Installs update/validate tools to .acts/bin/
#   6. Validates result
#   7. Commits changes

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────

GITHUB_REPO="tommasop/acts-spec"
GITHUB_BRANCH="master"
ACTS_DIR=".acts"
STORY_DIR=".story"
BACKUP_DIR="${ACTS_DIR}/backup"
DRY_RUN=false

# ─── Helpers ────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}ℹ${NC}  $1"; }
log_ok()    { echo -e "${GREEN}✓${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }
log_step()  { echo -e "${BOLD}── $1 ──${NC}"; }

cleanup() {
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# ─── Detect existing ACTS ──────────────────────────────────────────────

detect_acts() {
    log_step "Detecting existing ACTS installation"
    
    if [[ ! -d "$ACTS_DIR" ]]; then
        log_error "No .acts/ directory found."
        echo "  This script migrates existing ACTS installations."
        echo "  To install fresh, use: scripts/install-acts.sh"
        exit 1
    fi
    
    # Get current version
    CURRENT_VERSION="unknown"
    if [[ -f "${ACTS_DIR}/acts.json" ]]; then
        CURRENT_VERSION=$(python3 -c "
import json
with open('${ACTS_DIR}/acts.json') as f:
    data = json.load(f)
print(data.get('manifest_version', 'unknown'))
" 2>/dev/null || echo "unknown")
    fi
    
    log_ok "Found ACTS v${CURRENT_VERSION}"
    echo "  Target version: v0.6.0"
    echo ""
    
    # Show what exists
    log_info "Current installation:"
    if [[ -d "${ACTS_DIR}/operations" ]]; then
        local op_count
        op_count=$(find "${ACTS_DIR}/operations" -name "*.md" | wc -l)
        echo "  .acts/operations/ ($op_count files)"
    fi
    if [[ -d "${ACTS_DIR}/schemas" ]]; then
        local schema_count
        schema_count=$(find "${ACTS_DIR}/schemas" -name "*.json" | wc -l)
        echo "  .acts/schemas/ ($schema_count files)"
    fi
    if [[ -f "${ACTS_DIR}/acts.json" ]]; then
        echo "  .acts/acts.json"
    fi
    if [[ -d "$STORY_DIR" ]]; then
        echo "  .story/ (story data)"
    fi
    echo ""
}

# ─── Download source files ─────────────────────────────────────────────

download_source() {
    log_step "Downloading ACTS v0.6.0 framework files"
    
    TEMP_DIR=$(mktemp -d)
    
    if [[ -d "$(dirname "$0")/../.acts" ]]; then
        # Local mode — running from acts-spec repo
        log_info "Local mode: using files from $(cd "$(dirname "$0")/.." && pwd)"
        SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    else
        # Remote mode — download from GitHub
        log_info "Downloading from GitHub..."
        local zip_url="https://github.com/${GITHUB_REPO}/archive/refs/heads/${GITHUB_BRANCH}.zip"
        curl -sL "$zip_url" -o "${TEMP_DIR}/acts-spec.zip"
        unzip -q "${TEMP_DIR}/acts-spec.zip" -d "${TEMP_DIR}"
        SOURCE_DIR="${TEMP_DIR}/acts-spec-${GITHUB_BRANCH}"
    fi
    
    log_ok "Source ready: ${SOURCE_DIR}"
}

# ─── Backup ─────────────────────────────────────────────────────────────

create_backup() {
    log_step "Creating backup"
    
    local backup_version="${1:-unknown}"
    local backup_path="${BACKUP_DIR}/${backup_version}"
    
    mkdir -p "$backup_path"
    
    # Backup framework files
    for item in operations schemas report-protocol.md code-review-interface.json; do
        local src="${ACTS_DIR}/${item}"
        if [[ -d "$src" ]]; then
            cp -r "$src" "$backup_path/$item"
            log_ok "Backed up .acts/$item/"
        elif [[ -f "$src" ]]; then
            cp "$src" "$backup_path/$item"
            log_ok "Backed up .acts/$item"
        fi
    done
    
    # Backup acts.json
    if [[ -f "${ACTS_DIR}/acts.json" ]]; then
        cp "${ACTS_DIR}/acts.json" "${backup_path}/acts.json"
        log_ok "Backed up .acts/acts.json"
    fi
    
    # Write manifest
    cat > "${backup_path}/manifest.json" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "from_version": "${backup_version}",
  "to_version": "0.6.0",
  "migration": true
}
EOF
    
    log_ok "Backup created: .acts/backup/${backup_version}/"
}

# ─── Merge acts.json ───────────────────────────────────────────────────

merge_config() {
    log_step "Merging .acts/acts.json"
    
    local source="$1"
    local target="${ACTS_DIR}/acts.json"
    
    MERGE_SOURCE="${source}" MERGE_TARGET="${target}" python3 -c '
import json
import os
import sys

source = os.environ["MERGE_SOURCE"]
target = os.environ["MERGE_TARGET"]

# Read source template
with open(f"{source}/.acts/acts.json") as f:
    template = json.load(f)

# Read current config
with open(target) as f:
    current = json.load(f)

# Fields to update from template
UPDATE_FIELDS = ["manifest_version"]

# Fields to add if missing (new in this version)
ADD_IF_MISSING = {
    "agent_framework": {"enabled": False},
    "gh_stack": {"enabled": False, "description": "GitHub Stacked PRs adapter (private preview)."},
    "conformance_level": "standard"
}

# Apply updates
for field in UPDATE_FIELDS:
    if field in template:
        current[field] = template[field]

# Add missing fields
for field, default in ADD_IF_MISSING.items():
    if field not in current:
        current[field] = default

# Write merged config
with open(target, "w") as f:
    json.dump(current, f, indent=2)
    f.write("\n")

mv = current["manifest_version"]
print(f"  manifest_version: -> {mv}")
for field in ADD_IF_MISSING:
    if field in current and current[field] == ADD_IF_MISSING[field]:
        print(f"  {field}: added (new in v0.6.0)")
'
    
    log_ok "Config merged"
}

# ─── Copy framework files ──────────────────────────────────────────────

copy_framework() {
    log_step "Updating framework files"
    
    local source="$1"
    
    # Operations
    if [[ -d "${source}/.acts/operations" ]]; then
        mkdir -p "${ACTS_DIR}/operations"
        cp -r "${source}/.acts/operations/"*.md "${ACTS_DIR}/operations/"
        log_ok "Updated .acts/operations/ ($(find ${ACTS_DIR}/operations -name '*.md' | wc -l) files)"
    fi
    
    # Schemas
    if [[ -d "${source}/.acts/schemas" ]]; then
        mkdir -p "${ACTS_DIR}/schemas"
        cp -r "${source}/.acts/schemas/"*.json "${ACTS_DIR}/schemas/"
        log_ok "Updated .acts/schemas/"
    fi
    
    # Report protocol
    if [[ -f "${source}/.acts/report-protocol.md" ]]; then
        cp "${source}/.acts/report-protocol.md" "${ACTS_DIR}/report-protocol.md"
        log_ok "Updated .acts/report-protocol.md"
    fi
    
    # Code review interface
    if [[ -f "${source}/.acts/code-review-interface.json" ]]; then
        cp "${source}/.acts/code-review-interface.json" "${ACTS_DIR}/code-review-interface.json"
        log_ok "Updated .acts/code-review-interface.json"
    fi
}

# ─── Install bin tools ─────────────────────────────────────────────────

install_tools() {
    log_step "Installing .acts/bin/ tools"
    
    mkdir -p "${ACTS_DIR}/bin"
    
    local source="$1"
    
    # acts-update
    if [[ -f "${source}/.acts/bin/acts-update" ]]; then
        cp "${source}/.acts/bin/acts-update" "${ACTS_DIR}/bin/acts-update"
        chmod +x "${ACTS_DIR}/bin/acts-update"
        log_ok "Installed acts-update"
    fi
    
    # acts-validate (if exists in source)
    if [[ -f "${source}/.acts/bin/acts-validate" ]]; then
        cp "${source}/.acts/bin/acts-validate" "${ACTS_DIR}/bin/acts-validate"
        chmod +x "${ACTS_DIR}/bin/acts-validate"
        log_ok "Installed acts-validate"
    fi
    
    # Also keep in scripts/ for backward compatibility
    if [[ -f "${source}/scripts/validate.sh" ]]; then
        mkdir -p scripts
        cp "${source}/scripts/validate.sh" "scripts/validate.sh"
        chmod +x "scripts/validate.sh"
        log_ok "Kept scripts/validate.sh (backward compat)"
    fi
}

# ─── Validate ───────────────────────────────────────────────────────────

validate() {
    log_step "Validating migration"
    
    # Check acts.json is valid JSON
    if python3 -m json.tool "${ACTS_DIR}/acts.json" > /dev/null 2>&1; then
        log_ok "acts.json is valid JSON"
    else
        log_error "acts.json validation failed!"
        exit 1
    fi
    
    # Check required operations exist
    local required_ops=("preflight" "task-start" "task-review" "session-summary" "story-init")
    for op in "${required_ops[@]}"; do
        if [[ -f "${ACTS_DIR}/operations/${op}.md" ]]; then
            log_ok "Operation exists: ${op}"
        else
            log_warn "Missing operation: ${op}"
        fi
    done
    
    # Check version
    local version
    version=$(python3 -c "
import json
with open('${ACTS_DIR}/acts.json') as f:
    print(json.load(f).get('manifest_version', 'unknown'))
" 2>/dev/null)
    
    if [[ "$version" == "0.6.0" ]]; then
        log_ok "Version: v0.6.0"
    else
        log_warn "Version: v${version} (expected 0.6.0)"
    fi
}

# ─── Commit ─────────────────────────────────────────────────────────────

commit_changes() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would commit migration"
        return
    fi
    
    log_step "Committing changes"
    
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        log_warn "Not a git repository — skipping commit"
        return
    fi
    
    git add -A .acts/ scripts/
    
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return
    fi
    
    git commit -m "chore: migrate ACTS to v0.6.0 (operations, schemas, bin tools)"
    log_ok "Changes committed"
}

# ─── Summary ────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    log_step "Migration Complete"
    echo ""
    echo "  ACTS v0.6.0 is now installed."
    echo ""
    echo "  What changed:"
    echo "    • .acts/operations/ — updated to v0.6.0"
    echo "    • .acts/schemas/ — updated to v0.6.0"
    echo "    • .acts/bin/acts-update — new update tool"
    echo "    • .acts/bin/acts-validate — validation tool"
    echo "    • .acts/acts.json — config merged"
    echo ""
    echo "  What's preserved:"
    echo "    • .acts/acts.json — your project config"
    echo "    • .acts/review-providers/ — your providers"
    echo "    • .story/ — all story data"
    echo "    • AGENTS.md — your constitution"
    echo ""
    echo "  Next steps:"
    echo "    • Review the changes: git diff"
    echo "    • Run validation: .acts/bin/acts-validate"
    echo "    • Check for updates: .acts/bin/acts-update --check"
    echo "    • Read docs: docs/updating-acts.md"
    echo ""
    echo "  Rollback:"
    echo "    • .acts/bin/acts-update --restore v${BACKUP_VERSION}"
    echo ""
}

# ─── Main ───────────────────────────────────────────────────────────────

main() {
    echo -e "${BOLD}ACTS Migration to v0.6.0${NC}"
    echo ""
    
    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                cat << 'EOF'
Usage: migrate-to-v0.6.0.sh [options]

Options:
  --dry-run    Show what would be done without making changes
  --help       Show this help

Migration steps:
  1. Detect existing ACTS installation
  2. Backup current framework files
  3. Copy new framework files (operations, schemas, tools)
  4. Merge acts.json (preserve project config, add new fields)
  5. Validate result
  6. Commit changes

This script is idempotent — safe to run multiple times.
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run migration
    detect_acts
    BACKUP_VERSION="$CURRENT_VERSION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup, update files, merge config"
        exit 0
    fi
    
    download_source
    create_backup "$BACKUP_VERSION"
    copy_framework "$SOURCE_DIR"
    merge_config "$SOURCE_DIR" "${ACTS_DIR}/acts.json"
    install_tools "$SOURCE_DIR"
    validate
    commit_changes
    print_summary
}

main "$@"
