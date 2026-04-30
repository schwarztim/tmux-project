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
: "${TMUX_PROJECT_ROOTS:=$TMUX_PROJECT_DIR/project-roots}"
: "${TMUX_PROJECT_HOOKS:=$TMUX_PROJECT_DIR/hooks}"
: "${TMUX_PROJECT_DEFAULT_DIR:=$HOME/Projects}"
: "${TMUX_PROJECT_FAVORITES:=$TMUX_PROJECT_DIR/favorites}"

declare -A _TP_PROJECTS=()
declare -A _TP_ALIASES=()
declare -A _TP_FAVORITES=()
declare -A _TP_PROJECT_ROOT_LABELS=()
declare -A _TP_PROJECT_ROOT_BASES=()

_tp_load_aliases() {
    _TP_ALIASES=()
    local af="$TMUX_PROJECT_DIR/aliases"
    [[ -f "$af" ]] || return 0
    while IFS='=' read -r name short; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        _TP_ALIASES["$name"]="$short"
    done < "$af"
}

_tp_expand_path() {
    local value="$1"
    value="${value/#\~/$HOME}"
    printf '%s' "$value"
}

_tp_root_label_for_path() {
    local root_path="${1%/}"
    local label="${root_path##*/}"
    [[ -n "$label" ]] || label="root"
    printf '%s' "$label"
}

_tp_unique_project_name() {
    local candidate="$1" project_path="$2"
    local base="$candidate" index=2
    while [[ -n "${_TP_PROJECTS[$candidate]+_}" && "${_TP_PROJECTS[$candidate]}" != "$project_path" ]]; do
        candidate="${base}-${index}"
        index=$((index + 1))
    done
    printf '%s' "$candidate"
}

_tp_add_project() {
    local raw_name="$1" project_path="$2" root_label="${3:-}"
    [[ -z "$raw_name" || -z "$project_path" ]] && return 0

    local display="${_TP_ALIASES[$raw_name]:-$raw_name}"
    local candidate="$display"

    if [[ -n "$root_label" && -n "${_TP_PROJECT_ROOT_BASES[$display]:-}" && -z "${_TP_PROJECTS[$candidate]+_}" ]]; then
        candidate="${root_label}/${display}"
    fi

    if [[ -n "${_TP_PROJECTS[$candidate]+_}" ]]; then
        [[ "${_TP_PROJECTS[$candidate]}" == "$project_path" ]] && return 0
        local existing_path="${_TP_PROJECTS[$candidate]}"
        local existing_root_label="${_TP_PROJECT_ROOT_LABELS[$candidate]:-}"
        if [[ -n "$existing_root_label" ]]; then
            unset "_TP_PROJECTS[$candidate]"
            unset "_TP_PROJECT_ROOT_LABELS[$candidate]"
            local existing_candidate
            existing_candidate=$(_tp_unique_project_name "${existing_root_label}/${display}" "$existing_path")
            _TP_PROJECTS["$existing_candidate"]="$existing_path"
            _TP_PROJECT_ROOT_LABELS["$existing_candidate"]="$existing_root_label"
        fi

        if [[ -n "$root_label" ]]; then
            candidate="${root_label}/${display}"
        else
            candidate="${display}-2"
        fi

        candidate=$(_tp_unique_project_name "$candidate" "$project_path")
    fi

    _TP_PROJECTS["$candidate"]="$project_path"
    [[ -n "$root_label" ]] && _TP_PROJECT_ROOT_LABELS["$candidate"]="$root_label"
    [[ -n "$root_label" ]] && _TP_PROJECT_ROOT_BASES["$display"]=1
}

_tp_load_root_projects() {
    [[ -f "$TMUX_PROJECT_ROOTS" ]] || return 0

    local entry root_label root_path project_dir name nullglob_was_set
    shopt -q nullglob
    nullglob_was_set=$?
    shopt -s nullglob

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        if [[ "$entry" == *=* ]]; then
            root_label="${entry%%=*}"
            root_path="${entry#*=}"
        else
            root_label=""
            root_path="$entry"
        fi

        root_path=$(_tp_expand_path "$root_path")
        root_path="${root_path%/}"
        [[ -d "$root_path" ]] || continue
        [[ -n "$root_label" ]] || root_label=$(_tp_root_label_for_path "$root_path")

        for project_dir in "$root_path"/*; do
            [[ -d "$project_dir" ]] || continue
            name="${project_dir##*/}"
            [[ -z "$name" || "$name" == .* ]] && continue
            _tp_add_project "$name" "${project_dir%/}" "$root_label"
        done
    done < "$TMUX_PROJECT_ROOTS"

    (( nullglob_was_set == 0 )) || shopt -u nullglob
}

