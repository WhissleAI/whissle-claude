#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# lulu-code — Unified setup for MCP server + hooks + voice
#
# Usage:
#   ./setup.sh                  # interactive — prompts for everything
#   ./setup.sh --all            # install for all supported clients
#   ./setup.sh --claude-code    # Claude Code only
#   ./setup.sh --cursor         # Cursor only
#   ./setup.sh --claude-desktop # Claude Desktop only
#   ./setup.sh --opencode       # OpenCode only
#   ./setup.sh --mcp-only       # skip voice prerequisites + install
#   ./setup.sh --voice-only     # skip MCP server installation
#
# Environment variables (skip prompts):
#   WHISSLE_API_TOKEN, WHISSLE_USER_ID, WHISSLE_USER_NAME, WHISSLE_LOCATION
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/venv"
PYTHON="${VENV_DIR}/bin/python"
SERVER_PY="$SCRIPT_DIR/server.py"
VOICE_DIR="$SCRIPT_DIR/claude-voice"
TOKEN_DIR="$HOME/.claude-voice"
TOKEN_FILE="$TOKEN_DIR/.env"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}*${NC} $*"; }
ok()    { echo -e "${GREEN}+${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
err()   { echo -e "${RED}x${NC} $*" >&2; }

# ── Parse flags ──────────────────────────────────────────────────────────────
DO_CLAUDE_CODE=false
DO_CURSOR=false
DO_CLAUDE_DESKTOP=false
DO_OPENCODE=false
INTERACTIVE=true
SKIP_VOICE=false
SKIP_MCP=false

for arg in "$@"; do
  case "$arg" in
    --all)            DO_CLAUDE_CODE=true; DO_CURSOR=true; DO_CLAUDE_DESKTOP=true; DO_OPENCODE=true; INTERACTIVE=false ;;
    --claude-code)    DO_CLAUDE_CODE=true; INTERACTIVE=false ;;
    --cursor)         DO_CURSOR=true; INTERACTIVE=false ;;
    --claude-desktop) DO_CLAUDE_DESKTOP=true; INTERACTIVE=false ;;
    --opencode)       DO_OPENCODE=true; INTERACTIVE=false ;;
    --mcp-only)       SKIP_VOICE=true ;;
    --voice-only)     SKIP_MCP=true ;;
    --help|-h)
      echo "Usage: ./setup.sh [flags]"
      echo ""
      echo "Flags:"
      echo "  --all              Install for all supported clients"
      echo "  --claude-code      Claude Code only"
      echo "  --cursor           Cursor only"
      echo "  --claude-desktop   Claude Desktop only"
      echo "  --opencode         OpenCode only"
      echo "  --mcp-only         Skip voice (claude-voice) setup"
      echo "  --voice-only       Skip MCP server setup"
      echo ""
      echo "Sets up the Lulu MCP server (42 tools) and claude-voice"
      echo "(Alt+V voice dictation) for your AI coding tools."
      exit 0 ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Lulu Setup${NC}"
echo "=============================="
echo ""

# ── Detect OS ────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PKG_MGR="brew" ;;
  Linux)
    if command -v apt-get &>/dev/null; then
      PKG_MGR="apt"
    elif command -v dnf &>/dev/null; then
      PKG_MGR="dnf"
    elif command -v yum &>/dev/null; then
      PKG_MGR="yum"
    elif command -v pacman &>/dev/null; then
      PKG_MGR="pacman"
    else
      PKG_MGR="unknown"
    fi
    ;;
  *)      err "Unsupported OS: $OS"; exit 1 ;;
esac

# ── Helper: install a package via the detected package manager ───────────────
pkg_install() {
  local pkg="$1"
  case "$PKG_MGR" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get install -y "$pkg" ;;
    dnf)    sudo dnf install -y "$pkg" ;;
    yum)    sudo yum install -y "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
    *)      err "Unknown package manager. Install '$pkg' manually."; return 1 ;;
  esac
}

pkg_install_prompt() {
  local pkg="$1" display="${2:-$1}"
  echo -n "    Install $display via $PKG_MGR? [Y/n] "
  read -r answer
  if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
    warn "Skipping. Install manually: $PKG_MGR install $pkg"
    return 1
  fi
  pkg_install "$pkg"
}

