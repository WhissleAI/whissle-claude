#compdef claude-voice
# zsh completion for claude-voice

_claude-voice() {
  local -a opts
  opts=(
    '--token[Whissle API token]:token:'
    '--asr-url[Custom ASR server URL]:url:'
    '--language[ASR language code]:language:'
    '--speakers[Comma-separated speaker names]:speakers:'
  )
  _arguments -s $opts '*:claude args:_claude'
}

_claude-voice "$@"
