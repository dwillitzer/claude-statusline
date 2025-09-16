#!/bin/bash

# Claude Code Status Line
# Real-time context usage, session timing, and activity monitoring
# Cross-platform compatible for Windows/Mac/Linux
# Supports multiple modes: verbose, compact, custom

# Parse command line arguments
STATUSLINE_MODE="verbose"  # Default mode
CUSTOM_FORMAT='Context: %context% | Last: %last% | %project%'  # Default custom format

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            STATUSLINE_MODE="$2"
            shift 2
            ;;
        -c|--compact)
            STATUSLINE_MODE="compact"
            shift
            ;;
        -v|--verbose)
            STATUSLINE_MODE="verbose"
            shift
            ;;
        -f|--format)
            STATUSLINE_MODE="custom"
            CUSTOM_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  -m, --mode MODE      Set display mode (verbose, compact, custom)"
            echo "  -c, --compact        Use compact mode (shorthand)"
            echo "  -v, --verbose        Use verbose mode (shorthand)"
            echo "  -f, --format FORMAT  Use custom format with template"
            echo ""
            echo "Template variables for custom format:"
            echo "  %model%      - Model name (Opus, Sonnet, etc.)"
            echo "  %context%    - Context usage with color"
            echo "  %percent%    - Context percentage number"
            echo "  %remaining%  - Remaining tokens display"
            echo "  %session%    - Session date"
            echo "  %time%       - Current time"
            echo "  %last%       - Time since last message"
            echo "  %project%    - Project name"
            echo "  %message%    - Last message preview (first 5 words)"
            echo ""
            echo "Examples:"
            echo "  $0 --compact"
            echo "  $0 --format '[%percent%] %project%'"
            echo "  $0 -m verbose"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect operating system for platform-specific commands
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

OS_TYPE=$(detect_os)

# Platform-specific timestamp parsing function
parse_iso_timestamp() {
    local timestamp="$1"
    local timestamp_base="${timestamp%%.*}"

    case "$OS_TYPE" in
        "macos")
            # Native macOS date parsing with proper UTC handling
            if [[ "$timestamp" == *"Z" ]]; then
                # UTC timestamp - use TZ=UTC for proper timezone handling
                TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$timestamp_base" +%s 2>/dev/null || echo "0"
            else
                # Local timestamp - use native parsing
                date -j -f "%Y-%m-%dT%H:%M:%S" "$timestamp_base" +%s 2>/dev/null || echo "0"
            fi
            ;;
        "linux")
            # GNU date handles ISO timestamps properly
            date -d "$timestamp" +%s 2>/dev/null || echo "0"
            ;;
        "windows")
            # Windows/Git Bash - try GNU date first, fallback to basic parsing
            if command -v date >/dev/null 2>&1 && date --version >/dev/null 2>&1; then
                date -d "$timestamp" +%s 2>/dev/null || echo "0"
            else
                # Fallback: basic manual parsing for Windows without GNU date
                # Convert ISO timestamp to epoch (simplified approach)
                if [[ "$timestamp" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
                    year="${BASH_REMATCH[1]}"
                    month="${BASH_REMATCH[2]}"
                    day="${BASH_REMATCH[3]}"
                    hour="${BASH_REMATCH[4]}"
                    minute="${BASH_REMATCH[5]}"
                    second="${BASH_REMATCH[6]}"

                    # Use PowerShell for accurate timestamp conversion on Windows
                    if command -v powershell.exe >/dev/null 2>&1; then
                        powershell.exe -Command "[int][double]::Parse((Get-Date -Year $year -Month $month -Day $day -Hour $hour -Minute $minute -Second $second).ToString('yyyyMMddHHmmss'))" 2>/dev/null || echo "0"
                    else
                        echo "0"
                    fi
                else
                    echo "0"
                fi
            fi
            ;;
        *)
            # Unknown OS - try GNU date format first
            date -d "$timestamp" +%s 2>/dev/null || echo "0"
            ;;
    esac
}

