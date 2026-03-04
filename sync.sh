#!/bin/bash
# ──────────────────────────────────────────────────────────
# Claude Code Config Sync Script
# Syncs ~/.claude/ config and project settings between Macs
# ──────────────────────────────────────────────────────────

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
PROJECT_DIR="$HOME/Claude Code"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
GOLD='\033[0;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [push|pull|install]"
    echo ""
    echo "  push     Copy local config → dotfiles repo (then git commit/push)"
    echo "  pull     Copy dotfiles repo → local config (after git pull)"
    echo "  install  First-time setup on a new Mac"
    echo ""
}

push_config() {
    echo -e "${GOLD}▸ Pushing local Claude config to dotfiles repo...${NC}"

    # Global Claude config
    mkdir -p "$DOTFILES_DIR/global"

    # Copy project-level Claude settings
    mkdir -p "$DOTFILES_DIR/projects/claude-code"
    if [ -d "$PROJECT_DIR/.claude" ]; then
        cp -f "$PROJECT_DIR/.claude/launch.json" "$DOTFILES_DIR/projects/claude-code/" 2>/dev/null || true
        cp -f "$PROJECT_DIR/.claude/settings.local.json" "$DOTFILES_DIR/projects/claude-code/" 2>/dev/null || true
    fi

    # Copy project-specific memory/context from ~/.claude/projects/
    if [ -d "$CLAUDE_HOME/projects" ]; then
        mkdir -p "$DOTFILES_DIR/global/projects"
        # Copy memory files (small, important for context continuity)
        find "$CLAUDE_HOME/projects" -name "memory" -type d -exec sh -c '
            rel=$(echo "$1" | sed "s|'"$CLAUDE_HOME"'/||")
            mkdir -p "'"$DOTFILES_DIR"'/global/$rel"
            cp -r "$1/"* "'"$DOTFILES_DIR"'/global/$rel/" 2>/dev/null || true
        ' _ {} \;
    fi

    # Copy global settings if they exist
    [ -f "$CLAUDE_HOME/settings.json" ] && cp -f "$CLAUDE_HOME/settings.json" "$DOTFILES_DIR/global/" 2>/dev/null || true
    [ -f "$CLAUDE_HOME/settings.local.json" ] && cp -f "$CLAUDE_HOME/settings.local.json" "$DOTFILES_DIR/global/" 2>/dev/null || true

    echo -e "${GREEN}✓ Config pushed to dotfiles repo${NC}"
    echo ""
    echo "Now commit and push:"
    echo "  cd $DOTFILES_DIR && git add -A && git commit -m 'sync config' && git push"
}

