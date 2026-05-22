# Common zsh utilities shared by reply.zsh, dialog.zsh, and models.zsh.
# Source with: source "${lib_dir}/common.zsh"

# Fisher-Yates shuffle over positional arguments; prints each element on its own line.
shuffle_array() {
  local n=$#
  local arr=("$@")
  if (( n <= 1 )); then
    print -l -- "${arr[@]}"
    return 0
  fi
  for i in {$((n - 1))..1}; do
    local j=$((RANDOM % i + 1))
    local tmp="${arr[$i]}"
    arr[$i]="${arr[$j]}"
    arr[$j]="$tmp"
  done
  print -l -- "${arr[@]}"
}

# ~/foo -> $HOME/foo (zsh tilde expansion does not happen inside quoted vars).
expand_path() {
  local p="$1"
  print -r -- "${p/#\~\//${HOME}/}"
}

# PopClip-launched scripts do not always inherit proxy environment variables.
# Teach curl about the active macOS system proxy when no curl proxy env is set.
macos_curl_proxy_args() {
  if [[ -n "${HTTPS_PROXY:-}${https_proxy:-}${ALL_PROXY:-}${all_proxy:-}" ]]; then
    return 0
  fi

  local proxy_info https_enabled https_host https_port
  proxy_info="$(scutil --proxy 2>/dev/null)" || return 0
  https_enabled="$(print -r -- "${proxy_info}" | awk '$1 == "HTTPSEnable" { print $3; exit }')"
  if [[ "${https_enabled}" != "1" ]]; then
    return 0
  fi

  https_host="$(print -r -- "${proxy_info}" | awk '$1 == "HTTPSProxy" { print $3; exit }')"
  https_port="$(print -r -- "${proxy_info}" | awk '$1 == "HTTPSPort" { print $3; exit }')"
  if [[ -n "${https_host}" && -n "${https_port}" ]]; then
    print -r -- "--proxy"
    print -r -- "http://${https_host}:${https_port}"
  fi
}
