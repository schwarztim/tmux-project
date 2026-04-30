#!/bin/bash
# tmux-project installer — modular, per-component
# Run: bash install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${TMUX_PROJECT_DIR:-$HOME/.config/tmux-project}"
PROJECT_ROOTS_FILE="${TMUX_PROJECT_ROOTS:-$CONFIG_DIR/project-roots}"

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    BOLD='\033[1m' GREEN='\033[32m' YELLOW='\033[33m' RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RESET=''
fi

info()  { printf "${GREEN}[+]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
header() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# --- Dependency check ---
check_deps() {
    local missing=()
    command -v tmux &>/dev/null || missing+=(tmux)
    command -v fzf  &>/dev/null || missing+=(fzf)
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing required tools: ${missing[*]}"
        echo "  tmux: https://github.com/tmux/tmux"
        echo "  fzf:  https://github.com/junegunn/fzf"
        echo ""
        read -rp "Continue anyway? [y/N] " ans
        [[ "$ans" =~ ^[yY] ]] || exit 1
    fi

    if command -v sesh &>/dev/null; then
        info "sesh detected — in-tmux session switching will use sesh"
    else
        info "sesh not found — in-tmux session switching will use fzf fallback"
        echo "  Optional: https://github.com/joshmedeski/sesh"
    fi
}

# --- Detect shell ---
detect_shell() {
    local sh
    sh=$(basename "${SHELL:-/bin/bash}")
    case "$sh" in
        zsh)  echo "zsh" ;;
        bash) echo "bash" ;;
        *)    echo "bash" ;; # default to bash
    esac
}

detect_rc_file() {
    local shell_type="$1"
    case "$shell_type" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash)
            if [[ -f "$HOME/.bash_profile" ]] && [[ "$(uname -s)" == "Darwin" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
    esac
}

expand_path() {
    local value="$1"
    value="${value/#\~/$HOME}"
    printf '%s' "$value"
}

root_label_for_path() {
    local root_path="${1%/}"
    local label="${root_path##*/}"
    [[ -n "$label" ]] || label="root"
    printf '%s' "$label"
}

migrate_legacy_config() {
    local target_paths="$CONFIG_DIR/workspace-paths"
    local target_aliases="$CONFIG_DIR/aliases"
    local legacy_paths="${TMUX_PROJECT_LEGACY_PATHS:-$HOME/claude-rules/.workspace-paths}"
    local legacy_session="${TMUX_PROJECT_LEGACY_SESSION:-$HOME/claude-rules/shell/t-session.zsh}"

    if [[ ! -s "$target_paths" && -f "$legacy_paths" ]]; then
        cp "$legacy_paths" "$target_paths"
        info "Imported project registry from $legacy_paths"
    else
        [[ -f "$target_paths" ]] || touch "$target_paths"
    fi

    if [[ ! -s "$target_aliases" && -f "$legacy_session" ]]; then
        local tmp_aliases="${target_aliases}.tmp"
        awk '
            /^[[:space:]]*\[[^]]+\]=/ {
                line = $0
                sub(/^[[:space:]]*\[/, "", line)
                sub(/\][[:space:]]*=/, "=", line)
                print line
            }
        ' "$legacy_session" > "$tmp_aliases"
        if [[ -s "$tmp_aliases" ]]; then
            mv "$tmp_aliases" "$target_aliases"
            info "Imported project aliases from $legacy_session"
        else
            rm -f "$tmp_aliases"
        fi
    fi
}

seed_project_roots() {
    mkdir -p "$CONFIG_DIR"
    if [[ ! -s "$PROJECT_ROOTS_FILE" ]]; then
        local default_root
        default_root=$(expand_path "${TMUX_PROJECT_DEFAULT_DIR:-$HOME/Projects}")
        mkdir -p "$default_root"
        printf '%s\n' "$default_root" > "$PROJECT_ROOTS_FILE"
        info "Default project root: $default_root"
    fi
}

configure_project_roots() {
    header "Project Roots"
    mkdir -p "$CONFIG_DIR"

    echo "Project roots are parent folders whose direct child directories appear in the picker."
    echo "Add as many roots as you want, across macOS, Linux, WSL, or Git Bash paths."
    echo "Format stored in $PROJECT_ROOTS_FILE:"
    echo "  /path/to/projects"
    echo "  work=/path/to/work-projects"
    echo ""

    if [[ -s "$PROJECT_ROOTS_FILE" ]]; then
        echo "Current roots:"
        sed 's/^/  /' "$PROJECT_ROOTS_FILE"
        echo ""
        read -rp "Replace existing project roots? [y/N] " ans
        if [[ "$ans" =~ ^[yY] ]]; then
            : > "$PROJECT_ROOTS_FILE"
        fi
    fi

    if [[ -s "$PROJECT_ROOTS_FILE" ]]; then
        read -rp "Add another project root? [y/N] " ans
        [[ "$ans" =~ ^[yY] ]] || return
    else
        read -rp "Configure project roots now? [Y/n] " ans
        if [[ "$ans" =~ ^[nN] ]]; then
            seed_project_roots
            return
        fi
    fi

    while true; do
        local default_root root_path root_label root_entry create_ans another_ans
        default_root=$(expand_path "${TMUX_PROJECT_DEFAULT_DIR:-$HOME/Projects}")
        read -rp "Project root path [$default_root]: " root_path
        root_path="${root_path:-$default_root}"
        root_path=$(expand_path "$root_path")
        root_path="${root_path%/}"
        [[ -n "$root_path" ]] || continue

        if [[ ! -d "$root_path" ]]; then
            read -rp "Create $root_path? [Y/n] " create_ans
            [[ "$create_ans" =~ ^[nN] ]] || mkdir -p "$root_path"
        fi

        read -rp "Optional root label [$(root_label_for_path "$root_path")]: " root_label
        if [[ -n "$root_label" ]]; then
            root_entry="${root_label}=${root_path}"
        else
            root_entry="$root_path"
        fi

        if ! grep -qxF "$root_entry" "$PROJECT_ROOTS_FILE" 2>/dev/null; then
            printf '%s\n' "$root_entry" >> "$PROJECT_ROOTS_FILE"
            info "Added project root: $root_entry"
        else
            warn "Project root already configured: $root_entry"
        fi

        read -rp "Add another project root? [y/N] " another_ans
        [[ "$another_ans" =~ ^[yY] ]] || break
    done

    seed_project_roots
}

