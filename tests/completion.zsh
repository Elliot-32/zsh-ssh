#!/usr/bin/env zsh
# Run: zsh -f tests/completion.zsh
# Optional: FZF_TAB_DIR=/path/to/fzf-tab zsh -f tests/completion.zsh
emulate -R zsh
setopt pipefail
zmodload zsh/zpty || exit 1
zmodload zsh/zselect || exit 1
zmodload zsh/system || exit 1
local test_parent_pid=$sysparams[pid]

export TEST_ROOT=${0:A:h:h}
export TEST_LOG TEST_BINDING TEST_MODE
[[ -n $FZF_TAB_DIR ]] && export FZF_TAB_DIR=${FZF_TAB_DIR:A}
local test_tmp_root=${${TMPDIR:-/tmp}:A}
local test_tmp=$(mktemp -d "$test_tmp_root/zsh-ssh.XXXXXXXXXX") || exit 1
[[ -d $test_tmp && ${test_tmp:A:h} == $test_tmp_root ]] || exit 1
TEST_LOG=$test_tmp/result
TEST_BINDING=$test_tmp/binding
cleanup() {
  # zpty's fork can inherit EXIT traps; only the runner owns this directory.
  [[ $sysparams[pid] == $test_parent_pid ]] || return
  zpty -d 2>/dev/null
  [[ -d $test_tmp && ${test_tmp:A:h} == $test_tmp_root ]] && rm -rf -- "$test_tmp"
}
trap cleanup EXIT
local -i passed=0 failed=0
local transcript result

check() {
  local label=$1 actual=$2 expected=$3
  if [[ $actual == *"$expected"* ]]; then
    (( ++passed ))
  else
    print -ru2 -- "FAIL [$TEST_MODE] $label: expected ${(qqq)expected}, got ${(qqq)actual}"
    (( ++failed ))
  fi
}
reject() {
  local label=$1 actual=$2 unwanted=$3
  if [[ $actual != *"$unwanted"* ]]; then
    (( ++passed ))
  else
    print -ru2 -- "FAIL [$TEST_MODE] $label: unexpected ${(qqq)unwanted}"
    (( ++failed ))
  fi
}
wait_for() {
  local marker=$1 chunk
  local -i attempts=0
  transcript=''
  while (( ++attempts < 2000 )); do
    while zpty -r -t ssh_test chunk; do
      transcript+=$chunk
    done
    [[ $transcript == *"$marker"* ]] && return 0
    zselect -t 1
  done
  print -ru2 -- "Timed out [$TEST_MODE]: ${(V)transcript}"
  exit 1
}
complete() {
  : > "$TEST_LOG" || exit 1
  zpty -w -n ssh_test "$1"$'\t\C-X'
  wait_for __SSH_DONE__
  result=$(<"$TEST_LOG")
}

# The parser and old UI keep their existing record layout and styling.
source "$TEST_ROOT/zsh-ssh.zsh"
SSH_CONFIG_FILE="$TEST_ROOT/tests/ssh_config"
ZSH_SSH_KNOWN_HOSTS_FILE="$TEST_ROOT/tests/known_hosts"
check 'include records' "$(_ssh_config_records)" 'included|included.example||work|'
check 'merge repeated aliases' "$(_ssh_config_records)" 'inherited|inherited.example|admin|work|From first block'
reject 'plain records' "$(_ssh_config_records)" $'\e'
check 'standalone columns' "$(_ssh_host_list tag:work)" $'prod.web|->|192.0.2.10|deploy|[\e[00;36mwork'
reject 'standalone tag filter' "$(_ssh_host_list tag:work)" 'home|'

local -a modes=(native compinit-after)
if [[ -f $FZF_TAB_DIR/fzf-tab.zsh ]]; then
  modes+=(fzf-first plugin-first disabled reenabled)
else
  print 'SKIP fzf-tab integration: set FZF_TAB_DIR to a checkout'