# Platform-specific file stat function
get_file_mtime() {
    local file="$1"

    case "$OS_TYPE" in
        "macos")
            stat -f "%m" "$file" 2>/dev/null || echo "0"
            ;;
        "linux"|"windows")
            stat -c "%Y" "$file" 2>/dev/null || echo "0"
            ;;
        *)
            # Fallback to ls-based approach
            if [[ -f "$file" ]]; then
                date +%s
            else
                echo "0"
            fi
            ;;
    esac
}

# Platform-specific function to find most recent file by modification time
find_most_recent_file() {
    local search_path="$1"
    local pattern="$2"

    case "$OS_TYPE" in
        "macos")
            # macOS uses -f flag for stat
            find "$search_path" -name "$pattern" -type f -print0 2>/dev/null | \
                xargs -0 stat -f "%m %N" 2>/dev/null | \
                sort -rn | head -1 | cut -d' ' -f2-
            ;;
        "linux"|"windows")
            # Linux/Windows use -c flag for stat
            find "$search_path" -name "$pattern" -type f -print0 2>/dev/null | \
                xargs -0 stat -c "%Y %n" 2>/dev/null | \
                sort -rn | head -1 | cut -d' ' -f2-
            ;;
        *)
            # Fallback: use ls -t (less reliable but works everywhere)
            find "$search_path" -name "$pattern" -type f 2>/dev/null | \
                xargs ls -t 2>/dev/null | head -1
            ;;
    esac
}

# Get input JSON data (if provided by Claude Code) or auto-detect session info
# Only try to read input if we're in default mode (no arguments provided)
if [[ -t 0 ]]; then
    # Terminal is attached, no stdin waiting
    input="{}"
else
    # Read from stdin with timeout
    input=$(timeout 1 cat 2>/dev/null || echo "{}")
fi

# Check if we received JSON input from Claude Code
if echo "$input" | jq -e . >/dev/null 2>&1 && [[ "$input" != "{}" ]]; then
    # Extract key data from JSON input using the correct structure found in Claude Code
    session_id=$(echo "$input" | jq -r '.session_id // empty')
    model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // "Claude"')
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')
    current_dir=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
    output_style=$(echo "$input" | jq -r '.output_style.name // "default"')

    # Extract Claude Code's model-aware token data
    current_tokens=$(echo "$input" | jq -r '.current_tokens // 0')
    expected_total_tokens=$(echo "$input" | jq -r '.expected_total_tokens // 500000')
    min_tokens_for_perf_hint=$(echo "$input" | jq -r '.min_tokens_for_perf_hint // 180000')

    # If we got valid JSON but no session info, this might be a different JSON structure
    if [[ -z "$session_id" && -z "$transcript_path" ]]; then
        # Try alternative field names
        session_id=$(echo "$input" | jq -r '.sessionId // .id // empty')
        transcript_path=$(echo "$input" | jq -r '.transcriptPath // .file // empty')
    fi
