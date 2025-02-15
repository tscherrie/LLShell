# LLM Command Handler

This script integrates OpenAI's GPT-4o into your command line, allowing it to:
- Auto-correct invalid commands.
- Provide the correct command directly into your shell prompt.
- Offer explanations when explicitly requested.

## Supported Shells
- Zsh (macOS & Linux)
- Bash (macOS & Linux)
- Fish (macOS & Linux)

## Installation

### 1. Download & Run the Installer
```sh
curl -o setup_llm_command_handler.sh https://your-hosted-script-url.com
chmod +x setup_llm_command_handler.sh
./setup_llm_command_handler.sh
```

### 2. Follow the Prompts
- Enter your OpenAI API key when asked.
- The script will automatically configure your shell.
- Your shell will reload to apply the changes.

## Usage Examples
```sh
# Ask for a command
create a directory named test  # LLM outputs: mkdir test

# Fix an incorrect command
mke dir test  # LLM corrects: mkdir test

# Request an explanation
Why does 'ls' not work?  # LLM explains with "Message: ..." output
```

### Uninstall
To remove the setup, delete the following lines from your `~/.zshrc`, `~/.bashrc`, or `~/.config/fish/config.fish`:
```sh
source ~/.llm_command_handler.sh
source ~/.config/fish/functions/llm_command_handler.fish
```
Then, remove the script files:
```sh
rm -f ~/.llm_command_handler.sh ~/.config/fish/functions/llm_command_handler.fish
```

Enjoy an AI-powered command line experience! 🚀