# ── Voice prerequisites ─────────────────────────────────────────────────────
if ! $SKIP_VOICE; then
  echo -e "${BOLD}1. Prerequisites${NC}"
  echo ""

  # Node.js 20+
  if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VERSION" -ge 20 ]; then
      ok "Node.js $(node -v)"
    else
      err "Node.js $(node -v) found but v20+ is required"
      echo "    Install: https://nodejs.org or 'nvm install 22'"
      exit 1
    fi
  else
    err "Node.js not found"
    echo "    Install v20+ from https://nodejs.org or:"
    echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
    echo "    nvm install 22"
    exit 1
  fi

  # sox
  if command -v rec &>/dev/null || command -v sox &>/dev/null; then
    ok "sox ($(which rec 2>/dev/null || which sox))"
  else
    warn "sox not found — required for microphone capture"
    pkg_install_prompt "sox" || true
  fi

  # Claude Code CLI
  if command -v claude &>/dev/null; then
    ok "Claude Code CLI ($(which claude))"
  else
    warn "Claude Code CLI not found"
    echo -n "    Install via npm? [Y/n] "
    read -r answer
    if [[ "${answer:-Y}" =~ ^[Nn] ]]; then
      warn "Skipping. Install manually: npm install -g @anthropic-ai/claude-code"
    else
      npm install -g @anthropic-ai/claude-code
      ok "Claude Code CLI installed"
    fi
  fi

  echo ""
fi

# ── MCP server dependencies ─────────────────────────────────────────────────
if ! $SKIP_MCP; then
  echo -e "${BOLD}2. MCP Server${NC}"
  echo ""

  # Ensure python3 is available
  if ! command -v python3 &>/dev/null; then
    err "python3 not found. Install Python 3.11+ and re-run."
    exit 1
  fi

  if [ ! -f "$PYTHON" ] || ! "$PYTHON" --version &>/dev/null; then
    info "Creating Python virtual environment..."
    rm -rf "$VENV_DIR"
    # On Debian/Ubuntu, python3-venv may not be installed
    if ! python3 -m venv "$VENV_DIR" 2>/dev/null; then
      if [ "$PKG_MGR" = "apt" ]; then
        warn "python3-venv not installed"
        PYVER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        pkg_install_prompt "python3.${PYVER##*.}-venv" "python3-venv" || {
          # Fall back to generic package name
          pkg_install "python3-venv" 2>/dev/null || true
        }
        python3 -m venv "$VENV_DIR"
      else
        err "Failed to create venv. Ensure python3-venv is installed."
        exit 1
      fi
    fi
  fi

  info "Installing Python dependencies..."
  PIP_OUTPUT=$("$VENV_DIR/bin/pip" install -q -e "$SCRIPT_DIR" 2>&1) || {
    err "pip install failed:"
    echo "$PIP_OUTPUT" | grep -v "^\[notice\]" >&2
    err "Try deleting venv/ and re-running setup."
    exit 1
  }
  echo "$PIP_OUTPUT" | grep -v "^\[notice\]" | grep -v "^$" || true
  ok "MCP server ready (42 tools)"
  echo ""
fi

# ── Voice dependencies ──────────────────────────────────────────────────────
if ! $SKIP_VOICE; then
  echo -e "${BOLD}3. Voice (claude-voice)${NC}"
  echo ""

  info "Installing Node.js dependencies..."
  (cd "$VOICE_DIR" && npm install --silent 2>/dev/null)
  chmod +x "$VOICE_DIR/claude-voice"
  ok "claude-voice ready"
  echo ""
fi

# ── Collect credentials ─────────────────────────────────────────────────────
echo -e "${BOLD}4. Credentials${NC}"
echo ""

