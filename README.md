# lulu-code

Personal AI middleware for Claude Code, Cursor, VS Code, and OpenCode. Lulu intercepts both text and voice input streams, enriches them with emotion, intent, and behavioral metadata, then passes the augmented context to your AI tool. Every interaction builds a personality profile that makes your coding assistant increasingly personalized over time.

## How it works

```
You (typing or speaking)
        |
   ┌────┴────┐
   v         v
 Text      Voice (Alt+V)
   |         |
   |    sox (mic) → Whissle ASR
   |         |
   v         v
┌──────────────────────────────────────┐
│          Lulu (middleware)            │
│                                      │
│  Text stream:                        │
│    regex → emotion + intent          │
│    async → behavioral profiling      │
│                                      │
│  Voice stream:                       │
│    ASR → transcription + emotion     │
│    + intent + demographics           │
│    + speech rate + speaker ID        │
│                                      │
│  Session start:                      │
│    personality + archetype loaded    │
│                                      │
│  Enriched input (text or voice)      │
│  + [user signal: emotion, intent]    │
│  + personality context               │
└──────────────┬───────────────────────┘
               v
┌────────────────────────────────────────────────┐
│  Claude Code / Cursor / VS Code / OpenCode     │
│                                                │
│  Receives enriched input with full             │
│  user context — acts on it                     │
│                                                │
│  + 42 MCP tools (calendar, email,              │
│    memory, research, drive, etc.)              │
└───────────────────────┬────────────────────────┘
                        v
          Whissle Gateway (api.whissle.ai)
          Personality, archetype, behavioral
          profile, conversation memory
```

Three layers:

| Layer | What it does | How |
|---|---|---|
| **Text stream** | Intercepts every typed prompt, extracts emotion + intent, enriches input before the AI tool sees it | Hooks (`UserPromptSubmit`, `SessionStart`) — Claude Code only |
| **Voice stream** | Alt+V push-to-talk — streams audio to Whissle ASR, returns transcription with emotion, intent, demographics, speech rate, speaker ID | `claude-voice` PTY wrapper |
| **MCP tools** | 42 tools — calendar, email, contacts, memory, research, web search, Drive, Tasks, finance, media, navigation, weather | MCP server (`server.py`) — all clients |

## Install

```bash
git clone https://github.com/WhissleAI/lulu-code.git
cd lulu-code
./setup.sh
```

