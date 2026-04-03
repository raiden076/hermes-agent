#!/bin/bash
# ============================================================================
# Hermes Agent Installer (Merged Fork Edition)
# ============================================================================
# Installation script for Linux and macOS.
# Uses uv for fast Python provisioning and package management.
#
# This installer clones from raiden076/hermes-agent (merged-main branch)
# which combines NousResearch upstream features with outsourc-e webapi support.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/raiden076/hermes-agent/merged-main/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL ... | bash -s -- --no-venv --skip-setup
#
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration - MODIFIED FOR MERGED FORK
REPO_URL_SSH="git@github.com:raiden076/hermes-agent.git"
REPO_URL_HTTPS="https://github.com/raiden076/hermes-agent.git"
HERMES_HOME="$HOME/.hermes"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
PYTHON_VERSION="3.11"
NODE_VERSION="22"

# Options
USE_VENV=true
RUN_SETUP=true
BRANCH="merged-main"  # MODIFIED: Default to merged-main instead of main

# Detect non-interactive mode (e.g. curl | bash)
# When stdin is not a terminal, read -p will fail with EOF,
# causing set -e to silently abort the entire script.
if [ -t 0 ]; then
    IS_INTERACTIVE=true
else
    IS_INTERACTIVE=false
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-venv)
            USE_VENV=false
            shift
            ;;
        --skip-setup)
            RUN_SETUP=false
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Hermes Agent Installer (Merged Fork Edition)"
            echo ""
            echo "This installer uses raiden076/hermes-agent (merged-main branch)"
            echo "which combines NousResearch upstream with outsourc-e webapi support."
            echo ""
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-venv      Don't create virtual environment"
            echo "  --skip-setup   Skip interactive setup wizard"
            echo "  --branch NAME  Git branch to install (default: merged-main)"
            echo "  --dir PATH     Installation directory (default: ~/.hermes/hermes-agent)"
            echo "  -h, --help     Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper functions
# ============================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│       ⚕ Hermes Agent Installer (Merged Fork)            │"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│  Open source AI agent by Nous Research + WebAPI         │"
    echo "│  Fork: raiden076/hermes-agent (merged-main)             │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

log_info() {
    echo -e "${CYAN}→${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# ============================================================================
# System detection
# ============================================================================

detect_os() {
    case "$(uname -s)" in
        Linux*)
            OS="linux"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO="$ID"
            else
                DISTRO="unknown"
            fi
            ;;
        Darwin*)
            OS="macos"
            DISTRO="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS="windows"
            DISTRO="windows"
            log_error "Windows detected. Please use WSL2:"
            log_info "  https://learn.microsoft.com/en-us/windows/wsl/install"
            exit 1
            ;;
        *)
            OS="unknown"
            DISTRO="unknown"
            log_warn "Unknown operating system"
            ;;
    esac

    log_success "Detected: $OS ($DISTRO)"
}

# ============================================================================
# Dependency checks
# ============================================================================

install_uv() {
    log_info "Checking for uv package manager..."

    # Check common locations for uv
    if command -v uv &> /dev/null; then
        UV_CMD="uv"
        UV_VERSION=$($UV_CMD --version 2>/dev/null)
        log_success "uv found ($UV_VERSION)"
        return 0
    fi

    # Check ~/.local/bin (default uv install location) even if not on PATH yet
    if [ -x "$HOME/.local/bin/uv" ]; then
        UV_CMD="$HOME/.local/bin/uv"
        UV_VERSION=$($UV_CMD --version 2>/dev/null)
        log_success "uv found at ~/.local/bin ($UV_VERSION)"
        return 0
    fi

    # Check ~/.cargo/bin (alternative uv install location)
    if [ -x "$HOME/.cargo/bin/uv" ]; then
        UV_CMD="$HOME/.cargo/bin/uv"
        UV_VERSION=$($UV_CMD --version 2>/dev/null)
        log_success "uv found at ~/.cargo/bin ($UV_VERSION)"
        return 0
    fi

    # Install uv
    log_info "Installing uv (fast Python package manager)..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null; then
        # uv installs to ~/.local/bin by default
        if [ -x "$HOME/.local/bin/uv" ]; then
            UV_CMD="$HOME/.local/bin/uv"
        elif [ -x "$HOME/.cargo/bin/uv" ]; then
            UV_CMD="$HOME/.cargo/bin/uv"
        elif command -v uv &> /dev/null; then
            UV_CMD="uv"
        else
            log_error "uv installed but not found on PATH"
            log_info "Try adding ~/.local/bin to your PATH and re-running"
            exit 1
        fi
        UV_VERSION=$($UV_CMD --version 2>/dev/null)
        log_success "uv installed ($UV_VERSION)"
    else
        log_error "Failed to install uv"
        log_info "Install manually: https://docs.astral.sh/uv/getting-started/installation/"
        exit 1
    fi
}