if [ -z "${WHISSLE_API_TOKEN:-}" ] && [ -z "${WHISSLE_USER_ID:-}" ]; then
  # Check for saved credentials (POSIX-compatible parsing)
  _get_env_val() { grep "^$1=" "$TOKEN_FILE" 2>/dev/null | sed "s/^$1=//" | head -1; }
  if [ -f "$TOKEN_FILE" ]; then
    SAVED_TOKEN=$(_get_env_val WHISSLE_API_TOKEN)
    SAVED_UID=$(_get_env_val WHISSLE_USER_ID)
    if [ -n "$SAVED_TOKEN" ]; then
      info "Found saved token (${SAVED_TOKEN:0:8}...)"
      echo -n "  Use saved token? [Y/n] "
      read -r answer
      if [[ "${answer:-Y}" =~ ^[Yy]$ ]] || [ -z "$answer" ]; then
        WHISSLE_API_TOKEN="$SAVED_TOKEN"
        WHISSLE_USER_NAME=$(_get_env_val WHISSLE_USER_NAME)
        WHISSLE_LOCATION=$(_get_env_val WHISSLE_LOCATION)
      fi
    elif [ -n "$SAVED_UID" ]; then
      info "Found saved user ID (${SAVED_UID:0:12}...)"
      echo -n "  Use saved user ID? [Y/n] "
      read -r answer
      if [[ "${answer:-Y}" =~ ^[Yy]$ ]] || [ -z "$answer" ]; then
        WHISSLE_USER_ID="$SAVED_UID"
        WHISSLE_USER_NAME=$(_get_env_val WHISSLE_USER_NAME)
        WHISSLE_LOCATION=$(_get_env_val WHISSLE_LOCATION)
      fi
    fi
  fi
fi

if [ -z "${WHISSLE_API_TOKEN:-}" ] && [ -z "${WHISSLE_USER_ID:-}" ]; then
  info "Get a token at lulu.whissle.ai/access"
  echo ""
  echo -n "  API token (wh_...) or user ID: "
  read -r CRED_INPUT
  if [[ "$CRED_INPUT" == wh_* ]]; then
    WHISSLE_API_TOKEN="$CRED_INPUT"
    WHISSLE_USER_ID=""
  else
    WHISSLE_USER_ID="$CRED_INPUT"
    WHISSLE_API_TOKEN=""
  fi
fi

if [ -z "${WHISSLE_USER_NAME:-}" ]; then
  echo -n "  Your name (for personalization, enter to skip): "
  read -r WHISSLE_USER_NAME
fi

if [ -z "${WHISSLE_LOCATION:-}" ]; then
  echo -n "  Default location (e.g. San Francisco, enter to skip): "
  read -r WHISSLE_LOCATION
fi

echo ""

