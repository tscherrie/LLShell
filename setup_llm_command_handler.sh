#!/bin/bash

# Determine the current shell
SHELL_NAME=$(basename "$SHELL")

# Define paths for different shells
ZSH_SCRIPT_PATH="$HOME/.llm_command_handler.sh"
BASH_SCRIPT_PATH="$HOME/.llm_command_handler.sh"
FISH_SCRIPT_PATH="$HOME/.config/fish/functions/llm_command_handler.fish"

# Ensure necessary directories exist for Fish
mkdir -p "$HOME/.config/fish/functions/"

# Check if OPENAI_API_KEY is already set
if [[ -z "$OPENAI_API_KEY" ]]; then
    read -p "Enter your OpenAI API Key: " OPENAI_API_KEY
else
    echo "[✔] Using existing OPENAI_API_KEY."
fi

# Store environment variables persistently
if [[ "$SHELL_NAME" == "zsh" || "$SHELL_NAME" == "bash" ]]; then
    ENV_FILE="$HOME/.${SHELL_NAME}rc"
    if ! grep -q "export OPENAI_API_KEY" "$ENV_FILE"; then
        echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\"" >> "$ENV_FILE"
    fi
elif [[ "$SHELL_NAME" == "fish" ]]; then
    ENV_FILE="$HOME/.config/fish/config.fish"
    if ! grep -q "set -x OPENAI_API_KEY" "$ENV_FILE"; then
        echo "set -x OPENAI_API_KEY \"$OPENAI_API_KEY\"" >> "$ENV_FILE"
    fi
else
    echo "Unsupported shell: $SHELL_NAME"
    exit 1
fi

# Write LLM Command Handler (Universal Version)
cat > "$ZSH_SCRIPT_PATH" << 'EOF'
##############################
# Global conversation context for LLM (resets each session)
##############################
if [ -z "$LLM_CONTEXT_INITIALIZED" ]; then
    typeset -ga LLM_CONTEXT_ARRAY
    LLM_CONTEXT_ARRAY=()
    LLM_CONTEXT_INITIALIZED=1
fi

##############################
# ZLE Hook: Prefill LBUFFER in Zsh
##############################
zle_llm_suggestion() {
    if [ -f /tmp/llm_suggestion ]; then
        local suggestion
        suggestion=$(cat /tmp/llm_suggestion)
        if [ -n "$suggestion" ]; then
            LBUFFER="$suggestion"
            zle reset-prompt
        fi
        rm -f /tmp/llm_suggestion
    fi
}
zle -N zle_llm_suggestion
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init zle_llm_suggestion

##############################
# Command-Not-Found Handler
##############################
command_not_found_handler() {
    echo "zsh: command not found: $1"
    echo "Asking LLM..."

    local prompt="$*"

    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY is not set."
        return 127
    fi
    if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
        echo "Error: Missing curl or jq."
        return 127
    fi

    local content
    content=$(curl -sS --fail -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        --data @- <<JSON
{
    "model": "gpt-4o",
    "temperature": 0,
    "messages": [
        {
            "role": "system",
            "content": "You are a command-line assistant. Follow these rules strictly:\n\n1. If the user asks for a command, output only the command and nothing else.\n2. If the user enters a seemingly incorrect command, output only the corrected version of the command with no explanation or extra text.\n3. If the user asks for an explanation, prefix your response with \"Message:\".\n\nNever mix the three formats."
        },
        {
            "role": "user",
            "content": "$prompt"
        }
    ]
}
JSON
    )

    content=$(echo "$content" | jq -r '.choices[0].message.content // empty')

    if [[ "$content" == Message:* ]]; then
        echo ""
        echo "${content#Message: }"
        echo ""
    else
        echo "$content" > /tmp/llm_suggestion
    fi
    return 127
}

if [[ -n "$BASH_VERSION" ]]; then
    trap 'command_not_found_handler "$BASH_COMMAND"' ERR
fi
EOF

# Handler for Fish
cat > "$FISH_SCRIPT_PATH" << 'EOF'
function llm_command_not_found --on-event fish_command_not_found
    echo "fish: command not found: $argv"
    echo "Asking LLM..."
    set response (curl -sS --fail -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        --data @- <<JSON
{
    "model": "gpt-4o",
    "temperature": 0,
    "messages": [
        {
            "role": "system",
            "content": "You are a command-line assistant. Follow these rules strictly:\n\n1. If the user asks for a command, output only the command and nothing else.\n2. If the user enters a seemingly incorrect command, output only the corrected version of the command with no explanation or extra text.\n3. If the user asks for an explanation, prefix your response with \"Message:\".\n\nNever mix the three formats."
        },
        {
            "role": "user",
            "content": "$argv"
        }
    ]
}
JSON
    )

    if string match -q "Message:*" "$response"
        echo (string replace "Message: " "" "$response")
    else
        echo "$response" > /tmp/llm_suggestion
    end
end
EOF

echo "[✔] Command handler installed."

if [[ "$SHELL_NAME" == "zsh" || "$SHELL_NAME" == "bash" ]]; then
    if ! grep -q "source $ZSH_SCRIPT_PATH" "$ENV_FILE"; then
        echo "source $ZSH_SCRIPT_PATH" >> "$ENV_FILE"
    fi
elif [[ "$SHELL_NAME" == "fish" ]]; then
    if ! grep -q "source $FISH_SCRIPT_PATH" "$ENV_FILE"; then
        echo "source $FISH_SCRIPT_PATH" >> "$ENV_FILE"
    fi
fi

exec "$SHELL"
