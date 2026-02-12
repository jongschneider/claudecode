---
name: tmux
description: Use tmux to read output from sessions, send commands to sessions, or spin up temp environments for testing CLIs. Use when the user points you at a tmux session, asks to interact with one, or asks to test a CLI.
---

# tmux

Three use cases: reading from sessions, sending commands to sessions, and temp test environments.

## Reading from a session

Capture output from a session the user points you at:

```bash
# Capture last N lines
tmux capture-pane -t <name> -p -S -100

# Full scrollback
tmux capture-pane -t <name> -p -S -

# List sessions to find the right one
tmux list-sessions
```

## Sending commands to a session

Write to an existing session using send-keys:

```bash
# Send a command
tmux send-keys -t <name> '<command>' Enter

# Send Ctrl+C to interrupt
tmux send-keys -t <name> C-c

# Send multiple commands sequentially
tmux send-keys -t <name> 'cd /some/path' Enter
tmux send-keys -t <name> 'make build' Enter
```

Pair with `capture-pane` to send a command and read the result:

```bash
tmux send-keys -t <name> 'go test ./...' Enter
sleep 2
tmux capture-pane -t <name> -p -S -50
```

## Temp test environment

Create a throwaway session + temp dir for testing CLIs:

```bash
# Create temp dir and session
TMPDIR=$(mktemp -d)
SESSION="test-$(basename $TMPDIR | tail -c 8)"
tmux new-session -d -s "$SESSION" -c "$TMPDIR"
echo "Session: $SESSION"
echo "Dir: $TMPDIR"
```

Then send commands to it and capture output:

```bash
# Send a command
tmux send-keys -t "$SESSION" '<command>' Enter

# Wait a moment then capture result
sleep 1
tmux capture-pane -t "$SESSION" -p -S -50
```

**Always output the session name** so the user can `tmux attach -t <name>` to inspect interactively.

### Cleanup

```bash
tmux kill-session -t "$SESSION"
# temp dir is cleaned up by OS on reboot, or:
trash "$TMPDIR"
```

## Rules

1. Always use detached sessions (`-d`) -- never attach
2. Always name sessions (`-s`)
3. Use `capture-pane` to read output, never attach
4. When creating test environments, always print the session name
5. Use `trash` not `rm` for cleanup
