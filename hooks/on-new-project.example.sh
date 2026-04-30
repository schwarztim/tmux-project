#!/bin/bash
# Example onboard hook — called when a new project is created via `t`
# Arguments: $1 = project name, $2 = project path
#
# Copy this to ~/.config/tmux-project/hooks/on-new-project.sh and customize.
# Make it executable: chmod +x ~/.config/tmux-project/hooks/on-new-project.sh

NAME="$1"
PROJECT_PATH="$2"

echo "Onboarding project: $NAME at $PROJECT_PATH"

# Example: initialize git repo
# if [[ ! -d "$PROJECT_PATH/.git" ]]; then
#     git init "$PROJECT_PATH" --quiet
#     echo "  Initialized git repo"
# fi

# Example: create a README
# if [[ ! -f "$PROJECT_PATH/README.md" ]]; then
#     echo "# $NAME" > "$PROJECT_PATH/README.md"
#     echo "  Created README.md"
# fi

# Example: scaffold CLAUDE.md for AI-assisted development
# cat > "$PROJECT_PATH/CLAUDE.md" << EOF
# # $NAME
#
# ## Overview
# <!-- describe your project here -->
#
# ## Development
# <!-- commands, conventions, etc -->
# EOF
# echo "  Created CLAUDE.md"
