#!/usr/bin/env zsh

# Better completion for ssh in Zsh.
# https://github.com/sunlei/zsh-ssh
# v0.0.7
# Copyright (c) 2020 Sunlei <guizaicn@gmail.com>

setopt no_beep # don't beep
zstyle ':completion:*:ssh:*' hosts off # disable built-in hosts completion

SSH_CONFIG_FILE="${SSH_CONFIG_FILE:-$HOME/.ssh/config}"
typeset -gi _zsh_ssh_parse_depth=0
typeset -gA _zsh_ssh_seen_config_files

# Parse the file and handle the include directive.
_parse_config_file() {
  # Include expansion uses the (N) glob qualifier, so enable its option locally.
  setopt localoptions bareglobqual
  unsetopt rematchpcre
  unsetopt nomatch

  local input_path="$1"
  local logical_config_path config_file_path include_base_dir
  local line raw_path expanded include_file_path
  local -a include_paths

  # Keep the caller-visible path for relative Includes so symlinked configs
  # resolve sibling includes from the link location, while realpath is used
  # below for reading and cycle detection.
  logical_config_path="$input_path"
  if [[ $logical_config_path == '~'* ]]; then
    logical_config_path="${logical_config_path/#\~/$HOME}"
  fi
  if [[ "$logical_config_path" != /* ]]; then
    logical_config_path="$PWD/$logical_config_path"
  fi
  include_base_dir="$(dirname "$logical_config_path")"

  # Resolve the full path of the input config file
  config_file_path=$(realpath "$logical_config_path" 2>/dev/null) || return 0

  # If previous parse was interrupted, reset stale global state.
  if (( _zsh_ssh_parse_depth <= 0 )); then
    _zsh_ssh_parse_depth=0
    unset _zsh_ssh_seen_config_files
    typeset -gA _zsh_ssh_seen_config_files
  fi

  (( _zsh_ssh_parse_depth++ ))
  {
    if [[ -n "${_zsh_ssh_seen_config_files[$config_file_path]}" ]]; then
      return 0
    fi
    _zsh_ssh_seen_config_files[$config_file_path]=1

    # Read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Match lines starting with 'Include'
      if [[ $line =~ ^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]=]+(.*) ]] && (( $#match > 0 )); then
        # Split the rest of the line into individual paths
        include_paths=(${(z)match[1]})

        for raw_path in "${include_paths[@]}"; do
          # Expand ~ and environment variables in the path
          expanded="${(e)raw_path}"

          # Expand a literal leading ~ before testing whether the path is relative.
          if [[ $expanded == '~'* ]]; then
            expanded="${expanded/#\~/$HOME}"
          fi

          # Relative Include paths follow the logical config directory, not the realpath target.
          if [[ "$expanded" != /* ]]; then
            expanded="$include_base_dir/$expanded"
          fi

          # Expand wildcards (e.g. *.conf) and loop over each matched file
          for include_file_path in ${~expanded}(N); do
            if [[ -f "$include_file_path" ]]; then
              # Separate includes with a blank line (for readability)
              echo ""
              # Recursively parse included files
              _parse_config_file "$include_file_path"
            fi
          done
        done
      else
        # Print normal (non-Include) lines
        echo "$line"
      fi
    done < "$config_file_path"
  } always {
    (( _zsh_ssh_parse_depth-- ))
    if (( _zsh_ssh_parse_depth <= 0 )); then
      _zsh_ssh_parse_depth=0
      unset _zsh_ssh_seen_config_files
      typeset -gA _zsh_ssh_seen_config_files
    fi
  }
}

_ssh_known_hosts() {
  local known_hosts_file="${ZSH_SSH_KNOWN_HOSTS_FILE:-$HOME/.ssh/known_hosts}"

  [[ -f "$known_hosts_file" ]] || return 0

  command awk '
    function emit_host(host) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", host)

      if (!host || host ~ /^\|1\|/ || host ~ /[*?!]/) {
        return
      }

      if (host ~ /^\[[^]]+\]:[0-9]+$/) {
        host = substr(host, 2, index(host, "]") - 2)
      }

      if (host) {
        print host
      }
    }

    /^[[:space:]]*$/ || /^[[:space:]]*#/ { next }
    $1 ~ /^@/ { next }

    {
      split($1, hosts, ",")
      for (i in hosts) {
        emit_host(hosts[i])
      }
    }
  ' "$known_hosts_file"
}

_ssh_known_hosts_list() {
  _ssh_known_hosts | command awk '{
    printf "%s|->|%s| | |[\033[00;34mknown_hosts\033[0m]\n", $0, $0
  }'
}

# Unstyled records shared by the standalone UI and native completion.
# Fields: alias | hostname | user | tag | description.
_ssh_config_records() {
  local ssh_config

  ssh_config=$(_parse_config_file "$SSH_CONFIG_FILE")
  ssh_config=$(printf "%s\n" "$ssh_config" | command grep -v -E "^\s*#[^_]")
  # Ensure blank line before each Host/Match block for AWK paragraph mode (RS="")
  ssh_config=$(printf "%s\n" "$ssh_config" | command awk '/^[[:space:]]*[Hh]ost[[:space:]]|^[[:space:]]*[Mm]atch[[:space:]]/{print ""} {print}')

  printf "%s\n" "$ssh_config" | command awk '
    function join(array, start, end, sep, result, i) {
      # https://www.gnu.org/software/gawk/manual/html_node/Join-Function.html
      if (sep == "")
        sep = " "
      else if (sep == SUBSEP) # magic value
        sep = ""
      result = array[start]
      for (i = start + 1; i <= end; i++)
        result = result sep array[i]
      return result
    }

    function parse_line(line) {
      gsub(/^[[:space:]]+/, "", line)
      n = split(line, line_array, /[[:space:]]*=[[:space:]]*|[[:space:]]+/)

      key = line_array[1]
      value = join(line_array, 2, n)

      return key "#-#" value
    }

    function starts_or_ends_with_star(str) {
        start_char = substr(str, 1, 1)
        end_char = substr(str, length(str), 1)

        return start_char == "*" || end_char == "*" || start_char == "!"
    }

    BEGIN {
      IGNORECASE = 1
      FS="\n"
      RS=""
    }
    {
      match_directive = ""

      user = ""
      host_name = ""
      alias = ""
      aliases = ""
      tag = ""
      desc = ""

      for (line_num = 1; line_num <= NF; ++line_num) {
        line = parse_line($line_num)

        split(line, tmp, "#-#")

        key = tolower(tmp[1])
        value = tmp[2]

        if (key == "match") { match_directive = value }

        if (key == "host") { aliases = value }
        if (key == "user") { user = value }
        if (key == "hostname") { host_name = value }
        if (key == "tag" && !tag) { tag = value }
        if (key == "#_desc") { desc = value }
      }

      n_aliases = split(aliases, alias_list, " ")
      for (i = 1; i <= n_aliases; i++) {
        alias = alias_list[i]
        effective_hostname = host_name ? host_name : alias

        if (!(effective_hostname && !starts_or_ends_with_star(effective_hostname)) || !(alias && !starts_or_ends_with_star(alias)) || match_directive) {
          continue
        }

        # Per-alias aggregation: each field uses first-non-empty wins
        # Extra rule: explicit HostName takes precedence over fallback value
        if (!(alias in alias_hn)) {
          alias_hn[alias] = effective_hostname
          alias_user[alias] = user
          alias_tag[alias] = tag
          alias_desc[alias] = desc
          if (host_name) alias_explicit_hn[alias] = 1
        } else {
          if (host_name && !alias_explicit_hn[alias]) {
            alias_hn[alias] = host_name
            alias_explicit_hn[alias] = 1
          }
          if (user && !alias_user[alias]) {
            alias_user[alias] = user
          }
          if (tag && !alias_tag[alias]) {
            alias_tag[alias] = tag
          }
          if (desc && !alias_desc[alias]) {
            alias_desc[alias] = desc
          }
        }
      }
    }
    END {
      for (a in alias_hn) {
        printf "%s|%s|%s|%s|%s\n", a, alias_hn[a], alias_user[a], alias_tag[a], alias_desc[a]
      }
    }
  '
}

_ssh_host_list() {
  local host_list tag_query

  host_list=$(_ssh_config_records | command awk -F '|' '
    {
      user = $3 ? $3 : " "
      tag = $4 ? sprintf("[\033[00;36m%s\033[0m]", $4) : " "
      desc = $5 ? sprintf("[\033[00;34m%s\033[0m]", $5) : " "
      printf "%s|->|%s|%s|%s|%s\n", $1, $2, user, tag, desc
    }
  ')

  if [[ "$ZSH_SSH_INCLUDE_KNOWN_HOSTS" == "1" ]]; then
    host_list="${host_list}"$'\n'"$(_ssh_known_hosts_list)"
  fi

  for arg in "$@"; do
    case $arg in
    -*) shift;;
    *) break;;
    esac
  done

  if [[ "$1" == tag:* ]]; then
    tag_query="${1#tag:}"
    host_list=$(command awk -F '|' -v q="$tag_query" '
      function plain_tag(value) {
        gsub(/\033\[[0-9;]*m/, "", value)
        gsub(/^\[|\]$/, "", value)
        return value
      }

      BEGIN { q = tolower(q) }
      NF >= 6 && (q == "" || index(tolower(plain_tag($5)), q) > 0)
    ' <<< "$host_list")
  elif [[ -n "$1" ]]; then
    host_list=$(command grep -i "$1" <<< "$host_list")
  fi
  host_list=$(printf "%s\n" "$host_list" | command sort -u)

  printf "%s\n" "$host_list"
}


_zsh_ssh_columnize() {
  if command -v column >/dev/null 2>&1; then
    command column -t -s '|'
    return
  fi

  command awk -F '|' '{
    for (i = 1; i <= NF; i++) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
    }

    output = $1
    for (i = 2; i <= NF; i++) {
      output = output "  " $i
    }
    print output
  }'
}

_fzf_list_generator() {
  local header host_list

  if [ -n "$1" ]; then
    host_list="$1"
  else
    host_list=$(_ssh_host_list)
  fi

  if printf "%s\n" "$host_list" | command awk -F '|' 'NF >= 6 && $5 !~ /^[[:space:]]*$/ { found = 1 } END { exit !found }'; then
    header="
Alias|->|Hostname|User|Tag|Desc
─────|──|────────|────|───|────
"
  else
    host_list=$(printf "%s\n" "$host_list" | command awk -F '|' '
      BEGIN { OFS = "|" }
      NF >= 6 { print $1, $2, $3, $4, $6; next }
      { print }
    ')
    header="
Alias|->|Hostname|User|Desc
─────|──|────────|────|────
"
  fi

  host_list="${header}"$'\n'"${host_list}"

  printf "%s\n" "$host_list" | _zsh_ssh_columnize
}

_set_lbuffer() {
  local result selected_host connect_cmd is_fzf_result
  result="$1"
  is_fzf_result="$2"

  if [ "$is_fzf_result" = false ] ; then
    result=$(cut -f 1 -d "|" <<< ${result})
  fi

  selected_host=$(cut -f 1 -d " " <<< ${result})
  connect_cmd="ssh ${selected_host}"

  LBUFFER="$connect_cmd"
}

_zsh_ssh_compsys_complete() {
  local query record alias hostname user tag desc description_format
  local -a config_hosts config_descriptions expl match_options
  local -Ua known_hosts
  local ret=1

  setopt localoptions noshwordsplit noksh_arrays

  # Preserve the login prefix when replacing only the destination hostname.
  compset -P '*@'
  query="$PREFIX$SUFFIX"
  match_options=(-M 'm:{a-zA-Z}={A-Za-z} r:|.=* r:|=*')

  # Only tag: is a source filter. Ordinary input is matched by compsys for
  # both groups, so grep cannot discard candidates before the matcher runs.
  while IFS='|' read -r alias hostname user tag desc; do
    [[ -n "$alias" ]] || continue
    if [[ "$query" == tag:* && "${(L)tag}" != *"${(L)${query#tag:}}"* ]]; then
      continue
    fi
    config_hosts+=("$alias")
    record="$alias -- ${user:+$user@}$hostname"
    [[ -n "$tag" ]] && record+=" [$tag]"
    [[ -n "$desc" ]] && record+=" $desc"
    config_descriptions+=("$record")
  done <<< "$(_ssh_config_records)"

  if [[ "$query" == tag:* ]]; then
    # Replace the whole tag query; fzf-tab should start with an empty search.
    PREFIX=''
    SUFFIX=''
    # -U ignores IPREFIX/ISUFFIX, so pass them explicitly for user@tag:...
    match_options=(-U -i "$IPREFIX" -I "$ISUFFIX")
  fi

  if (( ${#config_hosts} )); then
    _wanted zsh-ssh-config expl 'SSH Config' \
      compadd "${match_options[@]}" -d config_descriptions -- "${config_hosts[@]}" && ret=0
  fi

  # Without descriptions, fzf-tab cannot distinguish the host sources.
  # Respect the current completion context, including an explicit empty format.
  zstyle -s ":completion:${curcontext}:descriptions" format description_format
  if [[ "$query" != tag:* &&
        ( -n "$description_format" || "${ZSH_SSH_INCLUDE_KNOWN_HOSTS:-0}" == 1 ) ]]; then
    known_hosts=("${(@f)$(_ssh_known_hosts)}")
    known_hosts=("${(@)known_hosts:#}")

    if (( ${#known_hosts} )); then
      _wanted zsh-ssh-known-hosts expl 'Known Hosts' \
        compadd "${match_options[@]}" -- "${known_hosts[@]}" && ret=0
    fi
  fi

  return ret
}

# Locate the destination before handing option values and remote commands to
# _ssh. Handle attached values (-p2222) and short option clusters (-vp2222).
_zsh_ssh_at_destination() {
  local word option value
  local -i i j end_options=0

  for (( i = 2; i < CURRENT; ++i )); do
    word=${words[i]}
    (( end_options )) && return 1
    case "$word" in
      --) end_options=1 ;;
      -?*)
        for (( j = 2; j <= ${#word}; ++j )); do
          option=${word[j]}
          case "$option" in
            # These operations have no destination argument.
            Q|V) return 1 ;;
            B|b|c|D|E|e|F|I|i|J|L|l|m|O|o|P|p|R|S|W|w)
              if (( j == ${#word} )); then
                (( ++i < CURRENT )) || return 1
                value=${words[i]}
              else
                value=${word[j+1,-1]}
              fi
              # SSH_CONFIG_FILE is local to the calling completion function.
              if [[ $option == F ]]; then
                [[ $value == none ]] && SSH_CONFIG_FILE=/dev/null || SSH_CONFIG_FILE=${(Q)value}
              fi
              break
              ;;
            4|6|A|a|C|f|G|g|K|k|M|N|n|q|s|T|t|v|X|x|Y|y) ;;
            *) return 1 ;;
          esac
        done
        ;;
      *) return 1 ;;
    esac
  done

  (( end_options )) || [[ "${words[CURRENT]}" != -* ]]
}

# Produce candidates inside the completion widget wrapped by fzf-tab.
_zsh_ssh_complete() {
  setopt localoptions noshwordsplit noksh_arrays
  local SSH_CONFIG_FILE="$SSH_CONFIG_FILE"
  if _zsh_ssh_at_destination; then
    _zsh_ssh_compsys_complete
  else
    _ssh "$@"
  fi
}

fzf_complete_ssh() {
  local tokens cmd result key selection fuzzy_input
  setopt localoptions noshwordsplit noksh_arrays noposixbuiltins

  tokens=(${(z)LBUFFER})
  cmd=${tokens[1]}

  # This is only a safety fallback for shells where fzf-tab was enabled after
  # the first prompt. Normal fzf-tab integration goes through compdef and never
  # reaches this widget; nested completion widgets cannot be captured by
  # fzf-tab.
  if (( ${IN_FZF_TAB:-0} )) && [[ "$cmd" == "ssh" ]]; then
    zle ${fzf_ssh_default_completion:-expand-or-complete}
    return
  fi

  if [[ "$LBUFFER" =~ "^ *ssh$" ]]; then
    zle ${fzf_ssh_default_completion:-expand-or-complete}
  elif [[ "$cmd" == "ssh" ]]; then
    result=$(_ssh_host_list ${tokens[2, -1]})
    fuzzy_input="${LBUFFER#"$tokens[1] "}"
    if [[ "$fuzzy_input" == tag:* ]]; then
      fuzzy_input="${fuzzy_input#tag:}"
    fi

    if [ -z "$result" ]; then
      # When host parameters exist, don't fall back to default completion to avoid slow hosts enumeration
      if [[ -z "${tokens[2]}" || "${tokens[-1]}" == -* ]]; then
        zle ${fzf_ssh_default_completion:-expand-or-complete}
      fi
      return
    fi

    if [ $(echo $result | wc -l) -eq 1 ]; then
      _set_lbuffer $result false
      zle reset-prompt
      # zle redisplay
      return
    fi

    result=$(_fzf_list_generator $result | fzf \
      --height 40% \
      --ansi \
      --border \
      --cycle \
      --info=inline \
      --header-lines=2 \
      --reverse \
      --prompt='SSH Remote > ' \
      --query=$fuzzy_input \
      --bind 'shift-tab:up,tab:down,bspace:backward-delete-char/eof' \
      --preview 'ssh -T -G $(cut -f 1 -d " " <<< {}) | grep -i -E "^User |^HostName |^Port |^ControlMaster |^ForwardAgent |^LocalForward |^IdentityFile |^RemoteForward |^ProxyCommand |^ProxyJump " | (command -v column >/dev/null 2>&1 && column -t || cat)' \
      --preview-window=right:40% \
      --expect=alt-enter,enter
    )

    if [ -n "$result" ]; then
      key=${result%%$'\n'*}
      if [[ "$key" == "$result" ]]; then
        selection="$result"
        key=""
      else
        selection=${result#*$'\n'}
      fi

      if [ -n "$selection" ]; then
        _set_lbuffer "$selection" true
        if [[ "$key" == "alt-enter" ]]; then
          zle reset-prompt
        else
          zle accept-line
        fi
      fi
    fi

    # Only reset prompt if not already done for alt-enter
    if [[ "$key" != "alt-enter" ]]; then
      zle reset-prompt
      # zle redisplay
    fi

  # Fall back to default completion
  else
    zle ${fzf_ssh_default_completion:-expand-or-complete}
  fi
}


# Register the SSH source with compsys. This lets fzf-tab wrap an actual
# completion widget and capture both groups in its own dynamic context.
(( $+functions[compdef] )) && compdef _zsh_ssh_complete ssh

# Delay the standalone Tab binding until the first prompt. Plugin managers load
# entries sequentially, so this gives fzf-tab a chance to load either before or
# after zsh-ssh without ever wrapping zsh-ssh's user-defined widget.
_zsh_ssh_finalize_widgets() {
  add-zsh-hook -d precmd _zsh_ssh_finalize_widgets

  # compinit might have run after this plugin was sourced.
  (( $+functions[compdef] )) && compdef _zsh_ssh_complete ssh

  # When fzf-tab is installed, leave Tab under its control. With fzf-tab
  # disabled, the same compdef still provides ordinary grouped completion.
  (( $+functions[fzf-tab-complete] )) && return

  if [[ -z "$fzf_ssh_default_completion" ]]; then
    local binding
    binding=$(bindkey '^I')
    [[ $binding =~ 'undefined-key' ]] || fzf_ssh_default_completion=$binding[(s: :w)2]
  fi

  zle -N fzf_complete_ssh
  bindkey '^I' fzf_complete_ssh
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_ssh_finalize_widgets

# vim: set ft=zsh sw=2 ts=2 et
