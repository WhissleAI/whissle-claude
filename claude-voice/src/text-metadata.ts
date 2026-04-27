/**
 * Text-based intent/emotion classification — TypeScript port of
 * live_assist_python_server/app/metadata/extractor.py heuristics.
 *
 * Provides the same metadata shape for typed input as the ASR engine
 * provides for voice input, enabling unified context tracking.
 */

export interface InputMetadata {
  source: "voice" | "text"
  emotionProfile: Record<string, number>
  intentProfile: Record<string, number>
  dominantEmotion: string
  dominantIntent: string
}

// Intent patterns — same as Python's _INTENT_PATTERNS
const INTENT_PATTERNS: Array<[RegExp, string]> = [
  [/\b(what|how|why|when|where|who|which|explain|tell me)\b/i, "QUERY"],
  [/\b(i (?:think|feel|prefer|like|love|hate|want)|my |i'm )\b/i, "INFORM"],
  [/\b(do|open|close|send|create|add|delete|run|start|stop|fix|change|update|remove|make|install|deploy|build|test|implement|migrate|refactor|push|merge|revert)\b/i, "COMMAND"],
  [/\b(play|find|search|look up)\b/i, "QUERY"],
  [/\b(please|could you|can you|would you)\b/i, "REQUEST"],
]

// Emotion keywords — same as Python's _EMOTION_KEYWORDS
const EMOTION_KEYWORDS: Record<string, string> = {
  frustrated: "ANGRY",
  angry: "ANGRY",
  mad: "ANGRY",
  annoyed: "ANGRY",
  stressed: "ANGRY",
  furious: "ANGRY",
  happy: "HAPPY",
  excited: "HAPPY",
  love: "HAPPY",
  great: "HAPPY",
  awesome: "HAPPY",
  amazing: "HAPPY",
  perfect: "HAPPY",
  sad: "SAD",
  depressed: "SAD",
  tired: "SAD",
  lonely: "SAD",
  disappointed: "SAD",
  scared: "FEARFUL",
  afraid: "FEARFUL",
  worried: "FEARFUL",
  anxious: "FEARFUL",
  nervous: "FEARFUL",
  disgusted: "DISGUSTED",
  gross: "DISGUSTED",
  surprised: "SURPRISED",
  wow: "SURPRISED",
  unexpected: "SURPRISED",
  curious: "NEUTRAL",
  confused: "NEUTRAL",
  neutral: "NEUTRAL",
}

function inferIntent(text: string): [string, Record<string, number>] {
  const lower = text.toLowerCase().trim()
  if (lower.endsWith("?")) {
    return ["QUERY", { QUERY: 0.8 }]
  }
  for (const [pattern, intent] of INTENT_PATTERNS) {
    if (pattern.test(lower)) {
      return [intent, { [intent]: 0.7 }]
    }
  }
  return ["INFORM", { INFORM: 0.5 }]
}

function inferEmotion(text: string): [string, Record<string, number>] {
  const lower = text.toLowerCase()
  for (const [keyword, emotion] of Object.entries(EMOTION_KEYWORDS)) {
    if (new RegExp(`\\b${keyword}\\b`).test(lower)) {
      return [emotion, { [emotion]: 0.6 }]
    }
  }
  return ["NEUTRAL", { NEUTRAL: 0.5 }]
}

/** Classify typed text input — returns unified metadata matching voice format. */
export function classifyTextInput(text: string): InputMetadata {
  const [dominantIntent, intentProfile] = inferIntent(text)
  const [dominantEmotion, emotionProfile] = inferEmotion(text)

  return {
    source: "text",
    emotionProfile,
    intentProfile,
    dominantEmotion,
    dominantIntent,
  }
}
