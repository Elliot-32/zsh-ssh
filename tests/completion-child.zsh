# Sourced inside the regression runner's pseudo-terminal.
emulate -R zsh
setopt no_beep
setopt completeinword
bindkey -e
KEYTIMEOUT=1
LISTMAX=100000
export TERM=xterm
PROMPT='__SSH_READY__'
RPROMPT=''
autoload -Uz compinit
if [[ $TEST_MODE != compinit-after ]]; then
  compinit -D -i
fi
export SSH_CONFIG_FILE="$TEST_ROOT/tests/ssh_config"
export ZSH_SSH_KNOWN_HOSTS_FILE="$TEST_ROOT/tests/known_hosts"
export ZSH_SSH_INCLUDE_KNOWN_HOSTS=1
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
zstyle ':completion:*' remote-access false

case $TEST_MODE in
  fzf-first|disabled|reenabled)
    source "$FZF_TAB_DIR/fzf-tab.zsh"
    source "$TEST_ROOT/zsh-ssh.zsh"
    ;;
  *)
    source "$TEST_ROOT/zsh-ssh.zsh"
    [[ $TEST_MODE == plugin-first ]] && source "$FZF_TAB_DIR/fzf-tab.zsh"
    ;;
esac
[[ $TEST_MODE == compinit-after ]] && compinit -D -i
_test_initialize() {
  add-zsh-hook -d precmd _test_initialize
  [[ $TEST_MODE == disabled ]] && disable-fzf-tab
  if [[ $TEST_MODE == reenabled ]]; then
    disable-fzf-tab
    enable-fzf-tab
  fi

  if (( $+functions[compadd] )); then
    functions -c compadd _test_original_compadd
  else
    _test_original_compadd() { builtin compadd "$@" }
  fi
  compadd() {
    if (( ${funcstack[(Ie)_zsh_ssh_compsys_complete]} )); then
      local -a hits test_descriptions
      local -a test_args=("$@")
      local -i desc_index=${test_args[(Ie)-d]}
      (( desc_index )) && test_descriptions=("${(@P)test_args[desc_index+1]}")
      builtin compadd -A hits -D test_descriptions "$@"
      local i
      for (( i=1; i <= $#hits; ++i )); do
        print -r -- "CANDIDATE|$hits[i]|$test_descriptions[i]|$IPREFIX|$PREFIX" >> "$TEST_LOG"
      done
      print -r -- "GROUP|${(j: :)expl}" >> "$TEST_LOG"
    fi
    _test_original_compadd "$@"
  }

  # Use fzf-tab's real capture and insertion path with deterministic selection.
  # No fzf binary, terminal interaction, or network connection is needed.
  -ftb-fzf() {
    local ignored
    while IFS= read -r ignored; do :; done
    print -r -- 'SELECTOR|fzf-tab' >> "$TEST_LOG"
    print -r -- "$_ftb_query"
    print -r -- ENTER
    print -r -- "$_ftb_complist[1]"
  }

  _test_report() {
    print -r -- "BUFFER|$BUFFER" >> "$TEST_LOG"
    BUFFER=''
    zle -I
    print -r -- __SSH_DONE__
    zle reset-prompt
  }
  zle -N _test_report
  bindkey '^X' _test_report

  # Without fzf-tab, exercise the native completion source directly and also
  # verify that the plugin installed its separate standalone Tab widget.
  if [[ $TEST_MODE == native || $TEST_MODE == compinit-after ]]; then
    print -r -- "BINDING|$(bindkey '^I')" > "$TEST_BINDING"
    bindkey '^I' expand-or-complete
  fi
  if [[ $TEST_MODE == fzf-first || $TEST_MODE == plugin-first || $TEST_MODE == reenabled ]]; then
    print -r -- "BINDING|$(bindkey '^I')" > "$TEST_BINDING"
  fi
  print -r -- __SSH_INITIALIZED__
}
add-zsh-hook precmd _test_initialize