# ── Validate token ──────────────────────────────────────────────────────────
if [ -n "${WHISSLE_API_TOKEN:-}" ] && [[ "$WHISSLE_API_TOKEN" == wh_* ]]; then
  info "Validating token..."
  VALIDATE_URL="https://live-assist-backend-843574834406.europe-west1.run.app/api-tokens/validate?token=$WHISSLE_API_TOKEN"
  VALIDATE_TMP=$(mktemp)
  HTTP_CODE=$(curl -s -o "$VALIDATE_TMP" -w "%{http_code}" "$VALIDATE_URL" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    VALID=$(python3 -c "import json; d=json.load(open('$VALIDATE_TMP')); print(d.get('valid',''))" 2>/dev/null || echo "")
    DEVICE_ID=$(python3 -c "import json; d=json.load(open('$VALIDATE_TMP')); print(d.get('deviceId',''))" 2>/dev/null || echo "")
    if [ "$VALID" = "True" ]; then
      ok "Token validated (device: ${DEVICE_ID:0:12}...)"
    else
      err "Token is invalid. Get a new one at lulu.whissle.ai/access"
      rm -f "$VALIDATE_TMP"
      exit 1
    fi
  else
    warn "Could not validate token (HTTP $HTTP_CODE). Continuing anyway..."
  fi
  rm -f "$VALIDATE_TMP"
fi

# ── Persist credentials ─────────────────────────────────────────────────────
mkdir -p "$TOKEN_DIR"
cat > "$TOKEN_FILE" <<EOF
# Lulu credentials — generated by setup.sh on $(date +%Y-%m-%d)
WHISSLE_API_TOKEN=${WHISSLE_API_TOKEN:-}
WHISSLE_USER_ID=${WHISSLE_USER_ID:-}
WHISSLE_USER_NAME=${WHISSLE_USER_NAME:-}
WHISSLE_LOCATION=${WHISSLE_LOCATION:-}
EOF
chmod 600 "$TOKEN_FILE"
ok "Credentials saved to $TOKEN_FILE"
echo ""

# ── Choose MCP targets ──────────────────────────────────────────────────────
if ! $SKIP_MCP; then
  if $INTERACTIVE; then
    echo -e "${BOLD}5. Configure MCP${NC}"
    echo ""
    echo "  Which tools to configure?"
    echo "    1) Claude Code"
    echo "    2) Cursor"
    echo "    3) Claude Desktop"
    echo "    4) OpenCode"
    echo "    5) All of the above"
    echo -n "  Choice [1-5, default=5]: "
    read -r CHOICE
    case "${CHOICE:-5}" in
      1) DO_CLAUDE_CODE=true ;;
      2) DO_CURSOR=true ;;
      3) DO_CLAUDE_DESKTOP=true ;;
      4) DO_OPENCODE=true ;;
      5) DO_CLAUDE_CODE=true; DO_CURSOR=true; DO_CLAUDE_DESKTOP=true; DO_OPENCODE=true ;;
      *) err "Invalid choice"; exit 1 ;;
    esac
    echo ""
  fi

  # ── Helpers ──────────────────────────────────────────────────────────────
  ensure_jq() {
    if ! command -v jq &>/dev/null; then
      err "jq is required for JSON config updates."
      pkg_install_prompt "jq" || {
        err "Cannot continue without jq."
        exit 1
      }
      ok "jq installed"
    fi
  }

  build_env_json() {
    ensure_jq
    local env="{}"
    if [ -n "${WHISSLE_API_TOKEN:-}" ]; then
      env=$(echo "$env" | jq --arg v "$WHISSLE_API_TOKEN" '.WHISSLE_API_TOKEN = $v')
    elif [ -n "${WHISSLE_USER_ID:-}" ]; then
      env=$(echo "$env" | jq --arg v "$WHISSLE_USER_ID" '.WHISSLE_USER_ID = $v')
    fi
    if [ -n "${WHISSLE_USER_NAME:-}" ]; then
      env=$(echo "$env" | jq --arg v "$WHISSLE_USER_NAME" '.WHISSLE_USER_NAME = $v')
    fi
    if [ -n "${WHISSLE_LOCATION:-}" ]; then
      env=$(echo "$env" | jq --arg v "$WHISSLE_LOCATION" '.WHISSLE_LOCATION = $v')
    fi
    echo "$env"
  }

  ENV_JSON=$(build_env_json)

  upsert_mcp_config() {
    local file="$1" name="$2" server_json="$3"
    ensure_jq
    if [ ! -f "$file" ]; then
      mkdir -p "$(dirname "$file")"
      echo '{}' > "$file"
    fi
    local tmp
    tmp=$(mktemp)
    jq --arg name "$name" --argjson srv "$server_json" \
      '.mcpServers[$name] = $srv' "$file" > "$tmp" && mv "$tmp" "$file"
  }

  MCP_SERVER_JSON=$(cat <<ENDJSON
{
  "command": "$PYTHON",
  "args": ["$SERVER_PY"],
  "env": $ENV_JSON
}
ENDJSON
)

  # ── Configure targets ──────────────────────────────────────────────────
  if $DO_CLAUDE_CODE; then
    info "Configuring Claude Code..."
    # Claude Code reads MCP servers from ~/.claude.json
    CLAUDE_JSON="$HOME/.claude.json"
    # Hooks go in ~/.claude/settings.json
    CLAUDE_SETTINGS="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    if [ ! -f "$CLAUDE_JSON" ]; then
      echo '{}' > "$CLAUDE_JSON"
    fi
    if [ ! -f "$CLAUDE_SETTINGS" ]; then
      echo '{}' > "$CLAUDE_SETTINGS"
    fi
    ensure_jq

    # Write MCP server config to ~/.claude.json (primary)
    tmp=$(mktemp)
    jq --argjson srv "$MCP_SERVER_JSON" \
      '.mcpServers.whissle = $srv' "$CLAUDE_JSON" > "$tmp" && mv "$tmp" "$CLAUDE_JSON"

    # Also sync to ~/.claude/settings.json
    tmp=$(mktemp)
    jq --argjson srv "$MCP_SERVER_JSON" \
      '.mcpServers.whissle = $srv' "$CLAUDE_SETTINGS" > "$tmp" && mv "$tmp" "$CLAUDE_SETTINGS"

    # Clean up stale project-level permissions that could cause tool bypass
    LOCAL_SETTINGS="$SCRIPT_DIR/.claude/settings.local.json"
    if [ -f "$LOCAL_SETTINGS" ]; then
      rm -f "$LOCAL_SETTINGS"
      info "Cleaned stale project permissions"
    fi

    ok "Claude Code MCP configured"
  fi

  if $DO_CURSOR; then
    info "Configuring Cursor..."
    CURSOR_GLOBAL="$HOME/.cursor/mcp.json"
    upsert_mcp_config "$CURSOR_GLOBAL" "whissle" "$MCP_SERVER_JSON"
    ok "Cursor configured ($CURSOR_GLOBAL)"
  fi

  if $DO_CLAUDE_DESKTOP; then
    info "Configuring Claude Desktop..."
    if [[ "$OSTYPE" == darwin* ]]; then
      DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    else
      DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
    fi
    upsert_mcp_config "$DESKTOP_CONFIG" "whissle" "$MCP_SERVER_JSON"
    ok "Claude Desktop configured ($DESKTOP_CONFIG)"
  fi

  if $DO_OPENCODE; then
    info "Configuring OpenCode..."
    OPENCODE_CONFIG="$HOME/.config/opencode/opencode.json"
    ensure_jq
    mkdir -p "$HOME/.config/opencode"
    if [ ! -f "$OPENCODE_CONFIG" ]; then
      echo '{}' > "$OPENCODE_CONFIG"
    fi

    OPENCODE_ENV_JSON=$(build_env_json)
    OPENCODE_MCP_JSON=$(cat <<ENDJSON
{
  "type": "local",
  "command": ["$PYTHON", "$SERVER_PY"],
  "environment": $OPENCODE_ENV_JSON
}
ENDJSON
)
    tmp=$(mktemp)
    jq --argjson srv "$OPENCODE_MCP_JSON" \
      '.mcp.whissle = $srv' "$OPENCODE_CONFIG" > "$tmp" && mv "$tmp" "$OPENCODE_CONFIG"
    ok "OpenCode configured ($OPENCODE_CONFIG)"
  fi

  # ── Configure hooks (Claude Code only) ──────────────────────────────────
  if $DO_CLAUDE_CODE; then
    info "Configuring Claude Code hooks..."
    HOOKS_DIR="$SCRIPT_DIR/hooks"
    chmod +x "$HOOKS_DIR/prompt-submit.py" "$HOOKS_DIR/session-start.py" 2>/dev/null || true

    HOOK_ENV="WHISSLE_API_TOKEN='${WHISSLE_API_TOKEN:-}'"
    [ -n "${WHISSLE_USER_NAME:-}" ] && HOOK_ENV="$HOOK_ENV WHISSLE_USER_NAME='$WHISSLE_USER_NAME'"
    [ -n "${WHISSLE_LOCATION:-}" ] && HOOK_ENV="$HOOK_ENV WHISSLE_LOCATION='$WHISSLE_LOCATION'"

    PROMPT_HOOK_CMD="$HOOK_ENV $PYTHON $HOOKS_DIR/prompt-submit.py"
    SESSION_HOOK_CMD="$HOOK_ENV $PYTHON $HOOKS_DIR/session-start.py"

    python3 -c "
