# tmux-project

Project-first tmux session manager. Organizes tmux sessions by project with an fzf-powered picker, cross-platform status bar, and optional kitty terminal integration.

## What It Does

- **`t` command** — Outside tmux: pick a project, then pick/create a session. Inside tmux: switch sessions (uses [sesh](https://github.com/joshmedeski/sesh) if installed, fzf fallback otherwise).
- **Project registry** — Simple `name=path` file at `~/.config/tmux-project/workspace-paths`. Create new projects from the picker — directory creation, registration, and session attachment in one flow.
- **Favorites + active-first ordering** — Press `F` in the project picker to pin or unpin a project. Favorites are shown first, projects with active sessions next, then the remaining projects alphabetically.
- **Status bar** — CPU, memory, network, and battery in your tmux status line. Auto-detects macOS, Linux, and Windows (MSYS2/WSL).
- **Kitty integration** — If kitty is detected, session name goes to the tab title instead of the status bar. Non-kitty terminals show everything in the status bar.
- **Lifecycle hooks** — Drop a script at `~/.config/tmux-project/hooks/on-new-project.sh` to run custom setup when creating projects (git init, scaffold files, etc).

## Requirements

- **tmux** (3.x+)
- **fzf** (0.30+)
- **bash** (4.0+) or **zsh** (5.0+)
- **sesh** (optional) — enhanced in-tmux session switching with zoxide integration

## Install

```bash
git clone <this-repo>
cd productivity/tmux-project
bash install.sh
```

The installer asks which components to install:

| Component | What It Does |
|-----------|-------------|
| Session manager | Sources the `t` function into your shell |
| Status bar | Links the OS-detecting status script to `~/.config/tmux-project/` |
| tmux config | Adds a `source-file` line to `~/.tmux.conf` |
| Example hooks | Copies a template hook to the config directory |

Or install everything at once:

```bash
bash install.sh --all
```

If you are migrating from the old `~/claude-rules/shell/t-session.zsh` setup, the installer imports `~/claude-rules/.workspace-paths` and its project aliases into `~/.config/tmux-project/` when the new config files are missing or empty.

## Usage

```
t              # Launch project picker (or session switcher if inside tmux)
thelp          # Show usage info
```

### Outside tmux

1. Pick a project (or "+ New Project" to create one)
2. Pick an existing session or create a new one
3. Sessions are named `{project}/{label}` (e.g. `myapp/frontend`)

### Inside tmux

- With sesh: full session switcher with zoxide, kill, filter by type
- Without sesh: fzf list of tmux sessions with kill support

## Configuration

All config lives in `~/.config/tmux-project/` (override with `$TMUX_PROJECT_DIR`).

| File | Purpose |
|------|---------|
| `workspace-paths` | Project registry — one `name=/path/to/project` per line |
| `aliases` | Display name overrides — `long-project-name=short` per line |
| `favorites` | Pinned project names, one display name per line |
| `hooks/on-new-project.sh` | Called with `(name, path)` when creating a project |
| `status.sh` | Symlink to the status bar dispatcher |

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TMUX_PROJECT_DIR` | `~/.config/tmux-project` | Config directory |
| `TMUX_PROJECT_DEFAULT_DIR` | `~/Projects` | Default parent for new projects |

## File Structure

```
tmux-project/
├── bin/
│   ├── t-session.zsh        # zsh session manager
│   └── t-session.bash       # bash session manager
├── status/
│   ├── status.sh            # OS dispatcher
│   ├── status-darwin.sh     # macOS metrics
│   ├── status-linux.sh      # Linux/WSL metrics
│   └── status-windows.sh    # MSYS2/Git Bash metrics
├── conf/
│   ├── tmux.conf            # Base tmux config
│   └── tmux-kitty.conf      # Kitty-specific overrides
├── hooks/
│   └── on-new-project.example.sh
├── install.sh
└── README.md
```

## Platform Notes

### macOS
- Status bar uses `memory_pressure`, `nettop`, `pmset` for metrics
- If using clipboard/keychain in tmux, uncomment the `reattach-to-user-namespace` line in `conf/tmux.conf`

### Linux / WSL
- Reads from `/proc/stat`, `/proc/meminfo`, `/sys/class/net/` for metrics
- WSL is auto-detected and uses the Linux status script

### Windows (MSYS2 / Git Bash)
- Uses `wmic` for CPU, memory, and battery
- Network stats not available (shows N/A)
- Requires bash 4.0+ (MSYS2 ships this; Git Bash may need updating)

## Uninstall

1. Remove the `source` line from your `~/.zshrc` or `~/.bashrc`
2. Remove the `source-file` line(s) from `~/.tmux.conf`
3. Optionally delete `~/.config/tmux-project/`
