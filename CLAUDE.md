# CLAUDE.md — Lulu Code

## MCP Tool Routing

This project includes a Lulu MCP server (42 tools) registered in `~/.claude/settings.json`. For ANY non-coding query, use the native MCP tools (`mcp__whissle__*`) directly:

- **Weather**: `mcp__whissle__get_weather`
- **Stocks**: `mcp__whissle__get_stock_price`
- **Crypto**: `mcp__whissle__get_crypto_price`
- **Calendar**: `mcp__whissle__check_calendar`
- **Email**: `mcp__whissle__check_email`, `mcp__whissle__send_email`
- **News**: `mcp__whissle__fetch_news`
- **Research**: `mcp__whissle__deep_research`
- **Memory**: `mcp__whissle__search_memories`, `mcp__whissle__store_memory`
- **Tasks**: `mcp__whissle__list_tasks`, `mcp__whissle__create_task`
- **Web search**: `mcp__whissle__web_search`
- **General**: `mcp__whissle__ask_agent` (routes automatically)

### What NOT to do

- Do NOT run `claude mcp call` — that CLI command does not exist
- Do NOT write Python/httpx scripts in Bash to call the API manually
- Do NOT use the built-in `WebSearch` tool when a Lulu tool covers the query
- If MCP tools are not available, tell the user to restart the session

## Project Structure

- `server.py` — MCP server (FastMCP, stdio transport, 42 tools)
- `hooks/` — Claude Code hooks (UserPromptSubmit, SessionStart)
- `hooks/shared.py` — mode detection, emotion/intent extraction, user ID resolution
- `claude-voice/` — PTY wrapper adding voice dictation (Alt+V) to Claude Code
- `setup.sh` — one-command setup for MCP server + hooks + voice

## Development

```bash
# Test MCP server
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | ./venv/bin/python server.py

# Run setup
./setup.sh --claude-code
```