pull_config() {
    echo -e "${GOLD}▸ Pulling dotfiles repo config to local...${NC}"

    # Restore project-level Claude settings
    if [ -d "$DOTFILES_DIR/projects/claude-code" ]; then
        mkdir -p "$PROJECT_DIR/.claude"
        cp -f "$DOTFILES_DIR/projects/claude-code/launch.json" "$PROJECT_DIR/.claude/" 2>/dev/null || true
        cp -f "$DOTFILES_DIR/projects/claude-code/settings.local.json" "$PROJECT_DIR/.claude/" 2>/dev/null || true
    fi

    # Restore global settings
    mkdir -p "$CLAUDE_HOME"
    [ -f "$DOTFILES_DIR/global/settings.json" ] && cp -f "$DOTFILES_DIR/global/settings.json" "$CLAUDE_HOME/" || true
    [ -f "$DOTFILES_DIR/global/settings.local.json" ] && cp -f "$DOTFILES_DIR/global/settings.local.json" "$CLAUDE_HOME/" || true

    # Restore memory files
    if [ -d "$DOTFILES_DIR/global/projects" ]; then
        # Map paths: session history is path-dependent, so we remap
        # Source path format: projects/-Users-markcoleman-Claude-Code/memory/
        for mem_dir in "$DOTFILES_DIR"/global/projects/*/memory; do
            if [ -d "$mem_dir" ]; then
                proj_dir=$(basename "$(dirname "$mem_dir")")

                # Remap path if username/home differs on this Mac
                local_proj_dir="$proj_dir"
                current_user=$(whoami)
                current_home=$(echo "$HOME" | sed 's|/|-|g' | sed 's/^-//')
                # Replace old user path with current
                local_proj_dir=$(echo "$proj_dir" | sed "s/-Users-[^-]*-/-Users-${current_user}-/")

                mkdir -p "$CLAUDE_HOME/projects/$local_proj_dir/memory"
                cp -r "$mem_dir/"* "$CLAUDE_HOME/projects/$local_proj_dir/memory/" 2>/dev/null || true
            fi
        done
    fi

    echo -e "${GREEN}✓ Config pulled from dotfiles repo${NC}"
}

install_new_mac() {
    echo -e "${GOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${GOLD}  MVHS Football — New Mac Setup${NC}"
    echo -e "${GOLD}═══════════════════════════════════════════════════${NC}"
    echo ""

    # 1. Create project directory
    echo -e "${GOLD}▸ Step 1: Creating project directory...${NC}"
    mkdir -p "$PROJECT_DIR"

    # 2. Clone repos
    echo -e "${GOLD}▸ Step 2: Cloning project repos...${NC}"
    if [ ! -d "$PROJECT_DIR/mission-football/.git" ]; then
        git clone git@github.com:markmissionfootball/mission-football.git "$PROJECT_DIR/mission-football"
        echo -e "${GREEN}  ✓ mission-football cloned${NC}"
    else
        echo "  ⏭ mission-football already exists, pulling latest..."
        cd "$PROJECT_DIR/mission-football" && git pull
    fi

    if [ ! -d "$PROJECT_DIR/mvhs_football/.git" ]; then
        git clone git@github.com:markmissionfootball/mvhs-football.git "$PROJECT_DIR/mvhs_football"
        echo -e "${GREEN}  ✓ mvhs_football cloned${NC}"
    else
        echo "  ⏭ mvhs_football already exists, pulling latest..."
        cd "$PROJECT_DIR/mvhs_football" && git pull
    fi

    # 3. Restore Claude config
    echo -e "${GOLD}▸ Step 3: Restoring Claude Code config...${NC}"
    pull_config

    # 4. Install dependencies
    echo -e "${GOLD}▸ Step 4: Installing dependencies...${NC}"

    if command -v npm &>/dev/null; then
        cd "$PROJECT_DIR/mission-football" && npm install
        echo -e "${GREEN}  ✓ Next.js dependencies installed${NC}"
    else
        echo -e "${RED}  ⚠ Node.js not found — install it, then run: cd '$PROJECT_DIR/mission-football' && npm install${NC}"
    fi

    if command -v flutter &>/dev/null; then
        cd "$PROJECT_DIR/mvhs_football" && flutter pub get
        echo -e "${GREEN}  ✓ Flutter dependencies installed${NC}"
    else
        echo -e "${RED}  ⚠ Flutter not found — install it, then run: cd '$PROJECT_DIR/mvhs_football' && flutter pub get${NC}"
    fi

    # 5. Firebase functions
    if [ -d "$PROJECT_DIR/mvhs_football/firebase/functions" ]; then
        if command -v npm &>/dev/null; then
            cd "$PROJECT_DIR/mvhs_football/firebase/functions" && npm install
            echo -e "${GREEN}  ✓ Firebase functions dependencies installed${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✓ Setup complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'claude /login' to authenticate Claude Code"
    echo "  2. cd '$PROJECT_DIR' && claude"
    echo "  3. Start building! 🏈"
    echo ""
}

# ── Main ──────────────────────────────────────────────────
case "${1:-}" in
    push)    push_config ;;
    pull)    pull_config ;;
    install) install_new_mac ;;
    *)       usage ;;
esac
