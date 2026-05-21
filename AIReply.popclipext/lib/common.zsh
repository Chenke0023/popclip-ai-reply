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
