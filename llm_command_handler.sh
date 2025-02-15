##############################
# Optional Debug Logging Function
##############################
llm_log() {
    if [[ -n "$LLM_DEBUG" ]]; then
        echo "[LLM-DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $*" >> /tmp/llm_command_handler.log
    fi
}

##############################
# Global conversation context for LLM (resets each session)
##############################
if [ -z "$LLM_CONTEXT_INITIALIZED" ]; then
    typeset -ga LLM_CONTEXT_ARRAY
    LLM_CONTEXT_ARRAY=()
    LLM_CONTEXT_INITIALIZED=1
    llm_log "Initialized LLM context."
fi

##############################
# ZLE Hook: Prefill LBUFFER when a new command line is initialized
##############################
zle_llm_suggestion() {
    if [ -f /tmp/llm_suggestion ]; then
        local suggestion
        suggestion=$(cat /tmp/llm_suggestion)
        if [ -n "$suggestion" ]; then
            llm_log "Prefilling suggestion into LBUFFER: '$suggestion'"
            LBUFFER="$suggestion"
            zle reset-prompt
        else
            llm_log "Suggestion file exists but is empty."
        fi
        rm -f /tmp/llm_suggestion
    else
        llm_log "No suggestion file found."
    fi
}
zle -N zle_llm_suggestion
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init zle_llm_suggestion

##############################
# Command-Not-Found Handler Using LLM
##############################
command_not_found_handler() {
    # Print the standard error message.
    echo "zsh: command not found: $1"
    echo "Asking LLM..."
    llm_log "Command not found: $*"

    local prompt="$*"

    # Basic dependency checks.
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Error: OPENAI_API_KEY is not set."
        llm_log "Missing OPENAI_API_KEY."
        return 127
    fi
    if ! command -v curl >/dev/null; then
        echo "Error: curl is not installed."
        llm_log "curl not installed."
        return 127
    fi
    if ! command -v jq >/dev/null; then
        echo "Error: jq is not installed."
        llm_log "jq not installed."
        return 127
    fi

    # Escape the full prompt for safe JSON embedding.
    local user_input
    user_input=$(printf "%s" "$prompt" | jq -Rs .)
    llm_log "User input (JSON escaped): $user_input"

    # Build the messages JSON array using a fixed system message and any prior context.
    local system_message='{"role": "system", "content": "You are a command-line assistant. Follow these rules strictly:\n\n1. If the user asks for a command, output only the command and nothing else.\n2. If the user enters a seemingly incorrect command, output only the corrected version of the command with no explanation or extra text.\n3. If the user asks for an explanation, prefix your response with \"Message:\".\n\nNever mix the three formats."}'
    local context_json=""
    if [ ${#LLM_CONTEXT_ARRAY[@]} -gt 0 ]; then
        local joined_context
        joined_context=$(IFS=,; echo "${LLM_CONTEXT_ARRAY[*]}")
        context_json=", $joined_context"
    fi
    local messages_json
    messages_json=$(printf '[%s%s, {"role": "user", "content": %s}]' "$system_message" "$context_json" "$user_input")
    local payload
    payload=$(printf '{"model": "gpt-4o", "temperature": 0, "messages": %s}' "$messages_json")
    llm_log "Payload: $payload"

    # Call the OpenAI API.
    local raw_response
    raw_response=$(curl -sS --fail -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        --data "$payload")
    if [ $? -ne 0 ]; then
        echo "Error: API connection failed."
        llm_log "API connection failed. Raw response: $raw_response"
        return 127
    fi
    llm_log "Raw API response: $raw_response"

    # Sanitize the API response (remove control characters).
    local sanitized_response
    sanitized_response=$(echo "$raw_response" | tr -d '\000-\037')
    llm_log "Sanitized API response: $sanitized_response"

    # Extract the assistant’s response.
    local content
    content=$(echo "$sanitized_response" | jq -r '.choices[0].message.content // empty')
    llm_log "Extracted content: $content"
    if [ -z "$content" ] || [ "$content" = "null" ]; then
        echo "Error: Invalid response from LLM."
        llm_log "Content is empty or null."
        return 127
    fi

    # Append this exchange to our conversation context.
    local assistant_json
    assistant_json=$(printf "%s" "$content" | jq -Rs .)
    LLM_CONTEXT_ARRAY+=("{\"role\": \"user\", \"content\": $user_input}")
    LLM_CONTEXT_ARRAY+=("{\"role\": \"assistant\", \"content\": $assistant_json}")
    llm_log "Updated LLM_CONTEXT_ARRAY with new exchange."

    # Enforce a rolling context limit of 50,000 characters.
    local concatenated_context total_length
    concatenated_context=$(IFS=""; echo "${LLM_CONTEXT_ARRAY[*]}")
    total_length=${#concatenated_context}
    llm_log "Current total context length: $total_length"
    while [ $total_length -gt 50000 ] && [ ${#LLM_CONTEXT_ARRAY[@]} -gt 0 ]; do
        LLM_CONTEXT_ARRAY=("${LLM_CONTEXT_ARRAY[@]:1}")
        concatenated_context=$(IFS=""; echo "${LLM_CONTEXT_ARRAY[*]}")
        total_length=${#concatenated_context}
        llm_log "Trimmed context; new length: $total_length"
    done

    # If the LLM response starts with "Message:", print the explanation.
    # Otherwise, store the command suggestion in /tmp/llm_suggestion.
    if [[ "$content" == Message:* ]]; then
         echo ""
         echo "${content#Message: }" | sed 's/\\n/\n/g'
         echo ""
         llm_log "LLM returned an explanation."
    else
         llm_log "LLM returned a command suggestion: $content"
         echo "$content" > /tmp/llm_suggestion
         llm_log "Wrote suggestion to /tmp/llm_suggestion."
    fi

    return 127
}
