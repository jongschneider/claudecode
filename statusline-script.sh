#!/bin/bash

input=$(cat)

# Extract fields
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name // "?"')
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0 | floor')

cd "$cwd" 2>/dev/null || cd "$HOME"

# Directory substitutions
dir_path="$cwd"
dir_path="${dir_path/#$HOME\/Developer/󰲋 }"
dir_path="${dir_path/#$HOME\/Documents/󰈙 }"
dir_path="${dir_path/#$HOME\/Downloads/ }"
dir_path="${dir_path/#$HOME\/Music/󰝚 }"
dir_path="${dir_path/#$HOME\/Pictures/ }"
dir_path="${dir_path/#$HOME/~}"

# Git info
git_branch=""
git_status=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        git_status_output=$(git status --porcelain 2>/dev/null)
        if [ -n "$git_status_output" ]; then
            echo "$git_status_output" | grep -q "^??" && git_status="${git_status}?"
            echo "$git_status_output" | grep -q "^.[MD]" && git_status="${git_status}!"
            echo "$git_status_output" | grep -q "^[MADRC]" && git_status="${git_status}+"
        fi
        upstream=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null)
        if [ -n "$upstream" ]; then
            ahead_behind=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
            ahead=$(echo "$ahead_behind" | awk '{print $1}')
            behind=$(echo "$ahead_behind" | awk '{print $2}')
            [ "$ahead" -gt 0 ] 2>/dev/null && git_status="${git_status}⇡"
            [ "$behind" -gt 0 ] 2>/dev/null && git_status="${git_status}⇣"
        fi
    fi
fi

# Context bar (5 segments)
filled=$((context_pct / 20))
empty=$((5 - filled))
bar=""
for ((i = 0; i < filled; i++)); do bar="${bar}━"; done
for ((i = 0; i < empty; i++)); do bar="${bar}╌"; done

# Context color
if [ "$context_pct" -ge 80 ]; then
    ctx_color="38;2;243;139;168"  # red
elif [ "$context_pct" -ge 50 ]; then
    ctx_color="38;2;249;226;175"  # yellow
else
    ctx_color="38;2;166;227;161"  # green
fi

# Colors
dim="38;2;108;112;134"     # overlay0
peach="38;2;250;179;135"
green="38;2;166;227;161"
lavender="38;2;180;190;254"

# -- Left side: directory + git --
left="\033[${peach}m ${dir_path}\033[0m"

if [ -n "$git_branch" ]; then
    left="${left} \033[${dim}m│\033[0m \033[${green}m ${git_branch}\033[0m"
    if [ -n "$git_status" ]; then
        left="${left} \033[${green}m${git_status}\033[0m"
    fi
fi

# -- Right side: model + context --
right="\033[${lavender}m${model}\033[0m \033[${dim}m│\033[0m \033[${ctx_color}m${bar} ${context_pct}%\033[0m"

# Calculate visible widths (strip ANSI)
left_plain=$(printf '%b' "$left" | sed 's/\x1b\[[0-9;]*m//g')
right_plain=$(printf '%b' "$right" | sed 's/\x1b\[[0-9;]*m//g')
left_len=${#left_plain}
right_len=${#right_plain}

# Terminal width
cols=$(tput cols 2>/dev/null || echo 120)
pad=$((cols - left_len - right_len))
[ "$pad" -lt 2 ] && pad=2
spaces=$(printf '%*s' "$pad" '')

printf '%b%s%b' "$left" "$spaces" "$right"
