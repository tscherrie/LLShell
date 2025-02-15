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

    # Properly escape the user input for JSON formatting
    local user_input
    user_input=$(printf "%s" "$prompt" | jq -Rs .)

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
            "content": $user_input
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