else
    # Auto-detect session information when no JSON input provided
    session_id=""
    model_name="Claude"
    transcript_path=""
    # Use Claude Code's project directory if available, otherwise fall back to pwd
    current_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    output_style="default"

    # Try to detect the current Claude session by finding the most likely transcript
    # Look for transcripts in the current project area
    project_path=$(echo "$current_dir" | sed 's|/|-|g')

    # Find the most recent transcript by modification time
    # Skip large files (>10MB) as they're likely old compacted sessions
    recent_transcript=$(find ~/.claude/projects -path "*$project_path*" -name "*.jsonl" -type f -size -10M -print0 2>/dev/null | xargs -0 stat -f "%m %N" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

    # If no small transcript found, get the most recent regardless of size
    if [[ -z "$recent_transcript" ]]; then
        recent_transcript=$(find ~/.claude/projects -path "*$project_path*" -name "*.jsonl" -type f -print0 2>/dev/null | xargs -0 stat -f "%m %N" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    fi

    # If found, extract session ID from filename
    if [[ -f "$recent_transcript" ]]; then
        session_id=$(basename "$recent_transcript" .jsonl)
        transcript_path="$recent_transcript"

        # Try to get model info from recent transcript entries
        model_name=$(tail -5 "$recent_transcript" 2>/dev/null | head -1 | jq -r '.message.model // "Claude"' 2>/dev/null || echo "Claude")
    fi
fi

# Intelligent model context limit detection
detect_model_context_limit() {
    local model="$1"
    local reported_limit="$2"

    # If Claude reports a reasonable limit, trust it
    if [[ "$reported_limit" -ge 10000 && "$reported_limit" -le 2000000 ]]; then
        echo "$reported_limit"
        return
    fi

    # Model-specific context limits
    case "$model" in
        # Sonnet 4 / 3.5 series - 1M context
        *claude-3-5-sonnet*|*claude-3\.5-sonnet*|*sonnet-3-5*|*sonnet-4*)
            echo "1000000" ;;
        # Other Claude models - 200K context
        *sonnet*|*Sonnet*|*opus*|*Opus*|*haiku*|*Haiku*|*claude*|*Claude*)
            echo "200000" ;;
        # OpenAI models
        *gpt-4o*|*gpt-4-turbo*)
            echo "128000" ;;
        *gpt-4*)
            echo "128000" ;;
        # Gemini models
        *gemini*)
            echo "1048576" ;;
        # Grok models
        *grok*)
            echo "128000" ;;
        # Default
        *)
            echo "500000" ;;
    esac
}

# Calculate context usage - prioritize Claude Code data or detect model limits
if [[ -n "$current_tokens" && "$current_tokens" -gt 0 ]]; then
    # Claude Code provided the token data directly!
    estimated_tokens=$current_tokens

    # Use intelligent model context limit detection
    context_limit=$(detect_model_context_limit "$model_name" $expected_total_tokens)

    # Handle potential over-reporting from Claude
    if [[ $estimated_tokens -gt $context_limit ]]; then
        echo "DEBUG: Adjusting over-reported token count" >&2
        estimated_tokens=$((context_limit / 4 * 3))
    fi

    # Calculate percentages and format
    context_percent=$((estimated_tokens * 100 / context_limit))
    remaining_tokens=$((context_limit - estimated_tokens))
    remaining_k=$((remaining_tokens / 1000))

    # Color coding for usage levels
    if [[ $context_percent -gt 80 ]]; then
        context_color="31"  # Red for high usage
    elif [[ $context_percent -gt 60 ]]; then
        context_color="33"  # Yellow for medium usage
    else
        context_color="32"  # Green for low usage
    fi

    context_info=$(printf "\033[%sm%s%%\033[0m (%sk left)" "$context_color" "$context_percent" "$remaining_k")

