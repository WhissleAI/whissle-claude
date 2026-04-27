"""Shared config and utilities for Lulu hooks."""

import os
import json
import re
import subprocess
import sys
from typing import Dict, Tuple

AGENT_URL = os.getenv(
    "WHISSLE_AGENT_URL",
    "https://api.whissle.ai/agent",
).rstrip("/")

BACKEND_URL = os.getenv(
    "WHISSLE_BACKEND_URL",
    "https://live-assist-backend-843574834406.europe-west1.run.app",
).rstrip("/")

API_TOKEN = os.getenv("WHISSLE_API_TOKEN", "").strip()
USER_ID = os.getenv("WHISSLE_USER_ID", "")
USER_NAME = os.getenv("WHISSLE_USER_NAME", "")

_resolved_user_id = None
_UID_CACHE_FILE = os.path.join(os.path.expanduser("~"), ".claude-voice", ".resolved_uid")


def auth_headers(user_id: str = "") -> dict:
    headers = {}
    if API_TOKEN and API_TOKEN.startswith("wh_"):
        headers["Authorization"] = f"Bearer {API_TOKEN}"
    uid = user_id or resolve_user_id()
    if uid:
        headers["X-Device-Id"] = uid
    return headers


def _read_cached_uid() -> str:
    try:
        with open(_UID_CACHE_FILE) as f:
            data = json.load(f)
        if data.get("token") == API_TOKEN and data.get("uid"):
            return data["uid"]
    except Exception:
        pass
    return ""


def _write_cached_uid(uid: str) -> None:
    try:
        os.makedirs(os.path.dirname(_UID_CACHE_FILE), exist_ok=True)
        with open(_UID_CACHE_FILE, "w") as f:
            json.dump({"token": API_TOKEN, "uid": uid}, f)
    except Exception:
        pass


def resolve_user_id() -> str:
    global _resolved_user_id
    if USER_ID:
        return USER_ID
    if _resolved_user_id:
        return _resolved_user_id
    if not API_TOKEN or not API_TOKEN.startswith("wh_"):
        return ""
    cached = _read_cached_uid()
    if cached:
        _resolved_user_id = cached
        return cached
    try:
        import urllib.request
        url = f"{BACKEND_URL}/api-tokens/validate?token={API_TOKEN}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            if data.get("valid") and data.get("deviceId"):
                _resolved_user_id = data["deviceId"]
                _write_cached_uid(_resolved_user_id)
                return _resolved_user_id
    except Exception:
        pass
    return ""


def read_hook_input() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


# --- Local regex-based metadata extraction (ported from extractor.py) ---

_INTENT_PATTERNS = [
    (r"\b(what|how|why|when|where|who|which|explain|tell me)\b", "QUERY"),
    (r"\b(i (?:think|feel|prefer|like|love|hate|want)|my |i'm )\b", "INFORM"),
    (r"\b(do|open|close|send|create|add|delete|run|start|stop|fix|change|update|remove|make|install|deploy|build|test|implement|migrate|refactor|push|merge|revert)\b", "COMMAND"),
    (r"\b(play|find|search|look up)\b", "QUERY"),
    (r"\b(please|could you|can you|would you)\b", "REQUEST"),
]

_EMOTION_KEYWORDS = {
    "frustrated": "ANGRY", "angry": "ANGRY", "mad": "ANGRY",
    "annoyed": "ANGRY", "stressed": "ANGRY", "furious": "ANGRY",
    "happy": "HAPPY", "excited": "HAPPY", "love": "HAPPY",
    "great": "HAPPY", "awesome": "HAPPY", "amazing": "HAPPY",
    "perfect": "HAPPY",
    "sad": "SAD", "depressed": "SAD",
    "tired": "SAD", "lonely": "SAD", "disappointed": "SAD",
    "scared": "FEARFUL", "afraid": "FEARFUL", "worried": "FEARFUL",
    "anxious": "FEARFUL", "nervous": "FEARFUL",
    "disgusted": "DISGUSTED", "gross": "DISGUSTED",
    "surprised": "SURPRISED", "wow": "SURPRISED", "unexpected": "SURPRISED",
    "curious": "NEUTRAL", "confused": "NEUTRAL",
}


def infer_emotion(text: str) -> Tuple[str, float]:
    lower = text.lower()
    for kw, emotion in _EMOTION_KEYWORDS.items():
        if re.search(rf"\b{re.escape(kw)}\b", lower):
            return emotion, 0.6
    return "NEUTRAL", 0.5


def infer_intent(text: str) -> Tuple[str, float]:
    lower = text.lower().strip()
    if lower.endswith("?"):
        return "QUERY", 0.8
    for pattern, intent in _INTENT_PATTERNS:
        if re.search(pattern, lower):
            return intent, 0.7
    return "INFORM", 0.5


def extract_text_signal(text: str) -> str:
    emotion, emo_conf = infer_emotion(text)
    intent, int_conf = infer_intent(text)
    return f"emotion={emotion} ({emo_conf:.0%}), intent={intent} ({int_conf:.0%})"


# --- Mode detection (ported from live_assist_python_server/app/modes/) ---

