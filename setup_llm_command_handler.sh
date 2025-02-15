#!/bin/bash

# Determine the current shell
SHELL_NAME=$(basename "$SHELL")

# Define script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="$HOME/.llm_command_handler.sh"
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

# Copy or symlink the LLM command handler from the same repo
echo "[✔] Installing LLM Command Handler..."
cp "$SCRIPT_DIR/llm_command_handler.sh" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# Add source to shell configs
if [[ "$SHELL_NAME" == "zsh" || "$SHELL_NAME" == "bash" ]]; then
    if ! grep -q "source $INSTALL_PATH" "$ENV_FILE"; then
        echo "source $INSTALL_PATH" >> "$ENV_FILE"
    fi
elif [[ "$SHELL_NAME" == "fish" ]]; then
    if ! grep -q "source $FISH_SCRIPT_PATH" "$ENV_FILE"; then
        echo "source $FISH_SCRIPT_PATH" >> "$ENV_FILE"
    fi
fi

# Reload shell
echo "[✔] Installation complete! Restarting shell..."
exec "$SHELL"