elif [[ -f "$transcript_path" ]]; then
    # Use enhanced token counting with model detection
    # Map Claude model names to tiktoken-compatible encodings
    case "$model_name" in
        *"claude-3-sonnet"* | *"Sonnet"* | *"sonnet"*) tiktoken_model="gpt-4" ;;
        *"claude-3-haiku"* | *"Haiku"* | *"haiku"*) tiktoken_model="gpt-4" ;;
        *"claude-3-opus"* | *"Opus"* | *"opus"*) tiktoken_model="gpt-4" ;;
        *"claude"* | *"Claude"*) tiktoken_model="gpt-4" ;;
        *) tiktoken_model="gpt-4" ;; # Default fallback
    esac

    # Check file size first to avoid processing huge files
    transcript_size=$(wc -c < "$transcript_path" 2>/dev/null || echo "0")

    # If file is larger than 10MB, use character estimation instead of token counting
    # This prevents hanging on huge transcript files
    if [[ $transcript_size -gt 10485760 ]]; then
        # Use character estimation for large files
        chars_per_token=${CLAUDE_CHARS_PER_TOKEN:-125}
        transcript_tokens=$((transcript_size / chars_per_token))
    elif command -v node >/dev/null 2>&1 && [[ -f "/Users/devops/.claude/claude-enhanced-token-counter.js" ]]; then
        # Use accurate token counting for normal-sized files
        transcript_tokens=$(node "/Users/devops/.claude/claude-enhanced-token-counter.js" "$transcript_path" "$tiktoken_model" 2>/dev/null || echo "0")
    elif command -v node >/dev/null 2>&1 && [[ -f "/Users/devops/.claude/claude-token-counter.js" ]]; then
        transcript_tokens=$(node "/Users/devops/.claude/claude-token-counter.js" "$transcript_path" 2>/dev/null || echo "0")
    else
        # Fallback to character estimation if Node.js or token counter not available
        chars_per_token=${CLAUDE_CHARS_PER_TOKEN:-125}
        transcript_tokens=$((transcript_size / chars_per_token))
    fi

    # Calculate dynamic system overhead
    # System prompt overhead - estimated at ~3.1k based on /context
    system_prompt_overhead=3100

    # System tools overhead - estimated at ~11.8k based on /context
    system_tools_overhead=11800

    # MCP tools overhead - calculate dynamically
    mcp_overhead=0

    # Check for MCP configuration in hierarchical override order
    # Claude Code looks for 3 types of files in this order:
    # Locations: $PWD/.claude/, $CWD/.claude/, ~/
    # Files: .claude.json/.claude.local.json, CLAUDE.md/CLAUDE.local.md, .claude/settings.json/.claude/settings.local.json
    mcp_config_found=false
    mcp_config_count=0

    # Define search locations in precedence order
    config_locations=("$PWD/.claude" "$current_dir/.claude" "$HOME")

    # Define config file patterns
    config_files=(".claude.json" ".claude.local.json" "CLAUDE.md" "CLAUDE.local.md" ".claude/settings.json" ".claude/settings.local.json")

    # Search for configurations in hierarchical order
    for location in "${config_locations[@]}"; do
        for config_file in "${config_files[@]}"; do
            config_path="$location/$config_file"
            if [[ -f "$config_path" ]]; then
                # Check if this config contains MCP configurations
                if grep -q "mcp\|MCP" "$config_path" 2>/dev/null; then
                    mcp_config_found=true
                    mcp_config_count=$((mcp_config_count + 1))
                fi
            fi
        done
    done

    # Count user-level MCP configs separately (legacy logic)
    check_dir="$(pwd)"
    for level in {0..5}; do  # Check up to 5 levels up
        if [[ -f "$check_dir/.claude.json" ]]; then
            mcp_config_found=true
            mcp_config_count=$((mcp_config_count + 1))
            # Most specific config wins, but all contribute to context overhead
        fi

        # Move up one directory level (skip for level 0)
        if [[ $level -gt 0 ]]; then
            check_dir="$(dirname "$check_dir")"
            # Stop if we've reached the root or home directory
            if [[ "$check_dir" == "/" ]] || [[ "$check_dir" == "$HOME" ]]; then
                break
            fi
        fi
    done

    # Check user-level MCP configs (global fallbacks)
    user_mcp_configs=0
    if [[ -f "$HOME/.claude/claude_desktop_config.json" ]]; then
        mcp_config_found=true
        user_mcp_configs=$((user_mcp_configs + 1))
    fi
    if [[ -f "$HOME/.config/claude/claude_desktop_config.json" ]]; then
        mcp_config_found=true
        user_mcp_configs=$((user_mcp_configs + 1))
    fi
    if [[ -f "$HOME/.claude.json" ]]; then
        mcp_config_found=true
        user_mcp_configs=$((user_mcp_configs + 1))
    fi

    # Calculate MCP overhead dynamically based on actual tools
    if [[ "$mcp_config_found" == true ]]; then
        # TODO: Parse actual MCP tool definitions and count tokens
        # For now, use observed value from /context output
        # Serena MCP shows as 10.9k tokens in /context
        mcp_overhead=10900
    fi

    # Calculate memory files overhead from all possible locations
    memory_overhead=0

    # User-level memory files (~/.claude/)
    user_claude_dir="$HOME/.claude"
    for file in "CLAUDE.md" "CLAUDE.local.md"; do
        if [[ -f "$user_claude_dir/$file" ]]; then
            # Estimate token count for each memory file (~1.6k per file)
            memory_overhead=$((memory_overhead + 1600))
        fi
    done

    # Project-level memory files (current directory and subdirectories)
    # Check current directory
    for file in "CLAUDE.md" "CLAUDE.local.md"; do
        if [[ -f "./$file" ]]; then
            memory_overhead=$((memory_overhead + 1600))
        fi
    done

    # Check .claude/ subdirectory
    if [[ -d ".claude" ]]; then
        for file in "CLAUDE.md" "CLAUDE.local.md"; do
            if [[ -f ".claude/$file" ]]; then
                memory_overhead=$((memory_overhead + 1600))
            fi
        done
    fi

    # Check for memory files in parent directories (up to 3 levels)
    check_dir="$(pwd)"
    for level in {1..3}; do
        check_dir="$(dirname "$check_dir")"
        # Stop if we've reached the root
        if [[ "$check_dir" == "/" ]]; then
            break
        fi

        # Check direct memory files
        for file in "CLAUDE.md" "CLAUDE.local.md"; do
            if [[ -f "$check_dir/$file" ]]; then
                memory_overhead=$((memory_overhead + 1600))
            fi
        done

        # Check .claude/ subdirectory
        if [[ -d "$check_dir/.claude" ]]; then
            for file in "CLAUDE.md" "CLAUDE.local.md"; do
                if [[ -f "$check_dir/.claude/$file" ]]; then
                    memory_overhead=$((memory_overhead + 1600))
                fi
            done
        fi
    done

    # Also check for settings.json overhead (smaller, ~500 tokens each)
    settings_overhead=0
    for settings_file in "$user_claude_dir/settings.json" "$user_claude_dir/settings.local.json" ".claude/settings.json" ".claude/settings.local.json"; do
        if [[ -f "$settings_file" ]]; then
            settings_overhead=$((settings_overhead + 500))
        fi
    done

    # Add settings overhead to total memory overhead
    memory_overhead=$((memory_overhead + settings_overhead))

    # Calculate total estimated context usage
    # For post-compact sessions, use a more accurate calculation
    # The transcript tokens represent the conversation content
    # Total context = transcript + (system_prompt + system_tools + mcp + memory - message_overlap)

    # Observed: 31k total with 6.6k transcript and 3.1k messages in /context
    # This means: transcript_overhead = 6.6k - 3.1k = 3.5k extra in transcript
    # So: total = transcript + overhead - transcript_overhead
    message_overlap=3500  # Difference between transcript content and /context "Messages"

    total_overhead=$((system_prompt_overhead + system_tools_overhead + mcp_overhead + memory_overhead))
    estimated_tokens=$((transcript_tokens + total_overhead - message_overlap))
    context_limit=200000

    # Cap tokens at reasonable maximum (context can't exceed 400k in practice)
    if [[ $estimated_tokens -gt 400000 ]]; then
        # If tokens are extremely high, fall back to simpler calculation
        estimated_tokens=$((transcript_tokens / 10 + total_overhead))
    fi

    # Prevent division by zero and handle large numbers properly
    if [[ $context_limit -gt 0 ]]; then
        context_percent=$((estimated_tokens * 100 / context_limit))
        remaining_tokens=$((context_limit - estimated_tokens))

        # Convert to k format for display
        remaining_k=$((remaining_tokens / 1000))

        # Format context usage with color coding
        if [[ $context_percent -gt 80 ]]; then
            context_color="31"  # Red for high usage
        elif [[ $context_percent -gt 60 ]]; then
            context_color="33"  # Yellow for medium usage
        else
            context_color="32"  # Green for low usage
        fi

        context_info=$(printf "\033[%sm%s%%\033[0m (%sk left)" "$context_color" "$context_percent" "$remaining_k")
    else
        context_info=$(printf "\033[90mN/A\033[0m")
    fi
