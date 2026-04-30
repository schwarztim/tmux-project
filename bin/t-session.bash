#!/usr/bin/env bash
# t-session.bash — Project-first tmux session manager (bash version)
# Source this from ~/.bashrc:  source /path/to/tmux-project/bin/t-session.bash
# Requires bash 4.0+ for associative arrays.

if (( BASH_VERSINFO[0] < 4 )); then
    echo "tmux-project: bash 4.0+ is required. Use zsh or install a newer bash." >&2
    if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
        exit 1
    fi
    return 1
fi

# Config locations
: "${TMUX_PROJECT_DIR:=$HOME/.config/tmux-project}"
: "${TMUX_PROJECT_PATHS:=$TMUX_PROJECT_DIR/workspace-paths}"
: "${TMUX_PROJECT_HOOKS:=$TMUX_PROJECT_DIR/hooks}"
: "${TMUX_PROJECT_DEFAULT_DIR:=$HOME/Projects}"
: "${TMUX_PROJECT_FAVORITES:=$TMUX_PROJECT_DIR/favorites}"

declare -A _TP_PROJECTS=()
declare -A _TP_ALIASES=()
declare -A _TP_FAVORITES=()

_tp_load_aliases() {
    _TP_ALIASES=()
    local af="$TMUX_PROJECT_DIR/aliases"
    [[ -f "$af" ]] || return 0
    while IFS='=' read -r name short; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        _TP_ALIASES["$name"]="$short"
    done < "$af"
}

_tp_load_projects() {
    _TP_PROJECTS=()
    [[ -f "$TMUX_PROJECT_PATHS" ]] || return 0

    _tp_load_aliases

    local name project_path short
    while IFS='=' read -r name project_path; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        short="${_TP_ALIASES[$name]:-$name}"
        _TP_PROJECTS["$short"]="$project_path"
    done < "$TMUX_PROJECT_PATHS"
}

_tp_load_favorites() {
    _TP_FAVORITES=()
    [[ -f "$TMUX_PROJECT_FAVORITES" ]] || return 0

    local name
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        _TP_FAVORITES["$name"]=1
    done < "$TMUX_PROJECT_FAVORITES"
}

_tp_is_favorite() {
    local project_name="$1"
    [[ -n "${_TP_FAVORITES[$project_name]:-}" ]]
}

_tp_toggle_favorite() {
    local project_name="$1"
    local tmp_file="${TMUX_PROJECT_FAVORITES}.tmp.$$"
    local favorite

    [[ -n "${_TP_PROJECTS[$project_name]:-}" ]] || return 1
    mkdir -p "$TMUX_PROJECT_DIR"
    _tp_load_favorites

    if _tp_is_favorite "$project_name"; then
        for favorite in "${!_TP_FAVORITES[@]}"; do
            [[ "$favorite" == "$project_name" ]] || printf '%s\n' "$favorite"
        done | sort > "$tmp_file"
    else
        {
            for favorite in "${!_TP_FAVORITES[@]}"; do
                printf '%s\n' "$favorite"
            done
            printf '%s\n' "$project_name"
        } | sort -u > "$tmp_file"
    fi

    mv "$tmp_file" "$TMUX_PROJECT_FAVORITES"
    _tp_load_favorites
}

_tp_session_matches_project() {
    local session_name="$1" project_name="$2"
    [[ "$session_name" == "$project_name" || "$session_name" == "${project_name}/"* ]]
}

_tp_session_line_for() {
    local session_name="$1" session_line
    while IFS= read -r session_line; do
        [[ "$session_line" == "${session_name}  "* ]] && {
            printf '%s\n' "$session_line"
            return 0
        }
    done
    return 1
}

_tp_clean_name() {
    local value="$1"
    value="${value#$'\n'}"
    value="${value#\\n}"
    printf '%s' "$value"
}

_tp_in_tmux_picker() {
    local _fzf="$1" _tmux="$2"

    # Prefer sesh if available
    local _sesh
    _sesh=$(command -v sesh 2>/dev/null)
    if [[ -n "$_sesh" ]]; then
        "$_sesh" connect "$("$_sesh" list --icons | "$_fzf" --no-sort --ansi \
            --border-label ' sesh ' --prompt '> ' \
            --header '  ^a all ^t tmux ^x zoxide ^d kill' \
            --bind "ctrl-a:change-prompt(> )+reload($_sesh list --icons)" \
            --bind "ctrl-t:change-prompt(tmux> )+reload($_sesh list -t --icons)" \
            --bind "ctrl-x:change-prompt(dir> )+reload($_sesh list -z --icons)" \
            --bind "ctrl-d:execute($_tmux kill-session -t {2..})+reload($_sesh list --icons)")"
    else
        # Fallback: plain fzf + tmux list
        local choice
        choice=$("$_tmux" list-sessions -F "#{session_name}  (#{session_windows} windows)" 2>/dev/null | \
            "$_fzf" --no-sort --ansi \
                --border-label ' sessions ' --prompt '> ' \
                --header '  Enter=switch  ^d=kill' \
                --bind "ctrl-d:execute-silent($_tmux kill-session -t \"\$(echo {} | sed 's/  .*//')\" 2>/dev/null)+reload($_tmux list-sessions -F '#{session_name}  (#{session_windows} windows)')")
        [[ -z "$choice" ]] && return
        local name="${choice%%  *}"
        "$_tmux" switch-client -t "$name"
    fi
}

