# bash completion for claude-voice

_claude_voice() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "--token --asr-url --language --speakers" -- "$cur"))
  fi
}

complete -F _claude_voice claude-voice