else
    context_info=$(printf "\033[90mN/A\033[0m")
fi

# Session timestamp (today's date)
session_date=$(date "+%m/%d")

# Current PST time
pst_time=$(TZ="America/Los_Angeles" date "+%I:%M %p PST")

# Last message timing - find actual user message from Claude transcript
current_time=$(date +%s)

# Try to find the real transcript file in ~/.claude/projects
real_transcript=""
if [[ -n "$session_id" ]]; then
    # Look for transcript based on session ID
    real_transcript=$(find ~/.claude/projects -name "${session_id}.jsonl" -type f 2>/dev/null | head -1)
fi

# If not found by session ID, try to find the most recent transcript in the current project directory
if [[ -z "$real_transcript" || ! -f "$real_transcript" ]]; then
    # Convert current directory to Claude project path format
    project_path=$(echo "$current_dir" | sed 's|/|-|g')
    # Use cross-platform function to find most recent transcript in project
    if [[ -d ~/.claude/projects ]]; then
        for project_dir in ~/.claude/projects/*"$project_path"*; do
            if [[ -d "$project_dir" ]]; then
                real_transcript=$(find_most_recent_file "$project_dir" "*.jsonl")
                if [[ -n "$real_transcript" && -f "$real_transcript" ]]; then
                    break
                fi
            fi
        done
    fi
fi

# If still not found, fall back to most recent transcript overall
if [[ -z "$real_transcript" || ! -f "$real_transcript" ]]; then
    real_transcript=$(find_most_recent_file ~/.claude/projects "*.jsonl")
fi

if [[ -f "$real_transcript" ]]; then
    # Find the most recent user message (human input, not tool results)
    # Look for messages that originate from human input
    # Find last human message timestamp and content
    last_human_data=$(tail -r "$real_transcript" 2>/dev/null | while IFS= read -r line; do
        # Look for actual human messages (not tool results) - handle both string and array content
        if echo "$line" | jq -e '.type == "user" and .message.role == "user" and (.message.content | type | . == "string" or . == "array")' >/dev/null 2>&1; then
            timestamp=$(echo "$line" | jq -r '.timestamp' 2>/dev/null)
            # Extract message content - handle both string and array formats
            content=$(echo "$line" | jq -r '
                if .message.content | type == "string" then
                    .message.content
                elif .message.content | type == "array" then
                    .message.content[] | select(.type == "text") | .text // empty
                else
                    empty
                end' 2>/dev/null | head -1)

            # Filter out command outputs and system messages
            if [[ "$content" != *"<local-command-stdout>"* ]] && \
               [[ "$content" != *"<command-name>"* ]] && \
               [[ "$content" != *"<system-reminder>"* ]] && \
               [[ "$content" != "No response requested"* ]] && \
               [[ -n "$content" ]]; then
                # Output both timestamp and content separated by a delimiter
                echo "${timestamp}|||${content}"
                break
            fi
        fi
    done)

    # Split the data
    last_human_timestamp="${last_human_data%%|||*}"
    last_human_message="${last_human_data#*|||}"

    if [[ -n "$last_human_timestamp" ]]; then
        # Convert ISO timestamp to epoch seconds using cross-platform function
        last_human_epoch=$(parse_iso_timestamp "$last_human_timestamp")
        time_diff=$((current_time - last_human_epoch))
    else
        # Fallback to transcript modification time using cross-platform function
        last_modified=$(get_file_mtime "$real_transcript")
        if [[ "$last_modified" == "0" ]]; then
            last_modified="$current_time"
        fi
        time_diff=$((current_time - last_modified))
    fi
else
    # No transcript found, fallback to basic timing
    time_diff=0
fi

# Enhanced time display
if [[ $time_diff -lt 10 ]]; then
    last_msg="<10s"
    msg_color="32"  # Green for just started
elif [[ $time_diff -lt 60 ]]; then
    last_msg="${time_diff}s"
    msg_color="32"  # Green for normal processing
elif [[ $time_diff -lt 300 ]]; then
    minutes=$((time_diff / 60))
    seconds=$((time_diff % 60))
    if [[ $seconds -gt 0 ]]; then
        last_msg="${minutes}m${seconds}s"
    else
        last_msg="${minutes}m"
    fi
    msg_color="33"  # Yellow for extended processing
elif [[ $time_diff -lt 3600 ]]; then
    minutes=$((time_diff / 60))
    last_msg="${minutes}m"
    msg_color="33"  # Yellow for long processing
else
    hours=$((time_diff / 3600))
    if [[ $hours -lt 24 ]]; then
        last_msg="${hours}h"
        msg_color="90"  # Gray for very long
    else
        days=$((time_diff / 86400))
        last_msg="${days}d"
        msg_color="90"  # Gray for extremely long
    fi
fi

# Project context (shortened path)
project_name=$(basename "$current_dir")

# Format last message preview (first 5 words or less)
if [[ -n "$last_human_message" ]]; then
    # Clean up the message (remove extra whitespace, newlines)
    clean_message=$(echo "$last_human_message" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Extract first 5 words
    word_count=0
    message_preview=""
    for word in $clean_message; do
        if [[ $word_count -lt 5 ]]; then
            message_preview="${message_preview} ${word}"
            word_count=$((word_count + 1))
        else
            break
        fi
    done

    # Trim and add ellipsis if message was longer
    message_preview=$(echo "$message_preview" | sed 's/^ *//')
    remaining_text="${clean_message#$message_preview}"
    if [[ -n "$remaining_text" && "$remaining_text" != " " ]]; then
        message_preview="${message_preview}..."
    fi

    # Add speech bubble emoji
    message_display="💬 \"${message_preview}\""