The installer will:
1. Check prerequisites (Python 3.11+, Node.js 22+, sox, Claude Code CLI, jq)
2. Prompt for your Whissle token (get one at [lulu.whissle.ai/access](https://lulu.whissle.ai/access))
3. Validate the token against the Whissle gateway
4. Set up the Python venv and MCP server
5. Configure MCP for Claude Code, Cursor, OpenCode, and/or Claude Desktop
6. Configure hooks for Claude Code (emotion/intent on every prompt, personality on session start)
7. Install claude-voice dependencies and optionally symlink to PATH

Restart your AI tool after setup. All tools (and hooks for Claude Code) activate automatically.

### Setup flags

```bash
./setup.sh                  # interactive — prompts for everything
./setup.sh --all            # configure all clients at once
./setup.sh --claude-code    # Claude Code only
./setup.sh --cursor         # Cursor only
./setup.sh --claude-desktop # Claude Desktop only
./setup.sh --opencode       # OpenCode only
./setup.sh --mcp-only       # skip voice setup (no Node.js/sox needed)
./setup.sh --voice-only     # skip MCP server setup
```

## Text hooks

Configured automatically by `./setup.sh` for Claude Code. Two hooks with visible spinners:

**SessionStart** — fires once when Claude Code starts. Shows `Lulu: loading your personality...` spinner. Fetches your personality profile and archetype from the Lulu backend, injects it as context so your AI tool knows your communication style from the first prompt.

**UserPromptSubmit** — fires on every Enter press. Shows `Lulu: reading emotion + intent...` spinner. Runs local regex to extract emotion and intent (~5ms), returns it as `additionalContext` that Claude sees:
```
[user signal: emotion=ANGRY (60%), intent=QUERY (70%)]
```
Also fires an async API call to log the text for behavioral profiling (non-blocking).

Debug hooks: `claude --debug hooks`

## Voice input

```bash
claude-voice                              # single user
claude-voice --speakers karan,reviewer    # collaborative — pair programming
claude-voice --model sonnet               # pass-through Claude flags
claude-voice --continue                   # resume last conversation
```

Press **Alt+V** to toggle recording. Speak your prompt. Press **Alt+V** to stop. Your speech is transcribed in real-time with metadata injected inline:

```
fix the auth middleware <!-- voice: speaker:karan, emotion:ANGRY, intent:COMMAND -->
```

Claude-voice also maintains `.claude-voice/context.md` with conversation dynamics, speaker profiles, and planning recommendations that Claude reads before responding.

### What gets analyzed

| Input type | Emotion | Intent | Demographics | Speech rate | Speaker ID |
|---|---|---|---|---|---|
| **Typed text** (hooks) | Yes | Yes | — | — | — |
| **Typed text** (claude-voice) | Yes | Yes | Yes | — | Primary speaker |
| **Voice** (claude-voice) | Yes (acoustic) | Yes (acoustic) | Yes | Yes | Yes (embeddings) |

All input types feed the same personality pipeline.

## MCP Tools (42)

| Category | Tools |
|---|---|
| **Core** | `ask_agent`, `deep_research`, `get_user_context`, `get_user_personality` |
| **Memory** | `search_memories`, `store_memory` |
| **Calendar** | `check_calendar`, `create_calendar_event`, `set_reminder` |
| **Email** | `check_email`, `send_email` |
| **Contacts** | `search_contacts` |
| **Google Drive** | `search_drive`, `save_to_sheet`, `read_from_sheet` |
| **Google Tasks** | `create_task`, `list_tasks`, `complete_task` |
| **Web Search** | `web_search`, `read_url`, `fetch_news`, `get_news` |
| **Finance** | `get_stock_price`, `get_crypto_price`, `convert_currency` |
| **Media** | `search_videos`, `generate_image`, `analyze_image`, `analyze_audio`, `analyze_video` |
| **Utilities** | `translate_text`, `calculate`, `run_code`, `analyze_document`, `extract_text_metadata` |
| **Navigation** | `search_places`, `get_directions` |
| **Weather** | `get_weather`, `daily_briefing` |
| **Scheduling** | `schedule_recurring`, `list_scheduled_tasks`, `cancel_scheduled_task` |
| **Settings** | `set_preference` |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `WHISSLE_API_TOKEN` | One of | — | API token (`wh_...`) from lulu.whissle.ai/access |
| `WHISSLE_USER_ID` | these | — | Device/user ID from the Whissle app |
| `WHISSLE_USER_NAME` | No | — | Your name (personalized responses) |
| `WHISSLE_LOCATION` | No | — | Default location (weather/places) |
| `WHISSLE_ASR_URL` | No | `wss://api.whissle.ai/asr/stream` | ASR WebSocket endpoint |
| `WHISSLE_ASR_LANGUAGE` | No | `en` | Speech recognition language |

## Project Structure

```
lulu-code/
  setup.sh               # Unified installer — MCP + hooks + voice
  server.py              # MCP server — 42 tools
  pyproject.toml         # Python package config
  Dockerfile             # Cloud Run deployment (MCP only)
  hooks/
    prompt-submit.py     # UserPromptSubmit — emotion/intent extraction per prompt
    session-start.py     # SessionStart — loads personality + archetype
    shared.py            # Shared config, regex patterns, async profile logging
  claude-voice/
    claude-voice          # Shell entrypoint — loads token, launches PTY wrapper
    bin/claude-voice.mjs  # Node.js bin entrypoint for npm link
    package.json
    src/
      index.ts            # PTY wrapper, Alt+V intercept, system prompt injection
      mic.ts              # Microphone capture via sox/rec (16kHz PCM)
      asr-client.ts       # WebSocket client for Whissle ASR streaming
      metadata.ts         # SessionContextStore — context.md + planning recommendations
      speaker-tracker.ts  # Multi-speaker identification via cosine similarity
      text-metadata.ts    # Text intent/emotion classification (regex)
```

## Manual MCP Setup

If you prefer not to use `./setup.sh`:

**Claude Code** — `~/.claude.json` (MCP config) + `~/.claude/settings.json` (hooks):
```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/lulu-code/venv/bin/python",
      "args": ["/path/to/lulu-code/server.py"],
      "env": {
        "WHISSLE_API_TOKEN": "wh_your_token_here",
        "WHISSLE_USER_NAME": "Your Name",
        "WHISSLE_LOCATION": "Your City"
      }
    }
  }
}
```

**Cursor** — `~/.cursor/mcp.json`:
```json
{
  "mcpServers": {
    "whissle": {
      "command": "/path/to/lulu-code/venv/bin/python",
      "args": ["/path/to/lulu-code/server.py"],
      "env": { "WHISSLE_API_TOKEN": "wh_your_token_here" }
    }
  }
}
```

**OpenCode** — `~/.config/opencode/opencode.json`:
```json
{
  "mcp": {
    "whissle": {
      "type": "local",
      "command": ["/path/to/lulu-code/venv/bin/python", "/path/to/lulu-code/server.py"],
      "environment": {
        "WHISSLE_API_TOKEN": "wh_your_token_here",
        "WHISSLE_USER_NAME": "Your Name",
        "WHISSLE_LOCATION": "Your City"
      }
    }
  }
}
```

## Troubleshooting

**Hooks not firing** — Run `claude --debug hooks` to see hook lifecycle. Check `~/.claude/settings.json` has the `hooks` section. Restart Claude Code after setup.

**`sox not found`** — Install sox: `brew install sox` (macOS) or `sudo apt install sox` (Linux)

**`claude` not found** — Install Claude Code: `npm install -g @anthropic-ai/claude-code`

**Voice server connection failed** — Check your token is valid and you have internet connectivity

**MCP tools not appearing** — Restart your AI tool after `./setup.sh`. Check the relevant config file has the `whissle` MCP entry:
- Claude Code: `~/.claude.json` (MCP servers) and `~/.claude/settings.json` (hooks)
- Cursor: `~/.cursor/mcp.json`
- OpenCode: `~/.config/opencode/opencode.json`

**Token expired** — Re-run `./setup.sh` to enter a new token, or edit `~/.claude-voice/.env` directly.

## Uninstall

**Claude Code:**
Remove the `whissle` entry from `mcpServers` in `~/.claude.json` and `~/.claude/settings.json`. Remove the `hooks` key from `~/.claude/settings.json`.

**Cursor:** Remove the `whissle` entry from `~/.cursor/mcp.json`.

**OpenCode:** Remove the `whissle` entry from the `mcp` section in `~/.config/opencode/opencode.json`.