_MODE_PATTERNS = [
    # Finance — check before generic search
    (r"\b(stock|share price|ticker|nasdaq|s&p|dow|nyse|market cap|stock price)\b", "finance_stock"),
    (r"\b(bitcoin|ethereum|crypto|btc|eth|solana|dogecoin|coin price|cryptocurrency)\b", "finance_crypto"),
    (r"\b(convert|exchange rate)\b.*\b(currency|usd|eur|gbp|jpy|inr|dollar|euro|pound|yen|rupee)\b", "finance_currency"),

    # Weather
    (r"\b(weather|temperature|forecast|rain|snow|sunny|cloudy|humidity|degrees)\b", "weather"),

    # Email — send before calendar (avoid "meeting" in "email about the meeting")
    (r"\b(send.*email|send.*mail|email to|write.*email|compose.*email|reply to.*email|send.*message to)\b", "email_send"),
    (r"\b(emails?|inbox|mail|gmail|check.*mail|unread|my mail)\b", "email"),

    # Calendar & reminders
    (r"\b(remind me|set.*reminder|alert me|don't forget)\b", "reminder"),
    (r"\b(schedule|calendar|meeting|appointment|event|agenda|my meetings|book a|set up a call)\b", "calendar"),

    # News & briefing
    (r"\b(briefing|morning brief|daily brief|daily summary)\b", "briefing"),
    (r"\b(news|headline|latest news|current events|what.s happening)\b", "news"),

    # Research
    (r"\b(deep research|research on|research about|deep dive|comprehensive analysis|investigate)\b", "research"),

    # Memory
    (r"\b(remember when|recall|you told me|we discussed|last time|previously|what did i)\b", "memory_search"),
    (r"\b(save this|store this|remember this|note this down)\b", "memory_store"),

    # Tasks
    (r"\b(my tasks|todo|to-do|task list|my checklist|show.*tasks)\b", "tasks"),
    (r"\b(add.*task|create.*task|new task|add to.*list)\b", "task_create"),

    # Contacts
    (r"\b(contact.*for|phone number for|email address for|look up.*contact)\b", "contacts"),

    # Navigation & places
    (r"\b(directions to|navigate to|route to|how to get to|how do i get to|drive to|walk to)\b", "navigation"),
    (r"\b(nearby|near me|find.*restaurant|find.*gas|find.*coffee|find.*hotel|closest)\b", "places"),

    # Translation
    (r"\b(translate|translation|in spanish|in french|in japanese|in hindi|in german|in chinese|in korean|in arabic|in portuguese|how do you say)\b", "translate"),

    # Calculation
    (r"\b(calculate|compute|what is \d|how much is \d|percentage of|convert \d)\b", "calculate"),

    # Media
    (r"\b(youtube|search.*video|find.*video|watch.*tutorial|how-to video)\b", "video"),
    (r"\b(generate.*image|draw me|draw a|create.*image|picture of|image of|illustrate)\b", "image_gen"),

    # Google services
    (r"\b(google drive|my drive|my documents|search.*drive|find.*files)\b", "drive"),
    (r"\b(save to sheet|write.*sheet|add.*sheet|log.*sheet)\b", "sheets_save"),
    (r"\b(google sheet|my sheet|read.*sheet|spreadsheet|show.*sheet)\b", "sheets_read"),

    # Code execution (Lulu sandbox)
    (r"\b(run this code|execute.*code|run python|run javascript)\b", "code_exec"),

    # Generic web search — lowest priority
    (r"\b(search for|search the web|look up online|current price of|what is the price)\b", "web_search"),
]

_MODE_TOOL_MAP = {
    "finance_stock": "get_stock_price",
    "finance_crypto": "get_crypto_price",
    "finance_currency": "convert_currency",
    "weather": "get_weather",
    "calendar": "check_calendar",
    "reminder": "set_reminder",
    "email": "check_email",
    "email_send": "send_email",
    "news": "fetch_news",
    "briefing": "daily_briefing",
    "research": "deep_research",
    "memory_search": "search_memories",
    "memory_store": "store_memory",
    "tasks": "list_tasks",
    "task_create": "create_task",
    "contacts": "search_contacts",
    "navigation": "get_directions",
    "places": "search_places",
    "translate": "translate_text",
    "calculate": "calculate",
    "video": "search_videos",
    "image_gen": "generate_image",
    "drive": "search_drive",
    "sheets_save": "save_to_sheet",
    "sheets_read": "read_from_sheet",
    "code_exec": "run_code",
    "web_search": "web_search",
}


def detect_mode(text: str) -> Tuple[str, str]:
    """Detect query mode and return (mode, mcp_tool_name) or ("", "")."""
    lower = text[:10000].lower().strip()
    for pattern, mode in _MODE_PATTERNS:
        if re.search(pattern, lower):
            tool = _MODE_TOOL_MAP.get(mode, "")
            return mode, tool
    return "", ""


def fire_async_profile_log(text: str, user_id: str):
    """Fire-and-forget API call to log text for behavioral profiling."""
    if not user_id or not text.strip():
        return
    headers = {"Content-Type": "application/json", **auth_headers(user_id)}
    script = f"""
import urllib.request, json
body = json.dumps({{"text": {json.dumps(text)}, "user_id": {json.dumps(user_id)}, "source": "claude_code_hook"}}).encode()
req = urllib.request.Request(
    {json.dumps(AGENT_URL + "/stream_meta")},
    data=body,
    headers={json.dumps(headers)},
)
try:
    urllib.request.urlopen(req, timeout=10)
except Exception:
    pass
"""
    subprocess.Popen(
        [sys.executable, "-c", script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