else
    message_display=""
fi

# Detect model and set appropriate color
# Extract model name from transcript if not provided
if [[ -z "$model_name" || "$model_name" == "Claude" ]] && [[ -f "$real_transcript" ]]; then
    # Try to extract model from recent transcript entries
    detected_model=$(tail -5 "$real_transcript" 2>/dev/null | jq -r '.message.model // empty' 2>/dev/null | grep -v '^$' | head -1)
    if [[ -n "$detected_model" ]]; then
        model_name="$detected_model"
    fi
fi

# Format model name for display (shorten if needed)
model_display="$model_name"
case "$model_name" in
    *opus*|*Opus*)
        model_display="Opus"
        model_color="35"  # Magenta for Opus
        ;;
    *sonnet*|*Sonnet*)
        model_display="Sonnet"
        model_color="34"  # Blue for Sonnet (changed from cyan)
        ;;
    *haiku*|*Haiku*)
        model_display="Haiku"
        model_color="32"  # Green for Haiku
        ;;
    *claude-3*)
        model_display="Claude 3"
        model_color="34"  # Blue for Claude 3
        ;;
    *claude-instant*)
        model_display="Instant"
        model_color="33"  # Yellow for Instant
        ;;

    # OpenAI models
    *gpt-4o*)
        model_display="GPT-4o"
        model_color="37"  # White for GPT-4o
        ;;
    *gpt-4-turbo*)
        model_display="GPT-4 Turbo"
        model_color="31"  # Red for GPT-4 Turbo
        ;;
    *gpt-4*)
        model_display="GPT-4"
        model_color="31"  # Red for GPT-4
        ;;
    *gpt-3.5*)
        model_display="GPT-3.5"
        model_color="93"  # Bright Yellow for GPT-3.5
        ;;

    # xAI Grok models
    *grok*)
        model_display="Grok"
        model_color="33"  # Yellow for Grok
        ;;
    *)
        # Default to extracting version if present
        if [[ "$model_name" =~ claude-([0-9]+) ]]; then
            model_display="Claude ${BASH_REMATCH[1]}"
        else
            model_display="Claude"
        fi
        model_color="34"  # Blue for default (changed from white)
        ;;
