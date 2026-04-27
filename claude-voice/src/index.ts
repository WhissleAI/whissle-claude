#!/usr/bin/env node
/**
 * claude-voice — PTY wrapper that adds voice dictation to Claude Code CLI.
 *
 * Spawns `claude` inside a pseudo-terminal, passes all I/O through
 * transparently, but intercepts Alt+V (ESC v) to toggle voice input
 * via Whissle ASR streaming.
 *
 * Voice + text metadata (emotion, intent, speech rate, speaker) is:
 * 1. Shown in the terminal title bar while recording
 * 2. Written to .claude-voice/context.md (readable by Claude via system prompt)
 * 3. Injected as context comments alongside transcribed text
 *
 * Usage:
 *   claude-voice --token wh_... [claude args...]
 *   WHISSLE_AUTH_TOKEN=wh_... claude-voice [claude args...]
 */

import * as pty from "node-pty"
import { MicCapture } from "./mic.js"
import { AsrStreamClient } from "./asr-client.js"
import { SessionContextStore } from "./metadata.js"
import which from "which"

// ── Parse claude-voice flags (strip before passing to claude) ─────
const argv = process.argv.slice(2)
const claudeArgs: string[] = []
let whissleToken = process.env.WHISSLE_AUTH_TOKEN ?? ""
let asrUrl = process.env.WHISSLE_ASR_URL
let asrLanguage = process.env.WHISSLE_ASR_LANGUAGE
let speakerLabels: string[] | undefined

for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--token" && i + 1 < argv.length) {
    whissleToken = argv[++i]
  } else if (argv[i] === "--asr-url" && i + 1 < argv.length) {
    asrUrl = argv[++i]
  } else if (argv[i] === "--language" && i + 1 < argv.length) {
    asrLanguage = argv[++i]
  } else if (argv[i] === "--speakers" && i + 1 < argv.length) {
    speakerLabels = argv[++i].split(",").map((s) => s.trim()).filter(Boolean)
  } else {
    claudeArgs.push(argv[i])
  }
}

if (!whissleToken) {
  console.error("Warning: No Whissle token. Use --token <token> or set WHISSLE_AUTH_TOKEN.")
  console.error("Voice dictation will not work without a valid token.\n")
}

// ── Resolve claude binary ──────────────────────────────────────────
const claudePath = await (async () => {
  try {
    return await which("claude")
  } catch {
    console.error("Error: 'claude' not found in PATH. Install Claude Code first.")
    process.exit(1)
  }
})()

// ── System prompt for voice context awareness ────────────────────
const voiceSystemPrompt = [
  `A voice-enabled session is active. Voice/text metadata (emotions, intents,`,
  `thinking patterns) is maintained in .claude-voice/context.md — read it before`,
  `responding to any planning, architecture, or multi-step task.`,
  `Inline annotations <!-- voice: ... --> after user text contain per-utterance metadata.`,
  ``,
  `CONVERSATIONAL PLANNING:`,
  `This is a voice-driven session — plans should emerge through dialogue, not monologue.`,
  `Read .claude-voice/context.md and follow the "Planning Recommendations" section to decide`,
  `whether to ask a clarifying question, present options, or proceed with execution.`,
  ``,
  `When to ASK (one focused question at a time, not a list):`,
  `- QUERY-heavy intents — user is still exploring, help narrow down`,
  `- Emotion signals confusion or frustration — clarify before building on shaky ground`,
  `- User is thinking aloud (INFORM-heavy) — they need help landing on a decision`,
  `- User shifted from directing to questioning — they're reconsidering, present alternatives`,
  `- The request is ambiguous or has multiple valid approaches — present 2-3 options briefly`,
  `- User mixed voice and text — voice may need refinement, confirm intent`,
  `- Multiple speakers show different intents — surface the disagreement`,
  ``,
  `When to PROCEED without asking:`,
  `- COMMAND-heavy intents — user knows what they want, just do it`,
  `- User shifted from exploring to commanding — they've decided, execute`,
  `- Urgency is high — act first, refine later`,
  `- The task is unambiguous with one obvious approach`,
  ``,
  `Keep questions short and specific — this is voice, not email. One question per response.`,
  `Reference what the user said ("You mentioned X — did you mean A or B?") to show you're`,
  `tracking the conversation, not asking generic questions. Build on prior context rather`,
  `than starting fresh each time.`,
].join("\n")

// ── PTY spawn ──────────────────────────────────────────────────────
const args = ["--append-system-prompt", voiceSystemPrompt, ...claudeArgs]
const cols = process.stdout.columns ?? 80
const rows = process.stdout.rows ?? 24

const child = pty.spawn(claudePath, args, {
  name: process.env.TERM ?? "xterm-256color",
  cols,
  rows,
  cwd: process.cwd(),
  env: process.env as Record<string, string>,
})

// Pipe PTY output → stdout
child.onData((data: string) => {
  process.stdout.write(data)
})

child.onExit(({ exitCode }) => {
  cleanup()
  process.exit(exitCode)
})

// Handle terminal resize
process.stdout.on("resize", () => {
  child.resize(process.stdout.columns, process.stdout.rows)
})

// ── Voice & context state ──────────────────────────────────────────
let recording = false
let mic: MicCapture | null = null
let asr: AsrStreamClient | null = null
const contextStore = new SessionContextStore(speakerLabels)

function writeStatus(msg: string) {
  process.stdout.write(`\x1b]0;${msg}\x07`)
}

