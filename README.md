# tmux-project

Project-first tmux session manager. Organizes tmux sessions by project with an fzf-powered picker, cross-platform status bar, and optional kitty terminal integration.

## What It Does

- **`t` command** — Outside tmux: pick a project, then pick/create a session. Inside tmux: switch sessions (uses [sesh](https://github.com/joshmedeski/sesh) if installed, fzf fallback otherwise).
- **Project roots + registry** — Configure one or many parent folders in `~/.config/tmux-project/project-roots`; direct child directories appear automatically in the picker. Add explicit one-off entries in `workspace-paths`.
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
| Session manager | Sources the `t` function into your shell and helps configure project roots |
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
troot          # List configured project roots
troot add work=~/Work
troot add --create personal=~/Projects
troot remove work
troot edit     # Open the roots file in $EDITOR
thelp          # Show usage info
```

### Outside tmux

1. Pick a project (or "+ New Project" to create one)
2. Pick an existing session or create a new one
3. Sessions are named `{project}/{label}` (e.g. `myapp/frontend`)

When creating a new project, `t` uses your configured project roots:

- No roots configured: defaults to `$TMUX_PROJECT_DEFAULT_DIR` (`~/Projects`)
- One root configured: uses that root as the parent folder
- Multiple roots configured: opens a root picker first, then suggests `{root}/{project-name}`

### Inside tmux

- With sesh: full session switcher with zoxide, kill, filter by type
- Without sesh: fzf list of tmux sessions with kill support

## Configuration

All config lives in `~/.config/tmux-project/` (override with `$TMUX_PROJECT_DIR`).

| File | Purpose |
|------|---------|
| `project-roots` | Project parent folders to scan — one path per line, or `label=/path` |
| `workspace-paths` | Explicit project registry — one `name=/path/to/project` per line |
| `aliases` | Display name overrides — `long-project-name=short` per line |
| `favorites` | Pinned project names, one display name per line |
| `hooks/on-new-project.sh` | Called with `(name, path)` when creating a project |
| `status.sh` | Symlink to the status bar dispatcher |

### Project Roots

`project-roots` is the flexible, cross-platform way to make whole folders of projects appear in the picker. Each direct child directory becomes a project.

Examples:

```text
# macOS / Linux
~/Projects
work=~/Work
clients=/srv/client-projects

# WSL
linux=~/code
windows=/mnt/c/Users/alex/Projects

# Git Bash / MSYS2 on Windows
personal=/c/Users/alex/Projects
work=/d/workspaces
```

Entries may be plain paths or `label=path`. Labels are used to disambiguate duplicate project names. For example, if both `personal` and `work` contain a `website` folder, the picker can show `personal/website` and `work/website`.

`workspace-paths` still exists for explicit entries that do not live under a root folder, or for custom display names:

```text
dotfiles=~/.dotfiles
infra=/opt/shared/infrastructure
```

You can update roots later without rerunning the installer:

```bash
troot list
troot add ~/OpenSource
troot add work=~/Work
troot add --create clients=/srv/clients
troot remove work
troot edit
```

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `TMUX_PROJECT_DIR` | `~/.config/tmux-project` | Config directory |
| `TMUX_PROJECT_DEFAULT_DIR` | `~/Projects` | Default parent for new projects |
| `TMUX_PROJECT_ROOTS` | `$TMUX_PROJECT_DIR/project-roots` | Project roots file |

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