esac

# Detect theme from environment or settings (future enhancement)
# For now, use the JSON input to check for theme hints
theme_name=$(echo "$input" | jq -r '.theme // .appearance // "default"' 2>/dev/null)

# Adjust colors based on theme (if available)
if [[ "$theme_name" == "light" || "$theme_name" == "day" ]]; then
    # Light theme - use darker/bolder colors
    model_color="1;${model_color}"  # Bold version
fi

# Build status line based on selected mode
case "$STATUSLINE_MODE" in
    "compact")
        # Compact mode: Model, context, message/time, project
        if [[ -n "$message_display" ]]; then
            # Show truncated message preview (first 3 words for compact)
            compact_message=$(echo "$message_preview" | awk '{print $1, $2, $3}' | sed 's/ *$//')
            if [[ "$message_preview" != "$compact_message" ]]; then
                compact_message="${compact_message}..."
            fi
            printf "\033[%sm%s\033[0m • \033[32m%d%%\033[0m • 💬 \"%s\" • \033[34m%s\033[0m\n" \
                "$model_color" \
                "$model_display" \
                "$context_percent" \
                "$compact_message" \
                "$project_name"
        else
            # Fall back to time if no message
            printf "\033[%sm%s\033[0m • \033[32m%d%%\033[0m • \033[%sm%s\033[0m • \033[34m%s\033[0m\n" \
                "$model_color" \
                "$model_display" \
                "$context_percent" \
                "$msg_color" \
                "$last_msg" \
                "$project_name"
        fi
        ;;

    "custom")
        # Custom mode: Use template with variable substitution
        output="$CUSTOM_FORMAT"
        output="${output//\%model\%/$model_display}"
        output="${output//\%context\%/$context_info}"
        output="${output//\%percent\%/${context_percent}%}"
        output="${output//\%remaining\%/${remaining_display}}"
        output="${output//\%session\%/$session_date}"
        output="${output//\%time\%/$pst_time}"
        output="${output//\%last\%/$last_msg}"
        output="${output//\%project\%/$project_name}"
        output="${output//\%message\%/$message_display}"
        echo "$output"
        ;;

    "verbose"|*)
        # Verbose mode (default): Model first, then full information
        if [[ -n "$message_display" ]]; then
            # Show message preview instead of last time
            printf "\033[%sm%s\033[0m \033[36m▸\033[0m Context: %s \033[36m▸\033[0m Session: \033[96m%s\033[0m \033[36m▸\033[0m %s \033[36m▸\033[0m %s \033[36m▸\033[0m \033[34m%s\033[0m\n" \
                "$model_color" \
                "$model_display" \
                "$context_info" \
                "$session_date" \
                "$pst_time" \
                "$message_display" \
                "$project_name"
        else
            # If no message, show timing instead
            printf "\033[%sm%s\033[0m \033[36m▸\033[0m Context: %s \033[36m▸\033[0m Session: \033[96m%s\033[0m \033[36m▸\033[0m %s \033[36m▸\033[0m Last: \033[%sm%s\033[0m \033[36m▸\033[0m \033[34m%s\033[0m\n" \
                "$model_color" \
                "$model_display" \
                "$context_info" \
                "$session_date" \
                "$pst_time" \
                "$msg_color" \
                "$last_msg" \
                "$project_name"
        fi
        ;;
esac