import json, os

settings_path = os.path.expanduser('$CLAUDE_SETTINGS')
try:
    with open(settings_path) as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

hooks = settings.setdefault('hooks', {})
hooks['UserPromptSubmit'] = [{'hooks': [{'type': 'command', 'command': '''$PROMPT_HOOK_CMD''', 'statusMessage': 'Lulu: reading emotion + intent...'}]}]
hooks['SessionStart'] = [{'hooks': [{'type': 'command', 'command': '''$SESSION_HOOK_CMD''', 'statusMessage': 'Lulu: loading your personality...'}]}]

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
"
    ok "Hooks configured (emotion/intent on every prompt, personality on session start)"
  fi

  echo ""
fi

# ── Make claude-voice globally accessible ────────────────────────────────────
if ! $SKIP_VOICE; then
  VOICE_BIN="$VOICE_DIR/claude-voice"
  echo -e "${BOLD}6. Global Access${NC}"
  echo ""
  echo "  Make 'claude-voice' available from anywhere?"
  echo "    1) Symlink to /usr/local/bin (may need sudo)"
  echo "    2) Symlink to ~/.local/bin"
  echo "    3) Skip (run from $VOICE_BIN)"
  echo -n "  Choice [1-3, default=3]: "
  read -r LINK_CHOICE
  case "${LINK_CHOICE:-3}" in
    1)
      sudo ln -sf "$VOICE_BIN" /usr/local/bin/claude-voice
      ok "claude-voice linked to /usr/local/bin/claude-voice"
      ;;
    2)
      mkdir -p "$HOME/.local/bin"
      ln -sf "$VOICE_BIN" "$HOME/.local/bin/claude-voice"
      ok "claude-voice linked to ~/.local/bin/claude-voice"
      if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        warn "~/.local/bin is not in your PATH. Add to your shell profile:"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
      fi
      ;;
    3)
      info "Skipping symlink. Run directly: $VOICE_BIN"
      ;;
  esac
  echo ""