check_python() {
    log_info "Checking Python $PYTHON_VERSION..."

    # Let uv handle Python — it can download and manage Python versions
    # First check if a suitable Python is already available
    if $UV_CMD python find "$PYTHON_VERSION" &> /dev/null; then
        PYTHON_PATH=$($UV_CMD python find "$PYTHON_VERSION")
        PYTHON_FOUND_VERSION=$($PYTHON_PATH --version 2>/dev/null)
        log_success "Python found: $PYTHON_FOUND_VERSION"
        return 0
    fi

    # Python not found — use uv to install it (no sudo needed!)
    log_info "Python $PYTHON_VERSION not found, installing via uv..."
    if $UV_CMD python install "$PYTHON_VERSION"; then
        PYTHON_PATH=$($UV_CMD python find "$PYTHON_VERSION")
        PYTHON_FOUND_VERSION=$($PYTHON_PATH --version 2>/dev/null)
        log_success "Python installed: $PYTHON_FOUND_VERSION"
    else
        log_error "Failed to install Python $PYTHON_VERSION"
        log_info "Install Python $PYTHON_VERSION manually, then re-run this script"
        exit 1
    fi
}

check_git() {
    log_info "Checking Git..."

    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        log_success "Git $GIT_VERSION found"
        return 0
    fi

    log_error "Git not found"
    log_info "Please install Git:"

    case "$OS" in
        linux)
            case "$DISTRO" in
                ubuntu|debian)
                    log_info "  sudo apt update && sudo apt install git"
                    ;;
                fedora)
                    log_info "  sudo dnf install git"
                    ;;
                arch)
                    log_info "  sudo pacman -S git"
                    ;;
                *)
                    log_info "  Use your package manager to install git"
                    ;;
            esac
            ;;
        macos)
            log_info "  xcode-select --install"
            log_info "  Or: brew install git"
            ;;
    esac

    exit 1
}

check_node() {
    log_info "Checking Node.js (for browser tools)..."

    if command -v node &> /dev/null; then
        local found_ver=$(node --version)
        log_success "Node.js $found_ver found"
        HAS_NODE=true
        return 0
    fi

    # Check our own managed install from a previous run
    if [ -x "$HERMES_HOME/node/bin/node" ]; then
        export PATH="$HERMES_HOME/node/bin:$PATH"
        local found_ver=$("$HERMES_HOME/node/bin/node" --version)
        log_success "Node.js $found_ver found (Hermes-managed)"
        HAS_NODE=true
        return 0
    fi

    log_info "Node.js not found — installing Node.js $NODE_VERSION LTS..."
    install_node
}