_tp_load_projects() {
    _TP_PROJECTS=()
    _TP_PROJECT_ROOT_LABELS=()
    _TP_PROJECT_ROOT_BASES=()

    _tp_load_aliases

    if [[ -f "$TMUX_PROJECT_PATHS" ]]; then
        local name project_path
        while IFS='=' read -r name project_path; do
            [[ -z "$name" || "$name" == \#* ]] && continue
            project_path=$(_tp_expand_path "$project_path")
            _tp_add_project "$name" "$project_path"
        done < "$TMUX_PROJECT_PATHS"
    fi

    _tp_load_root_projects
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

_tp_select_project_root() {
    local _fzf="$1"
    local root_lines="" count=0 entry root_label root_path choice
    local root_delim=$'\t'

    if [[ -f "$TMUX_PROJECT_ROOTS" ]]; then
        while IFS= read -r entry; do
            [[ -z "$entry" || "$entry" == \#* ]] && continue
            if [[ "$entry" == *=* ]]; then
                root_label="${entry%%=*}"
                root_path="${entry#*=}"
            else
                root_label=""
                root_path="$entry"
            fi

            root_path=$(_tp_expand_path "$root_path")
            root_path="${root_path%/}"
            [[ -n "$root_path" ]] || continue
            [[ -n "$root_label" ]] || root_label=$(_tp_root_label_for_path "$root_path")
            root_lines+="${root_label}${root_delim}${root_path}"$'\n'
            count=$((count + 1))
        done < "$TMUX_PROJECT_ROOTS"
    fi

    if (( count == 0 )); then
        _tp_expand_path "$TMUX_PROJECT_DEFAULT_DIR"
    elif (( count == 1 )); then
        root_lines="${root_lines%$'\n'}"
        printf '%s\n' "$root_lines" | cut -f 2-
    else
        choice=$(printf '%s' "$root_lines" | "$_fzf" --no-sort --ansi \
            --border-label ' project roots ' --prompt 'root> ' \
            --header '  Pick parent folder for the new project' \
            --pointer '>' --cycle)
        [[ -z "$choice" ]] && return 1
        printf '%s\n' "$choice" | cut -f 2-
    fi
}

troot() {
    local cmd="${1:-list}"
    shift 2>/dev/null || true
    mkdir -p "$TMUX_PROJECT_DIR"
    touch "$TMUX_PROJECT_ROOTS"

    case "$cmd" in
        list)
            if [[ -s "$TMUX_PROJECT_ROOTS" ]]; then
                nl -ba "$TMUX_PROJECT_ROOTS"
            else
                echo "tmux-project: no project roots configured"
            fi
            ;;
        add)
            local create=0
            if [[ "${1:-}" == "--create" ]]; then
                create=1
                shift
            fi
            local entry="$*"
            if [[ -z "$entry" ]]; then
                echo "usage: troot add [--create] [label=]/path" >&2
                return 2
            fi

            local label="" root_path root_entry
            if [[ "$entry" == *=* ]]; then
                label="${entry%%=*}"
                root_path="${entry#*=}"
            else
                root_path="$entry"
            fi
            root_path=$(_tp_expand_path "$root_path")
            root_path="${root_path%/}"
            if [[ ! -d "$root_path" ]]; then
                if (( create )); then
                    mkdir -p "$root_path"
                else
                    echo "tmux-project: root does not exist: $root_path" >&2
                    echo "rerun with: troot add --create ${entry}" >&2
                    return 1
                fi
            fi

            if [[ -n "$label" ]]; then
                root_entry="${label}=${root_path}"
            else
                root_entry="$root_path"
            fi
            if grep -qxF "$root_entry" "$TMUX_PROJECT_ROOTS" 2>/dev/null; then
                echo "tmux-project: root already configured: $root_entry"
            else
                printf '%s\n' "$root_entry" >> "$TMUX_PROJECT_ROOTS"
                echo "tmux-project: added root: $root_entry"
            fi
            ;;
        remove|rm|delete)
            local target="$*"
            if [[ -z "$target" ]]; then
                echo "usage: troot remove <label-or-path>" >&2
                return 2
            fi
            local expanded_target
            expanded_target=$(_tp_expand_path "$target")
            expanded_target="${expanded_target%/}"
            local tmp_file="${TMUX_PROJECT_ROOTS}.tmp.$$"
            local removed=0 entry label root_path
            while IFS= read -r entry; do
                if [[ "$entry" == *=* ]]; then
                    label="${entry%%=*}"
                    root_path="${entry#*=}"
                else
                    label=""
                    root_path="$entry"
                fi
                root_path=$(_tp_expand_path "$root_path")
                root_path="${root_path%/}"
                if [[ "$entry" == "$target" || "$label" == "$target" || "$root_path" == "$expanded_target" ]]; then
                    removed=1
                    continue
                fi
                printf '%s\n' "$entry"
            done < "$TMUX_PROJECT_ROOTS" > "$tmp_file"
            mv "$tmp_file" "$TMUX_PROJECT_ROOTS"
            if (( removed )); then
                echo "tmux-project: removed root matching: $target"
            else
                echo "tmux-project: no root matched: $target" >&2
                return 1
            fi
            ;;
        edit)
            "${EDITOR:-vi}" "$TMUX_PROJECT_ROOTS"
            ;;
        help|-h|--help)
            echo "usage: troot list | add [--create] [label=]/path | remove <label-or-path> | edit"
            ;;
        *)
            echo "tmux-project: unknown troot command: $cmd" >&2
            echo "usage: troot list | add [--create] [label=]/path | remove <label-or-path> | edit" >&2
            return 2
            ;;
    esac
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

        local parent_dir
        parent_dir=$(_tp_select_project_root "$_fzf") || return
        parent_dir="${parent_dir%/}"
        local new_path="${parent_dir}/$new_name"
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
     \$TMUX_PROJECT_DIR/project-roots     Project parent folders
     \$TMUX_PROJECT_DIR/aliases           Display name overrides
     \$TMUX_PROJECT_DIR/favorites         Pinned projects
     \$TMUX_PROJECT_DIR/hooks/            Lifecycle hooks

  Env vars:
     TMUX_PROJECT_DIR         Config dir (default: ~/.config/tmux-project)
     TMUX_PROJECT_DEFAULT_DIR Default new project parent (default: ~/Projects)
     TMUX_PROJECT_ROOTS       Project roots file
     TMUX_PROJECT_FAVORITES   Favorites file

  Root management:
     troot list
     troot add [--create] [label=]/path
     troot remove <label-or-path>
     troot edit
"'