t() {
    local _fzf _tmux
    _fzf=$(command -v fzf 2>/dev/null)
    _tmux=$(command -v tmux 2>/dev/null)

    if [[ -z "$_fzf" ]]; then
        echo "tmux-project: fzf is required. Install from https://github.com/junegunn/fzf" >&2
        return 1
    fi
    if [[ -z "$_tmux" ]]; then
        echo "tmux-project: tmux is required." >&2
        return 1
    fi

    # Ensure config dir exists
    [[ -d "$TMUX_PROJECT_DIR" ]] || mkdir -p "$TMUX_PROJECT_DIR"

    # If already in tmux, use session picker
    if [[ -n "$TMUX" ]]; then
        _tp_in_tmux_picker "$_fzf" "$_tmux"
        return
    fi

    # Load projects from workspace-paths
    _tp_load_projects
    _tp_load_favorites

    # Build sorted project list
    local sorted_projects
    sorted_projects=$(for p in "${!_TP_PROJECTS[@]}"; do echo "$p"; done | sort)

    # Build project list with session counts
    local project_lines="" favorite_lines="" active_lines="" inactive_lines=""
    local all_sessions all_session_lines
    all_sessions=$("$_tmux" list-sessions -F "#{session_name}" 2>/dev/null) || true
    all_session_lines=$("$_tmux" list-sessions -F "#{session_name}  (#{session_windows} windows)" 2>/dev/null) || true

    while IFS= read -r proj; do
        [[ -z "$proj" ]] && continue
        local count=0
        if [[ -n "$all_sessions" ]]; then
            local sess
            while IFS= read -r sess; do
                _tp_session_matches_project "$sess" "$proj" && count=$((count + 1))
            done <<< "$all_sessions"
        fi
        local line="$proj"
        _tp_is_favorite "$proj" && line+="  *"
        if (( count > 0 )); then
            line+="  +${count}"
        fi

        if _tp_is_favorite "$proj"; then
            favorite_lines+="${line}"$'\n'
        elif (( count > 0 )); then
            active_lines+="${line}"$'\n'
        else
            inactive_lines+="${line}"$'\n'
        fi
    done <<< "$sorted_projects"
    project_lines="${favorite_lines}${active_lines}${inactive_lines}"

    # Show orphan sessions (not under any project)
    local orphan_count=0
    if [[ -n "$all_sessions" ]]; then
        while IFS= read -r sess; do
            [[ -z "$sess" ]] && continue
            local is_project=0
            for proj in "${!_TP_PROJECTS[@]}"; do
                _tp_session_matches_project "$sess" "$proj" && is_project=1 && break
            done
            (( is_project == 0 )) && orphan_count=$((orphan_count + 1))
        done <<< "$all_sessions"
    fi
    if (( orphan_count > 0 )); then
        project_lines+="---"$'\n'
        project_lines+="other  (${orphan_count} sessions)"$'\n'
    fi

    # Step 1: Pick a project
    local picker_output picker_key="" proj_choice
    picker_output=$(printf "%s\n%s" "+ New Project" "$project_lines" | "$_fzf" --no-sort --ansi \
        --border-label ' projects ' --prompt '> ' \
        --header '  Pick a project | F=pin/unpin favorite' \
        --pointer '>' --cycle \
        --expect=F)

    [[ -z "$picker_output" ]] && return
    if [[ "$picker_output" == F$'\n'* ]]; then
        picker_key="F"
        proj_choice="${picker_output#*$'\n'}"
    else
        proj_choice="$picker_output"
    fi
    proj_choice=$(_tp_clean_name "$proj_choice")

    if [[ "$picker_key" == "F" ]]; then
        local favorite_project
        favorite_project=$(_tp_clean_name "${proj_choice%%  *}")
        [[ -n "$favorite_project" ]] && _tp_toggle_favorite "$favorite_project"
        t
        return
    fi

    # Handle new project creation
    if [[ "$proj_choice" == "+ New Project" ]]; then
        printf "Project name (short): "
        local new_name
        read -r new_name
        new_name=$(_tp_clean_name "$new_name")
        [[ -z "$new_name" ]] && return

        local new_path="${TMUX_PROJECT_DEFAULT_DIR}/$new_name"
        # bash uses read -e for readline editing (instead of zsh vared)
        printf "Project path [%s]: " "$new_path"
        local user_path
        read -re -i "$new_path" user_path
        [[ -n "$user_path" ]] && new_path="$user_path"
        [[ -z "$new_path" ]] && return
        new_path="${new_path/#\~/$HOME}"

        if [[ ! -d "$new_path" ]]; then
            mkdir -p "$new_path"
        fi

        # Register in workspace-paths
        echo "${new_name}=${new_path}" >> "$TMUX_PROJECT_PATHS"
        sort -o "$TMUX_PROJECT_PATHS" "$TMUX_PROJECT_PATHS"
        _tp_load_projects
        echo "Registered: $new_name -> $new_path"

        # Run onboard hook if present
        local hook="$TMUX_PROJECT_HOOKS/on-new-project.sh"
        if [[ -x "$hook" ]]; then
            "$hook" "$new_name" "$new_path"
        fi

        # Create first session
        printf "Session label (creates %s/<label>): " "$new_name"
        local label
        read -r label
        label=$(_tp_clean_name "$label")
        [[ -z "$label" ]] && return
        "$_tmux" new-session -s "${new_name}/${label}" -c "$new_path"
        return
    fi

    local proj_name
    proj_name=$(_tp_clean_name "${proj_choice%%  *}")
    [[ "$proj_name" == "---" ]] && return

    # Step 2: Show sessions for that project
    local proj_sessions=""
    local NEW="+ New Session"

    if [[ "$proj_name" == "other" ]]; then
        if [[ -n "$all_sessions" ]]; then
            while IFS= read -r sess; do
                [[ -z "$sess" ]] && continue
                local is_project=0
                for proj in "${!_TP_PROJECTS[@]}"; do
                    _tp_session_matches_project "$sess" "$proj" && is_project=1 && break
                done
                if (( is_project == 0 )); then
                    local wins
                    wins=$(_tp_session_line_for "$sess" <<< "$all_session_lines")
                    proj_sessions+="${wins}"$'\n'
                fi
            done <<< "$all_sessions"
        fi
    else
        if [[ -n "$all_sessions" ]]; then
            while IFS= read -r sess; do
                [[ -z "$sess" ]] && continue
                if _tp_session_matches_project "$sess" "$proj_name"; then
                    local wins
                    wins=$(_tp_session_line_for "$sess" <<< "$all_session_lines")
                    proj_sessions+="${wins}"$'\n'
                fi
            done <<< "$all_sessions"
        fi
    fi

    local sess_choice
    if [[ -n "${proj_sessions//[$'\n']/}" ]]; then
        sess_choice=$(printf "%s\n%s" "$NEW" "$proj_sessions" | sed '/^$/d' | "$_fzf" --no-sort --ansi \
            --border-label " ${proj_name} sessions " --prompt '> ' \
            --header '  Enter=attach  k=kill' \
            --pointer '>' --cycle \
            --bind "k:execute-silent($_tmux kill-session -t \"\$(echo {} | sed 's/  .*//')\" 2>/dev/null)+reload(echo '+ New Session'; $_tmux list-sessions -F '#{session_name}  (#{session_windows} windows)' 2>/dev/null | grep '^${proj_name}/')")
    else
        sess_choice="$NEW"
    fi

    [[ -z "$sess_choice" ]] && return

    if [[ "$sess_choice" == "$NEW" ]]; then
        if [[ "$proj_name" == "other" ]]; then
            printf "Session name: "
            local label
            read -r label
            label=$(_tp_clean_name "$label")
            [[ -z "$label" ]] && return
            "$_tmux" new-session -s "$label"
        else
            printf "Session label (creates %s/<label>): " "$proj_name"
            local label
            read -r label
            label=$(_tp_clean_name "$label")
            [[ -z "$label" ]] && return
            local session_name="${proj_name}/${label}"
            local proj_path="${_TP_PROJECTS[$proj_name]}"
            "$_tmux" new-session -s "$session_name" -c "$proj_path"
        fi
    else
        local name
        name=$(_tp_clean_name "${sess_choice%%  *}")
        "$_tmux" attach-session -t "$name"
    fi
}

# Help alias
alias thelp='echo "
  tmux-project — Project-first tmux session manager
  ===================================================
  Launcher:
    t            Project picker -> session picker / new (F pins/unpins favorite)

  Inside tmux:
    t            Session switcher (sesh if available, fzf fallback)

  Sessions:
    Named {project}/{label} (e.g. myapp/frontend)
    Kitty tab shows session name automatically (if kitty detected)

  Config:
     \$TMUX_PROJECT_DIR/workspace-paths   Project registry (name=path)
     \$TMUX_PROJECT_DIR/aliases           Display name overrides
     \$TMUX_PROJECT_DIR/favorites         Pinned projects
     \$TMUX_PROJECT_DIR/hooks/            Lifecycle hooks

  Env vars:
     TMUX_PROJECT_DIR         Config dir (default: ~/.config/tmux-project)
     TMUX_PROJECT_DEFAULT_DIR Default new project parent (default: ~/Projects)
     TMUX_PROJECT_FAVORITES   Favorites file
"'