install_node() {
    local arch=$(uname -m)
    local node_arch
    case "$arch" in
        x86_64)        node_arch="x64"    ;;
        aarch64|arm64) node_arch="arm64"  ;;
        armv7l)        node_arch="armv7l" ;;
        *)
            log_warn "Unsupported architecture ($arch) for Node.js auto-install"
            log_info "Install manually: https://nodejs.org/en/download/"
            HAS_NODE=false
            return 0
            ;;
    esac

    local node_os
    case "$OS" in
        linux) node_os="linux"  ;;
        macos) node_os="darwin" ;;
        *)
            log_warn "Unsupported OS for Node.js auto-install"
            HAS_NODE=false
            return 0
            ;;
    esac

    # Resolve the latest v22.x.x tarball name from the index page
    local index_url="https://nodejs.org/dist/latest-v${NODE_VERSION}.x/"
    local tarball_name
    tarball_name=$(curl -fsSL "$index_url" \
        | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.xz" \
        | head -1)

    # Fallback to .tar.gz if .tar.xz not available
    if [ -z "$tarball_name" ]; then
        tarball_name=$(curl -fsSL "$index_url" \
            | grep -oE "node-v${NODE_VERSION}\.[0-9]+\.[0-9]+-${node_os}-${node_arch}\.tar\.gz" \
            | head -1)
    fi

    if [ -z "$tarball_name" ]; then
        log_warn "Could not find Node.js $NODE_VERSION binary for $node_os-$node_arch"
        log_info "Install manually: https://nodejs.org/en/download/"
        HAS_NODE=false
        return 0
    fi

    local download_url="${index_url}${tarball_name}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    log_info "Downloading $tarball_name..."
    if ! curl -fsSL "$download_url" -o "$tmp_dir/$tarball_name"; then
        log_warn "Download failed"
        HAS_NODE=false
        return 0
    fi

    log_info "Extracting to $HERMES_HOME/node/..."
    mkdir -p "$HERMES_HOME/node"
    rm -rf "$HERMES_HOME/node"/* 2>/dev/null || true
    tar -xf "$tmp_dir/$tarball_name" -C "$HERMES_HOME/node" --strip-components=1
    rm -rf "$tmp_dir"

    # Symlink to ~/.local/bin for PATH access
    mkdir -p "$HOME/.local/bin"
    ln -sf "$HERMES_HOME/node/bin/node" "$HOME/.local/bin/node"
    ln -sf "$HERMES_HOME/node/bin/npm"  "$HOME/.local/bin/npm"
    ln -sf "$HERMES_HOME/node/bin/npx"  "$HOME/.local/bin/npx"

    export PATH="$HERMES_HOME/node/bin:$PATH"

    local installed_ver
    installed_ver=$("$HERMES_HOME/node/bin/node" --version 2>/dev/null)
    log_success "Node.js $installed_ver installed to ~/.hermes/node/"
    HAS_NODE=true
}

install_system_packages() {
    # Detect what's missing
    HAS_RIPGREP=false
    HAS_FFMPEG=false
    local need_ripgrep=false
    local need_ffmpeg=false

    log_info "Checking ripgrep (fast file search)..."
    if command -v rg &> /dev/null; then
        log_success "$(rg --version | head -1) found"
        HAS_RIPGREP=true
    else
        need_ripgrep=true
    fi

    log_info "Checking ffmpeg (TTS voice messages)..."
    if command -v ffmpeg &> /dev/null; then
        local ffmpeg_ver=$(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')
        log_success "ffmpeg $ffmpeg_ver found"
        HAS_FFMPEG=true
    else
        need_ffmpeg=true
    fi

    # Nothing to install — done
    if [ "$need_ripgrep" = false ] && [ "$need_ffmpeg" = false ]; then
        return 0
    fi

    # Build a human-readable description + package list
    local desc_parts=()
    local pkgs=()
    if [ "$need_ripgrep" = true ]; then
        desc_parts+=("ripgrep for faster file search")
        pkgs+=("ripgrep")
    fi
    if [ "$need_ffmpeg" = true ]; then
        desc_parts+=("ffmpeg for TTS voice messages")
        pkgs+=("ffmpeg")
    fi
    local description
    description=$(IFS=" and "; echo "${desc_parts[*]}")

    # ── macOS: brew ──
    if [ "$OS" = "macos" ]; then
        if command -v brew &> /dev/null; then
            log_info "Installing ${pkgs[*]} via Homebrew..."
            if brew install "${pkgs[@]}"; then
                [ "$need_ripgrep" = true ] && HAS_RIPGREP=true && log_success "ripgrep installed"
                [ "$need_ffmpeg" = true ]  && HAS_FFMPEG=true  && log_success "ffmpeg installed"
                return 0
            fi
        fi
        log_warn "Could not auto-install (brew not found or install failed)"
        log_info "Install manually: brew install ${pkgs[*]}"
        return 0
    fi

    # ── Linux: resolve package manager command ──
    local pkg_cmd=""
    local pkg_args=()

    if command -v apt-get &> /dev/null; then
        pkg_cmd="apt-get"
        pkg_args=("-qq" "install" "-y")
    elif command -v dnf &> /dev/null; then
        pkg_cmd="dnf"
        pkg_args=("-y" "install")
    elif command -v pacman &> /dev/null; then
        pkg_cmd="pacman"
        pkg_args=("-S" "--noconfirm" "--needed")
    elif command -v zypper &> /dev/null; then
        pkg_cmd="zypper"
        pkg_args=("--non-interactive" "install")
    elif command -v apk &> /dev/null; then
        pkg_cmd="apk"
        pkg_args=("add" "--no-cache")
    fi

    # Map generic package names to distro-specific names
    local distro_pkgs=()
    for p in "${pkgs[@]}"; do
        case "$p" in
            ripgrep)
                case "$pkg_cmd" in
                    apt-get) distro_pkgs+=("ripgrep") ;;
                    dnf)     distro_pkgs+=("ripgrep") ;;
                    pacman)  distro_pkgs+=("ripgrep") ;;
                    zypper)  distro_pkgs+=("ripgrep") ;;
                    apk)     distro_pkgs+=("ripgrep") ;;
                    *)       distro_pkgs+=("ripgrep") ;;
                esac
                ;;
            ffmpeg)
                distro_pkgs+=("ffmpeg")
                ;;
        esac
    done

    # Install
    if [ -n "$pkg_cmd" ]; then
        log_info "Installing ${distro_pkgs[*]} via $pkg_cmd..."
        if sudo "$pkg_cmd" "${pkg_args[@]}" "${distro_pkgs[@]}" 2>/dev/null; then
            [ "$need_ripgrep" = true ] && HAS_RIPGREP=true && log_success "ripgrep installed"
            [ "$need_ffmpeg" = true ]  && HAS_FFMPEG=true  && log_success "ffmpeg installed"
            return 0
        else
            log_warn "Package installation failed or was cancelled"
        fi
    else
        log_warn "Could not detect package manager"
    fi

    log_info "Install manually:"
    for p in "${pkgs[@]}"; do
        log_info "  - $p"
    done
}

clone_repo() {
    log_info "Installing to $INSTALL_DIR..."

    if [ -d "$INSTALL_DIR" ]; then
        if [ -d "$INSTALL_DIR/.git" ]; then
            log_info "Existing installation found, updating..."
            cd "$INSTALL_DIR"

            local autostash_ref=""
            if [ -n "$(git status --porcelain)" ]; then
                local stash_name
                stash_name="hermes-install-autostash-$(date -u +%Y%m%d-%H%M%S)"
                log_info "Local changes detected, stashing before update..."
                git stash push --include-untracked -m "$stash_name"
                autostash_ref="$(git rev-parse --verify refs/stash)"
            fi

            # Update remote URL to point to merged fork
            git remote set-url origin "$REPO_URL_HTTPS"
            
            git fetch origin
            git checkout "$BRANCH"
            git pull --ff-only origin "$BRANCH"

            if [ -n "$autostash_ref" ]; then
                local restore_now="yes"
                if [ -t 0 ] && [ -t 1 ]; then
                    echo
                    log_warn "Local changes were stashed before updating."
                    log_warn "Restoring them may reapply local customizations onto the updated codebase."
                    printf "Restore local changes now? [Y/n] "
                    read -r restore_answer
                    case "$restore_answer" in
                        ""|y|Y|yes|YES|Yes) restore_now="yes" ;;
                        *) restore_now="no" ;;
                    esac
                fi

                if [ "$restore_now" = "yes" ]; then
                    log_info "Restoring local changes..."
                    if git stash apply "$autostash_ref"; then
                        git stash drop "$autostash_ref" >/dev/null
                        log_warn "Local changes were restored on top of the updated codebase."
                        log_warn "Review git diff / git status if Hermes behaves unexpectedly."
                    else
                        log_error "Update succeeded, but restoring local changes failed. Your changes are still preserved in git stash."
                        log_info "Resolve manually with: git stash apply $autostash_ref"
                        exit 1
                    fi
                else
                    log_info "Skipped restoring local changes."
                    log_info "Your changes are still preserved in git stash."
                    log_info "Restore manually with: git stash apply $autostash_ref"
                fi
            fi
        else
            log_error "Directory exists but is not a git repository: $INSTALL_DIR"
            log_info "Remove it or choose a different directory with --dir"
            exit 1
        fi
    else
        # Try SSH first (for private repo access), fall back to HTTPS
        # GIT_SSH_COMMAND disables interactive prompts and sets a short timeout
        # so SSH fails fast instead of hanging when no key is configured.
        log_info "Trying SSH clone..."
        if GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=5" \
           git clone --branch "$BRANCH" "$REPO_URL_SSH" "$INSTALL_DIR" 2>/dev/null; then
            log_success "Cloned via SSH"
        else
            rm -rf "$INSTALL_DIR" 2>/dev/null  # Clean up partial SSH clone
            log_info "SSH failed, trying HTTPS..."
            if git clone --branch "$BRANCH" "$REPO_URL_HTTPS" "$INSTALL_DIR"; then
                log_success "Cloned via HTTPS"
            else
                log_error "Failed to clone repository"
                exit 1
            fi
        fi
    fi

    cd "$INSTALL_DIR"

    log_success "Repository ready (merged fork with webapi support)"
}

setup_venv() {
    if [ "$USE_VENV" = false ]; then
        log_info "Skipping virtual environment (--no-venv)"
        return 0
    fi

    log_info "Creating virtual environment with Python $PYTHON_VERSION..."

    if [ ! -d "venv" ]; then
        # Use uv to create the venv with the correct Python version
        $UV_CMD venv --python "$PYTHON_VERSION" venv
        log_success "Virtual environment created"
    else
        log_info "Virtual environment already exists, reusing"
    fi

    log_info "Installing Python dependencies (this may take a few minutes)..."

    # Install dependencies using uv pip (fast!)
    VENV_PYTHON="$INSTALL_DIR/venv/bin/python"
    $UV_CMD pip install --python "$VENV_PYTHON" -e "$INSTALL_DIR"

    log_success "Dependencies installed"
}

install_deps() {
    # Already done in setup_venv with uv pip
    :
}

install_node_deps() {
    log_info "Installing Node.js dependencies for browser tools..."

    cd "$INSTALL_DIR"

    if [ ! -f "package.json" ]; then
        log_warn "No package.json found, skipping Node.js dependencies"
        return 0
    fi

    # Check for pnpm, npm
    local pkg_manager=""
    if command -v pnpm &> /dev/null; then
        pkg_manager="pnpm"
    elif command -v npm &> /dev/null; then
        pkg_manager="npm"
    else
        log_warn "No package manager found (pnpm or npm), skipping Node.js dependencies"
        return 0
    fi

    # Prefer non-interactive installs
    if ! $pkg_manager install; then
        log_warn "Node.js dependency installation failed"
        log_info "Browser tools may not work correctly"
    else
        log_success "Node.js dependencies installed"
    fi
}

setup_path() {
    log_info "Setting up PATH..."

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    # Create wrapper script that activates the venv
    cat > "$bin_dir/hermes" << 'EOF'
#!/bin/bash
# Hermes CLI wrapper - auto-activates the virtual environment
HERMES_DIR="${HERMES_INSTALL_DIR:-$HOME/.hermes/hermes-agent}"

if [ -f "$HERMES_DIR/venv/bin/python" ]; then
    exec "$HERMES_DIR/venv/bin/python" -m hermes_cli.main "$@"
else
    echo "Error: Hermes not found at $HERMES_DIR"
    echo "Please reinstall: curl -fsSL ... | bash"
    exit 1
fi
EOF

    chmod +x "$bin_dir/hermes"

    # Create gateway wrapper
    cat > "$bin_dir/hermes-gateway" << 'EOF'
#!/bin/bash
# Hermes Gateway wrapper - for starting the gateway directly
HERMES_DIR="${HERMES_INSTALL_DIR:-$HOME/.hermes/hermes-agent}"

if [ -f "$HERMES_DIR/venv/bin/python" ]; then
    exec "$HERMES_DIR/venv/bin/python" -m hermes_cli.main gateway "$@"
else
    echo "Error: Hermes not found at $HERMES_DIR"
    exit 1
fi
EOF

    chmod +x "$bin_dir/hermes-gateway"

    # Ensure ~/.local/bin is on PATH
    local shell_rc=""
    case "$(basename "${SHELL:-/bin/bash}")" in
        zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        bash)
            shell_rc="$HOME/.bashrc"
            ;;
        *)
            shell_rc="$HOME/.bashrc"
            ;;
    esac

    if ! grep -q "$bin_dir" "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# Added by Hermes Agent installer" >> "$shell_rc"
        echo "export PATH=\"$bin_dir:\$PATH\"" >> "$shell_rc"
        log_info "Added $bin_dir to PATH in $shell_rc"
    fi

    log_success "PATH configured"
}

copy_config_templates() {
    log_info "Setting up configuration..."

    # Create directories
    mkdir -p "$HERMES_HOME"
    mkdir -p "$HERMES_HOME/cron"
    mkdir -p "$HERMES_HOME/logs"

    # Copy .env.example if .env doesn't exist
    if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
        cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
        log_info "Created ~/.hermes/.env from template"
    fi

    # Copy cli-config.yaml.example if config.yaml doesn't exist
    if [ ! -f "$HERMES_HOME/config.yaml" ] && [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
        cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
        log_info "Created ~/.hermes/config.yaml from template"
    fi
}

run_setup_wizard() {
    if [ "$RUN_SETUP" = false ]; then
        log_info "Skipping setup wizard (--skip-setup)"
        return 0
    fi

    # The setup wizard reads from /dev/tty, so it works even when the
    # install script itself is piped (curl | bash). Only skip if no
    # terminal is available at all (e.g. Docker build, CI).
    if ! [ -e /dev/tty ]; then
        log_info "Setup wizard skipped (no terminal available). Run 'hermes setup' after install."
        return 0
    fi

    echo ""
    log_info "Starting setup wizard..."
    echo ""

    cd "$INSTALL_DIR"

    # Run hermes setup using the venv Python directly (no activation needed).
    # Redirect stdin from /dev/tty so interactive prompts work when piped from curl.
    if [ "$USE_VENV" = true ]; then
        "$INSTALL_DIR/venv/bin/python" -m hermes_cli.main setup < /dev/tty
    else
        python -m hermes_cli.main setup < /dev/tty
    fi
}

maybe_start_gateway() {
    # Check if any messaging platform tokens were configured
    ENV_FILE="$HERMES_HOME/.env"
    if [ ! -f "$ENV_FILE" ]; then
        return 0
    fi

    HAS_MESSAGING=false
    for VAR in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN SLACK_APP_TOKEN WHATSAPP_ENABLED; do
        VAL=$(grep "^${VAR}=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$VAL" ] && [ "$VAL" != "your-token-here" ]; then
            HAS_MESSAGING=true
            break
        fi
    done

    if [ "$HAS_MESSAGING" = false ]; then
        return 0
    fi

    echo ""
    log_info "Messaging platform token detected!"
    log_info "The gateway needs to be running for Hermes to send/receive messages."

    # If WhatsApp is enabled and no session exists yet, run foreground first for QR scan
    WHATSAPP_VAL=$(grep "^WHATSAPP_ENABLED=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2-)
    WHATSAPP_SESSION="$HERMES_HOME/whatsapp/session/creds.json"
    if [ "$WHATSAPP_VAL" = "true" ] && [ ! -f "$WHATSAPP_SESSION" ]; then
        if [ "$IS_INTERACTIVE" = true ]; then
            echo ""
            log_info "WhatsApp is enabled but not yet paired."
            log_info "Running 'hermes whatsapp' to pair via QR code..."
            echo ""
            read -p "Pair WhatsApp now? [Y/n] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                HERMES_CMD="$HOME/.local/bin/hermes"
                [ ! -x "$HERMES_CMD" ] && HERMES_CMD="hermes"
                $HERMES_CMD whatsapp || true
            fi
        else
            log_info "WhatsApp pairing skipped (non-interactive). Run 'hermes whatsapp' to pair."
        fi
    fi

    if ! [ -e /dev/tty ]; then
        log_info "Gateway setup skipped (no terminal available). Run 'hermes gateway install' later."
        return 0
    fi

    echo ""
    read -p "Would you like to install the gateway as a background service? [Y/n] " -n 1 -r < /dev/tty
    echo

    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        HERMES_CMD="$HOME/.local/bin/hermes"
        if [ ! -x "$HERMES_CMD" ]; then
            HERMES_CMD="hermes"
        fi

        if command -v systemctl &> /dev/null; then
            log_info "Installing systemd service..."
            if $HERMES_CMD gateway install 2>/dev/null; then
                log_success "Gateway service installed"
                if $HERMES_CMD gateway start 2>/dev/null; then
                    log_success "Gateway started! Your bot is now online."
                else
                    log_warn "Service installed but failed to start. Try: hermes gateway start"
                fi
            else
                log_warn "Systemd install failed. You can start manually: hermes gateway"
            fi
        else
            log_info "systemd not available — starting gateway in background..."
            nohup $HERMES_CMD gateway > "$HERMES_HOME/logs/gateway.log" 2>&1 &
            GATEWAY_PID=$!
            log_success "Gateway started (PID $GATEWAY_PID). Logs: ~/.hermes/logs/gateway.log"
            log_info "To stop: kill $GATEWAY_PID"
            log_info "To restart later: hermes gateway"
        fi
    else
        log_info "Skipped. Start the gateway later with: hermes gateway"
    fi
}

print_success() {
    echo ""
    echo -e "${GREEN}${BOLD}"
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│        ✓ Installation Complete! (Merged Fork)           │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo ""

    # Show file locations
    echo -e "${CYAN}${BOLD}📁 Your files (all in ~/.hermes/):${NC}"
    echo ""
    echo -e "   ${YELLOW}Config:${NC}    ~/.hermes/config.yaml"
    echo -e "   ${YELLOW}API Keys:${NC}  ~/.hermes/.env"
    echo -e "   ${YELLOW}Data:${NC}      ~/.hermes/cron/, sessions/, logs/"
    echo -e "   ${YELLOW}Code:${NC}      ~/.hermes/hermes-agent/ (merged fork)"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}🚀 Commands:${NC}"
    echo ""
    echo -e "   ${GREEN}hermes${NC}              Start chatting (CLI)"
    echo -e "   ${GREEN}hermes --gateway${NC}    Start web API gateway (for workspace)"
    echo -e "   ${GREEN}hermes setup${NC}        Configure API keys & settings"
    echo -e "   ${GREEN}hermes config${NC}       View/edit configuration"
    echo -e "   ${GREEN}hermes update${NC}       Update to latest version"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${MAGENTA}${BOLD}🔗 WebAPI Support:${NC}"
    echo ""
    echo -e "   This installation includes webapi endpoints for Hermes Workspace:"
    echo -e "   ${CYAN}http://127.0.0.1:8642${NC}"
    echo ""
    echo -e "   Endpoints: /health, /v1/models, /v1/chat/completions"
    echo -e "              /api/skills, /api/sessions, /api/memory, /api/config"
    echo ""

    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${YELLOW}⚡ Reload your shell to use 'hermes' command:${NC}"
    echo ""
    LOGIN_SHELL="$(basename "${SHELL:-/bin/bash}")"
    if [ "$LOGIN_SHELL" = "zsh" ]; then
        echo "   source ~/.zshrc"
    elif [ "$LOGIN_SHELL" = "bash" ]; then
        echo "   source ~/.bashrc"
    else
        echo "   source ~/.bashrc   # or ~/.zshrc"
    fi
    echo ""

    # Show Node.js warning if auto-install failed
    if [ "$HAS_NODE" = false ]; then
        echo -e "${YELLOW}"
        echo "Note: Node.js could not be installed automatically."
        echo "Browser tools need Node.js. Install manually:"
        echo "  https://nodejs.org/en/download/"
        echo -e "${NC}"
    fi

    # Show ripgrep note if not installed
    if [ "$HAS_RIPGREP" = false ]; then
        echo -e "${YELLOW}"
        echo "Note: ripgrep (rg) was not found. File search will use"
        echo "grep as a fallback. For faster search in large codebases,"
        echo "install ripgrep: sudo apt install ripgrep (or brew install ripgrep)"
        echo -e "${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner

    detect_os
    install_uv
    check_python
    check_git
    check_node
    install_system_packages

    clone_repo
    setup_venv
    install_deps
    install_node_deps
    setup_path
    copy_config_templates
    run_setup_wizard
    maybe_start_gateway

    print_success
}

main