async function startVoice() {
  if (recording) return
  recording = true
  writeStatus("🎙 Recording… (alt+v to stop)")

  mic = new MicCapture()
  asr = new AsrStreamClient({
    token: whissleToken,
    url: asrUrl,
    language: asrLanguage,
  })

  asr.onTranscript = (seg) => {
    // Ingest into multi-speaker context store
    const { speakerLabel } = contextStore.ingestVoice(seg)

    // Update terminal title with live speaker + metadata
    const meta = contextStore.shortSummary
    if (meta) writeStatus(`🎙 ${meta}`)

    if (seg.is_final && seg.text.trim()) {
      // Build the text to inject
      let textToInject = seg.text.trim()

      // Append inline voice context as an HTML comment that Claude can see
      const emotion = seg.metadata?.emotion
      const intent = seg.metadata?.intent
      if (emotion || intent || speakerLabel) {
        const parts: string[] = []
        if (speakerLabel) parts.push(`speaker:${speakerLabel}`)
        if (emotion) parts.push(`emotion:${emotion}`)
        if (intent) parts.push(`intent:${intent}`)
        textToInject += ` <!-- voice: ${parts.join(", ")} -->`
      }

      child.write(textToInject + " ")
    }
  }

  asr.onError = (err) => {
    process.stderr.write(`\r\nVoice error: ${err.message}\r\n`)
    stopVoice()
  }

  try {
    await asr.connect()
  } catch (err) {
    const msg = err instanceof Error ? err.message : "ASR connection failed"
    process.stderr.write(`\r\nVoice: ${msg}\r\n`)
    recording = false
    mic = null
    asr = null
    writeStatus("Claude Code")
    return
  }

  mic.onData = (pcm) => {
    asr?.sendPcm(pcm)
  }

  mic.onError = (err) => {
    process.stderr.write(`\r\nMic error: ${err.message}\r\n`)
    stopVoice()
  }

  try {
    await mic.start()
    process.stderr.write(`\r\n🎙 Voice recording started (alt+v to stop)\r\n`)
    process.stderr.write(`   Context: ${contextStore.filePath}\r\n`)
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Mic failed"
    process.stderr.write(`\r\nVoice: ${msg}\r\n`)
    recording = false
    mic = null
    try { asr?.close() } catch {}
    asr = null
    writeStatus("Claude Code")
  }
}

async function stopVoice() {
  if (!recording) return
  recording = false
  writeStatus("Claude Code")

  mic?.stop()
  mic = null

  try {
    await asr?.end()
  } catch {}
  asr = null

  const meta = contextStore.shortSummary
  process.stderr.write(`\r\n🎙 Voice stopped${meta ? ` (${meta})` : ""}\r\n`)
}

async function toggleVoice() {
  if (recording) {
    await stopVoice()
  } else {
    await startVoice()
  }
}

// ── Raw stdin handling ─────────────────────────────────────────────
if (process.stdin.isTTY) {
  process.stdin.setRawMode(true)
}
process.stdin.resume()
process.stdin.setEncoding("utf8")

let escPending = false
let escTimer: ReturnType<typeof setTimeout> | null = null
const ESC_WAIT = 50

// ── Text input buffer for metadata classification ─────────────────
let textBuffer = ""

process.stdin.on("data", (chunk: string) => {
  let i = 0
  while (i < chunk.length) {
    const ch = chunk[i]

    if (escPending) {
      if (escTimer) {
        clearTimeout(escTimer)
        escTimer = null
      }
      escPending = false

      if (ch === "v") {
        toggleVoice()
        i++
        continue
      } else {
        child.write("\x1b")
        continue
      }
    }

    if (ch === "\x1b") {
      if (i + 1 < chunk.length && chunk[i + 1] === "v") {
        toggleVoice()
        i += 2
        continue
      }

      if (i + 1 >= chunk.length) {
        escPending = true
        escTimer = setTimeout(() => {
          escPending = false
          escTimer = null
          child.write("\x1b")
        }, ESC_WAIT)
        i++
        continue
      }

      // Pass through escape sequence and skip buffering
      child.write(chunk.slice(i))
      return
    }

    // Buffer printable text for metadata classification
    if (ch === "\r" || ch === "\n") {
      // Enter — classify buffered text, ingest, then forward
      if (textBuffer.trim().length > 2) {
        contextStore.ingestText(textBuffer)
      }
      textBuffer = ""
    } else if (ch === "\x7f" || ch === "\b") {
      // Backspace — remove last char from buffer
      textBuffer = textBuffer.slice(0, -1)
    } else if (ch >= " " && ch <= "~") {
      // Printable ASCII — add to buffer
      textBuffer += ch
    } else if (ch === "\x03") {
      // Ctrl+C — clear buffer
      textBuffer = ""
    }

    child.write(ch)
    i++
  }
})

// ── Cleanup ────────────────────────────────────────────────────────
let cleanedUp = false
function cleanup() {
  if (cleanedUp) return
  cleanedUp = true
  if (process.stdin.isTTY) {
    try { process.stdin.setRawMode(false) } catch {}
  }
  mic?.stop()
  asr?.close()
  contextStore.flush()
}

process.on("SIGINT", () => {
  child.write("\x03")
})

process.on("SIGTERM", () => {
  cleanup()
  child.kill()
  process.exit(0)
})

process.on("exit", cleanup)
