#!/usr/bin/env zsh
# Test preview construction and execution without making SSH connections.
emulate -R zsh
setopt extendedglob
zmodload zsh/system || exit 1
local owner_pid=$sysparams[pid]
local root=${0:A:h:h}
local tmp_root=${${TMPDIR:-/tmp}:A}
local tmp=$(mktemp -d "$tmp_root/zsh-ssh-preview.XXXXXXXXXX") || exit 1
[[ -d $tmp && ${tmp:A:h} == $tmp_root ]] || exit 1
cleanup() {
  [[ $sysparams[pid] == $owner_pid ]] || return
  [[ -d $tmp && ${tmp:A:h} == $tmp_root ]] && rm -rf -- "$tmp"
}
trap cleanup EXIT
local -i passed=0 failed=0
check() {
  if [[ $2 == *"$3"* ]]; then
    (( ++passed ))
  else
    print -ru2 -- "FAIL $1: expected ${(qqq)3}, got ${(qqq)2}"
    (( ++failed ))
  fi
}
reject() {
  if [[ $2 != *"$3"* ]]; then
    (( ++passed ))
  else
    print -ru2 -- "FAIL $1: unexpected ${(qqq)3}"
    (( ++failed ))
  fi
}

mkdir "$tmp/bin"
export SSH_TEST_ARGS_FILE="$tmp/args"
print -r -- '#!/usr/bin/env zsh
print -rl -- "$@" > "$SSH_TEST_ARGS_FILE"
print -rl -- "user deploy" "hostname 192.0.2.10" "port 2222" \
  "controlmaster auto" "forwardagent yes" "localforward 8080 localhost:80" \
  "identityfile /keys/example key" "remoteforward 9090 localhost:90" \
  "proxycommand proxy --host example" "proxyjump bastion" "compression no"
' > "$tmp/bin/ssh"
chmod +x "$tmp/bin/ssh"
path=("$tmp/bin" $path)
SSH_CONFIG_FILE="$tmp/config with spaces"

zstyle ':fzf-tab:*' fzf-preview 'custom global preview'
zstyle ':fzf-tab:*' fzf-flags --height=60%
source "$root/zsh-ssh.zsh"
local preview
local -a flags reply words
local -A ctxt
local _ftb_curcontext=complete:ssh: CURRENT
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
check 'preserve existing global preview' "$preview" 'custom global preview'
zstyle -a ':fzf-tab:complete:ssh:' fzf-flags flags
check 'preserve existing flags' "$flags" '--height=60%'
zstyle ':fzf-tab:*' fzf-preview ''
source "$root/zsh-ssh.zsh"
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
check 'preserve disabled preview' "${#preview}" 0

zstyle -d ':fzf-tab:*' fzf-preview
zstyle -d ':fzf-tab:*' fzf-flags
source "$root/zsh-ssh.zsh"
words=(ssh -p 2222 -l deploy root@tag:work)
CURRENT=$#words
local word=prod.web
ctxt=(IPREFIX root@)
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
local output=$(eval "$preview")
local args=$(<"$SSH_TEST_ARGS_FILE")
check 'config path stays one argument' "$args" "$SSH_CONFIG_FILE"
check 'port option retained' "$args" $'-p\n2222'
check 'login option retained' "$args" $'-l\ndeploy'
check 'selected alias and login prefix' "$args" $'--\nroot@prod.web'
reject 'tag query is not used as destination' "$args" 'tag:work'
for field in user hostname port controlmaster forwardagent localforward identityfile remoteforward proxycommand proxyjump; do
  check "preview field $field" "$output" "$field "
done
reject 'exclude unrelated SSH settings' "$output" 'compression'

words=(ssh -F "$tmp/alternate config" candidate)
CURRENT=$#words
ctxt=(IPREFIX '')
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
eval "$preview" >/dev/null
args=$(<"$SSH_TEST_ARGS_FILE")
check 'alternate config retained' "$args" $'-F\n'"$tmp/alternate config"
words=(ssh -F none candidate)
CURRENT=$#words
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
eval "$preview" >/dev/null
args=$(<"$SSH_TEST_ARGS_FILE")
check 'no-config option retained' "$args" $'-F\nnone'

words=(ssh candidate)
CURRENT=$#words
word='host; print INJECTION'
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
output=$(eval "$preview")
args=$(<"$SSH_TEST_ARGS_FILE")
check 'selected word is quoted' "$args" $'--\nhost; print INJECTION'
reject 'selected word cannot inject shell syntax' "$output" INJECTION

for case in option command unrelated; do
  case $case in
    option) words=(ssh -p ''); _ftb_curcontext=complete:ssh: ;;
    command) words=(ssh server echo ''); _ftb_curcontext=complete:ssh: ;;
    unrelated) words=(cd ''); _ftb_curcontext=complete:cd: ;;
  esac
  CURRENT=$#words
  zstyle -s ":fzf-tab:$_ftb_curcontext" fzf-preview preview
  check "$case gets no SSH preview" "${#preview}" 0
done

words=(ssh candidate)
CURRENT=$#words
_ftb_curcontext=complete:ssh:
zstyle ':fzf-tab:complete:ssh:*' fzf-preview 'custom SSH preview'
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
check 'specific user preview overrides fallback' "$preview" 'custom SSH preview'
zstyle ':fzf-tab:*' fzf-preview 'later global preview'
zstyle -d ':fzf-tab:complete:ssh:*' fzf-preview
zstyle -s ':fzf-tab:complete:ssh:' fzf-preview preview
check 'later global preview overrides fallback' "$preview" 'later global preview'
print -- "$passed preview checks passed; $failed failed"
(( failed == 0 ))
