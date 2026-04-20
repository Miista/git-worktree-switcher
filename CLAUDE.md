# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`wt` is a CLI tool for fast git worktree switching. It ships as two independent scripts:

- **`wt`** — Bash script (Linux/macOS)
- **`wt.ps1`** — PowerShell script (Windows, requires dot-sourcing)

Both scripts implement the same command surface but are maintained separately — there is no shared code or code generation. Changes to behavior must be applied to both scripts.

## Linting

```bash
shellcheck -e SC2148 wt completions/_wt_completion completions/wt_completion
```

CI runs ShellCheck (v0.9.0) on push/PR to `master`. There is no linter configured for the PowerShell script.

## Architecture

Each script is a single self-contained file with no external dependencies beyond git (and optionally `fzf` for interactive mode). The command dispatch is at the bottom of each file: a `case` statement in bash, a `switch` block in PowerShell.

Both scripts parse `git worktree list --porcelain` output to resolve worktree paths and branches. The bash version uses inline `awk` scripts; the PowerShell version uses `Get-ParsedWorktrees` which returns hashtables with `Path`, `Head`, and `Branch` keys.

Key behavioral difference: the bash `switch_worktree` calls `exec $SHELL` (replaces the shell process), while the PowerShell `Invoke-Switch` calls `Set-Location` (changes directory in the current session, requires dot-sourcing).

## File Encoding

`wt.ps1` must be saved with UTF-8 BOM encoding. Windows PowerShell 5.1 requires the BOM to correctly handle Unicode characters (checkmarks/crosses in `check` output).

## Commands

Both scripts support: `list`, `help`, `version`, `-` (goto main), `current`, `add`, `create`, `rm`, `done`, `check`, and bare `<name>` (switch). The `update` command exists only in the bash version.

The `done` command performs safety checks (uncommitted changes, unpushed commits, upstream tracking) before removing a worktree and deleting its branch. The `--yes` flag skips these checks and force-removes.