fi
(( $# )) && modes=("$@")

for TEST_MODE in $modes; do
  zpty -b ssh_test zsh -f
  zpty -w ssh_test "source ${(q)TEST_ROOT}/tests/completion-child.zsh"
  wait_for __SSH_INITIALIZED__
  if [[ $TEST_MODE == native || $TEST_MODE == compinit-after ]]; then
    check 'standalone Tab binding' "$(<"$TEST_BINDING")" fzf_complete_ssh
  elif [[ $TEST_MODE != disabled ]]; then
    check 'fzf-tab Tab binding' "$(<"$TEST_BINDING")" fzf-tab-complete
  fi

  complete 'ssh p.w'
  check 'matcher config' "$result" 'CANDIDATE|prod.web|prod.web -- deploy@192.0.2.10 [work] Production web'
  check 'matcher known hosts' "$result" 'CANDIDATE|prod.web||'
  check 'config group' "$result" 'SSH Config'
  check 'known hosts group' "$result" 'Known Hosts'

  for input in 'ssh root@p.w' 'ssh -p 2222 root@p.w' 'ssh -vp2222 root@p.w' 'ssh -l deploy root@p.w' 'ssh -- root@p.w'; do
    complete "$input"
    check 'preserve login and options' "$result" "BUFFER|${input%p.w}prod.web"
  done

  complete 'ssh tag:WORK'
  check 'tag match' "$result" 'CANDIDATE|backup|'
  check 'included tag match' "$result" 'CANDIDATE|included|'
  reject 'exclude other tags' "$result" 'CANDIDATE|home|'
  reject 'exclude known hosts for tags' "$result" 'Known Hosts'
  reject 'tag is replaced' "$result" 'BUFFER|ssh tag:'
  complete 'ssh root@tag:personal'
  check 'tag login insertion' "$result" 'BUFFER|ssh root@home'
  complete $'ssh root@tag:personal\C-B\C-B\C-B'
  check 'tag query with cursor inside word' "$result" 'BUFFER|ssh root@home'
  complete 'ssh tag:missing'
  check 'unmatched tag stays unchanged' "$result" 'BUFFER|ssh tag:missing'

  for input in "ssh -F $TEST_ROOT/tests/alternate_config alt" "ssh -F$TEST_ROOT/tests/alternate_config alt"; do
    complete "$input"
    check 'alternate config' "$result" "BUFFER|${input%alt}alternate"
  done
  complete 'ssh -F none '
  reject 'disable config with -F none' "$result" 'SSH Config'

  # Real native option completion must remain available.
  complete 'ssh -o StrictHostKeyChecking=ye'
  check 'native option completion' "$result" 'BUFFER|ssh -o StrictHostKeyChecking=yes'
  for input in 'ssh -p ' 'ssh -i ' 'ssh -o ' 'ssh -J ' 'ssh -Q ' 'ssh prod.web echo '; do
    complete "$input"
    reject 'do not complete destination in other arguments' "$result" 'CANDIDATE|'
  done

  complete 'ssh '
  if [[ $TEST_MODE == fzf-first || $TEST_MODE == plugin-first || $TEST_MODE == reenabled ]]; then
    check 'uses real fzf-tab pipeline' "$result" 'SELECTOR|fzf-tab'
  fi
  check 'known hostname' "$result" 'CANDIDATE|known.example|'
  check 'port normalization' "$result" 'CANDIDATE|port.example|'
  reject 'hashed host' "$result" 'CANDIDATE||1|'
  reject 'revoked host' "$result" 'CANDIDATE|revoked.example|'
  reject 'wildcard host' "$result" 'CANDIDATE|*.wildcard.example|'
  local -a known_matches=("${(@M)${(@f)result}:#CANDIDATE\|prod.web\|\|*}")
  check 'unique known hosts' "$#known_matches" 1

  zpty -w ssh_test 'ZSH_SSH_INCLUDE_KNOWN_HOSTS=0; print __SSH_SETTING__'
  wait_for __SSH_SETTING__
  complete 'ssh '
  reject 'known hosts disabled' "$result" 'Known Hosts'
  zpty -d ssh_test
  print -- "PASS $TEST_MODE"
done

print -- "$passed checks passed; $failed failed"
(( failed == 0 ))