# --- Component installers ---

install_session_manager() {
    local mode="${1:-interactive}"
    header "Session Manager (t function)"
    local shell_type
    shell_type=$(detect_shell)
    local source_file="$SCRIPT_DIR/bin/t-session.${shell_type}"

    if [[ ! -f "$source_file" ]]; then
        warn "No session manager for shell: $shell_type"
        return 1
    fi

    local rc_file
    rc_file=$(detect_rc_file "$shell_type")

    local source_line="source \"${source_file}\""

    if grep -qF "$source_line" "$rc_file" 2>/dev/null; then
        warn "Session manager already sourced from this install path in $rc_file — skipping"
    else
        if grep -qF "t-session" "$rc_file" 2>/dev/null; then
            warn "Existing t-session source found in $rc_file — appending tmux-project after it so this version wins"
        fi
        {
            echo ""
            echo "# tmux-project session manager"
            echo "$source_line"
        } >> "$rc_file"
        info "Added to $rc_file"
    fi

    # Create config dir and empty workspace-paths if needed
    mkdir -p "$CONFIG_DIR/hooks"
    migrate_legacy_config
    if [[ "$mode" == "interactive" ]]; then
        configure_project_roots
    else
        seed_project_roots
    fi
    info "Config directory: $CONFIG_DIR"
}

install_status_bar() {
    header "Status Bar"

    # Symlink the dispatcher to config dir for tmux.conf to find
    mkdir -p "$CONFIG_DIR"
    local target="$CONFIG_DIR/status.sh"

    if [[ -L "$target" || -f "$target" ]]; then
        warn "Status script already exists at $target — replacing"
        rm -f "$target"
    fi

    ln -s "$SCRIPT_DIR/status/status.sh" "$target"
    chmod +x "$SCRIPT_DIR/status/"*.sh
    info "Linked $target -> status/status.sh (auto-detects OS)"
}

install_tmux_conf() {
    header "tmux Configuration"

    local tmux_conf="$HOME/.tmux.conf"
    local source_line="source-file \"${SCRIPT_DIR}/conf/tmux.conf\""

    if [[ ! -f "$tmux_conf" ]]; then
        {
            echo "# tmux configuration"
            echo "$source_line"
        } > "$tmux_conf"
        info "Created $tmux_conf"
    elif grep -qF "tmux-project" "$tmux_conf" 2>/dev/null; then
        warn "tmux-project already referenced in $tmux_conf — skipping"
    else
        {
            echo ""
            echo "# tmux-project base config"
            echo "$source_line"
        } >> "$tmux_conf"
        info "Added source line to $tmux_conf"
    fi

    # Kitty detection
    if [[ "$TERM" == *kitty* || -n "${KITTY_PID:-}" ]]; then
        local kitty_line="source-file \"${SCRIPT_DIR}/conf/tmux-kitty.conf\""
        if ! grep -qF "tmux-kitty" "$tmux_conf" 2>/dev/null; then
            echo "$kitty_line" >> "$tmux_conf"
            info "Kitty detected — added kitty overrides"
        fi
    else
        info "Not kitty terminal — session name shown in tmux status bar"
    fi
}

install_hooks() {
    header "Example Hooks"
    mkdir -p "$CONFIG_DIR/hooks"
    if [[ ! -f "$CONFIG_DIR/hooks/on-new-project.sh" ]]; then
        cp "$SCRIPT_DIR/hooks/on-new-project.example.sh" "$CONFIG_DIR/hooks/on-new-project.example.sh"
        info "Example hook copied to $CONFIG_DIR/hooks/"
        echo "  To enable: cp on-new-project.example.sh on-new-project.sh && chmod +x on-new-project.sh"
    else
        warn "on-new-project.sh already exists — not overwriting"
    fi
}

# --- Main ---
main() {
    printf '%b\n' "${BOLD}tmux-project installer${RESET}"
    echo "Components: session-manager, status-bar, tmux-conf, hooks"
    echo ""

    check_deps

    if [[ "${1:-}" == "--all" ]]; then
        install_session_manager automatic
        install_status_bar
        install_tmux_conf
        install_hooks
    else
        echo ""
        read -rp "Install session manager (t function)? [Y/n] " ans
        [[ ! "$ans" =~ ^[nN] ]] && install_session_manager interactive

        read -rp "Install status bar (CPU/MEM/NET/battery)? [Y/n] " ans
        [[ ! "$ans" =~ ^[nN] ]] && install_status_bar

        read -rp "Install tmux config? [Y/n] " ans
        [[ ! "$ans" =~ ^[nN] ]] && install_tmux_conf

        read -rp "Install example hooks? [Y/n] " ans
        [[ ! "$ans" =~ ^[nN] ]] && install_hooks
    fi

    header "Done!"
    local shell_type rc_file
    shell_type=$(detect_shell)
    rc_file=$(detect_rc_file "$shell_type")
    echo "  Restart your shell or run: source $rc_file"
    echo "  Then type 't' to launch the project picker."
    echo "  Type 'thelp' for usage info."
    echo ""
}

main "$@"