fi

# ── Verify MCP server ───────────────────────────────────────────────────────
if ! $SKIP_MCP; then
  echo -e "${BOLD}7. Verification${NC}"
  echo ""

  info "Testing MCP server..."
  INIT_MSG='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"setup-test","version":"0.1"}}}'
  MCP_RESULT=$(echo "$INIT_MSG" | timeout 15 "$PYTHON" "$SERVER_PY" 2>/dev/null) || true

  if echo "$MCP_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['result']['serverInfo']['name']=='Lulu'" 2>/dev/null; then
    TOOL_COUNT=$(printf '%s\n%s\n%s\n' \
      "$INIT_MSG" \
      '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
      '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
      | timeout 15 "$PYTHON" "$SERVER_PY" 2>/dev/null \
      | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('id') == 2:
            print(len(d.get('result',{}).get('tools',[])))
    except: pass
" 2>/dev/null || echo "?")
    ok "MCP server OK — ${TOOL_COUNT} tools registered"
  else
    warn "MCP server test failed. Check: $PYTHON $SERVER_PY"
    warn "Try deleting venv/ and re-running setup."
  fi

  echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo ""

if ! $SKIP_MCP; then
  echo "  MCP Server (42 tools):"
  echo "    Core, Memory, Calendar, Email, Contacts, Drive, Tasks,"
  echo "    Web Search, Finance, Media, Utilities, Navigation, Weather"
  echo ""
  if $DO_CLAUDE_CODE; then
    echo "  Hooks (Claude Code):"
    echo "    SessionStart  — loads your personality + archetype on every session"
    echo "    PromptSubmit  — extracts emotion/intent from every typed prompt"
    echo ""
  fi
  if $DO_OPENCODE; then
    echo "  OpenCode:"
    echo "    MCP tools configured. Note: OpenCode does not support hooks."
    echo ""
  fi
  echo "    Restart your AI tool to pick up the new configuration."
  echo ""
fi

if ! $SKIP_VOICE; then
  echo "  Voice Dictation (claude-voice):"
  echo "    Run:  claude-voice"
  echo "    Keys: Alt+V to toggle recording"
  echo "    Pair: claude-voice --speakers alice,bob"
  echo ""
fi

echo "  Credentials: $TOKEN_FILE"
echo ""
