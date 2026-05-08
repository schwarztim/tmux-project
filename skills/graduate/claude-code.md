---
name: graduate
description: "Graduate the current conversation into a project. Synthesizes conversation context into .claude/context.md at the target project path, registers in T (tmux-project) if new, copies a kickoff prompt to clipboard, and opens a tmux session in the project directory."
allowed-tools: Read, Bash, Write, Edit, AskUserQuestion, Glob, Grep
---

# Graduate Conversation to Project

You are helping the user transfer the current conversation's context into a project directory so they can pick it up in a new Claude Code session scoped to that project.

## Step 1: Read the T Project Registry

Run this exact command to get the list of registered projects:

```bash
cat ~/.config/tmux-project/workspace-paths
```

The output is `name=path` pairs, one per line. Present these to the user and ask them to either:
- Name an existing project from the list
- Provide a new project name

Store the chosen name as `PROJECT_NAME` and the path as `PROJECT_PATH` for all subsequent steps.

## Step 2: Handle New Projects

If the user named a project that does NOT exist in workspace-paths:

**2a.** Read the default project root:
```bash
cat ~/.config/tmux-project/project-roots
```
This returns a single directory path (e.g., `/Users/timothy.schwarz/Projects`).

**2b.** Set `PROJECT_PATH` to `<project-root>/<PROJECT_NAME>`.

**2c.** Create the directory:
```bash
mkdir -p <PROJECT_PATH>
```

**2d.** Register in T by appending to workspace-paths and sorting:
```bash
echo '<PROJECT_NAME>=<PROJECT_PATH>' >> ~/.config/tmux-project/workspace-paths
sort -o ~/.config/tmux-project/workspace-paths ~/.config/tmux-project/workspace-paths
```

## Step 3: Synthesize Context

Reflect on the ENTIRE current conversation. Produce a structured markdown document that captures everything a fresh session would need to continue this work. Write it as if briefing a brand new Claude or Copilot session that has zero knowledge of this conversation.

**This is the only bridge between this session and the next one. Be thorough. Include every technical detail, every decision, every gotcha.**

Use this exact structure (omit sections that have no content):

```markdown
# <Project Name>

> <One-line description of what this project is>

## Background

<Why this project exists. What problem it solves. What motivated the exploration.>

## Goals

<Bullet list of concrete goals/requirements that emerged.>

## Decisions Made

<Key technical and design decisions with rationale. Format: "- Decision: rationale">

## Current State

<What exists right now. Files created, commands run, things configured, what works, what doesn't. Include specific file paths, URLs, versions, config values.>

## Architecture / Design

<Components, data flow, integrations, tech stack. Include diagrams if discussed.>

## Next Steps

<Ordered list of specific next actions. Not "implement the thing" but "create X with Y using Z pattern".>

## Key Details

<API endpoints, config values, env vars, dependency versions, gotchas, commands that worked, error solutions.>

## References

<URLs, docs, repos, tools mentioned.>
```

Rules:
- Write in second person ("you decided...", "the goal is...")
- Include ALL technical specifics -- paths, versions, commands, config values
- Capture WHY behind decisions, not just WHAT
- Include key code snippets that were discussed or generated
- Do NOT include meta-commentary about the graduation process

## Step 4: Write the Context Files

Run these exact commands. Write the SAME synthesized content to both locations:

**4a.** Create directories:
```bash
mkdir -p <PROJECT_PATH>/.claude
mkdir -p <PROJECT_PATH>/.github
```

**4b.** Write the synthesized context to BOTH files using the Write tool:
- `<PROJECT_PATH>/.claude/context.md` -- auto-loaded by Claude Code
- `<PROJECT_PATH>/.github/copilot-instructions.md` -- auto-loaded by Copilot CLI

**4c.** Check if `<PROJECT_PATH>/CLAUDE.md` exists:
```bash
test -f <PROJECT_PATH>/CLAUDE.md && echo "exists" || echo "missing"
```

If missing, write this file at `<PROJECT_PATH>/CLAUDE.md`:
```markdown
# <Project Name>

> <One-line description>

## Context

See `.claude/context.md` for full project context from the initial exploration session.
```

## Step 5: Generate and Copy Kickoff Prompt

Write a kickoff prompt -- 2-4 sentences that a fresh session can act on immediately. It MUST:
- Tell the session to read the context file first
- State the immediate priority from Next Steps
- Give enough specifics that the session can start without asking questions

Example format:
```
Read .claude/context.md for full project background. The priority is implementing the SSDP discovery endpoint -- the auth middleware and database models are already in place. Start with the endpoint handler in api/discovery.py.
```

Copy it to clipboard with this exact command:
```bash
printf '%s' '<THE KICKOFF PROMPT TEXT>' | pbcopy
```

Use `printf '%s'` not `echo` -- avoids trailing newline issues. Single-quote the prompt text. If the prompt contains single quotes, escape them as `'\''`.

## Step 6: Launch Tmux Session

Create a tmux session named `<PROJECT_NAME>/claude` in the project directory.

**6a.** Check if we're inside tmux:
```bash
echo "${TMUX:-not-in-tmux}"
```

**6b.** Create the session (always detached first):
```bash
tmux new-session -d -s '<PROJECT_NAME>/claude' -c '<PROJECT_PATH>'
```

**6c.** If `$TMUX` was set (we ARE inside tmux), switch to the new session:
```bash
tmux switch-client -t '=<PROJECT_NAME>/claude'
```

If `$TMUX` was NOT set, skip the switch -- the user can attach later with `t`.

## Step 7: Report

Tell the user exactly:
- Context written to `<PROJECT_PATH>/.claude/context.md` and `<PROJECT_PATH>/.github/copilot-instructions.md`
- Kickoff prompt is in clipboard -- paste it as the first message in the new session
- Tmux session `<PROJECT_NAME>/claude` is ready

Do NOT ask for confirmation between steps. Execute all steps in sequence. The user invoked /graduate because they want this to happen now.
