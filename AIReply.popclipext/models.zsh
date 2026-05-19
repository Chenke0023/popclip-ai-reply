#!/bin/zsh
# Fetch the model list from the configured endpoint, let the user pick one,
# and copy the choice to the clipboard so it can be pasted into the Model field.

set -u

api_key="${POPCLIP_OPTION_API_KEY:-}"
api_key_file_raw="${POPCLIP_OPTION_API_KEY_FILE:-}"
endpoint="${POPCLIP_OPTION_ENDPOINT:-}"
api_key_pool_file_raw="${POPCLIP_OPTION_API_KEY_POOL_FILE:-}"
api_key_pool="${POPCLIP_OPTION_API_KEY_POOL:-}"

script_dir="${0:A:h}"
lib_dir="${script_dir}/lib"
debug_dir="${HOME}/Library/Logs/AIReplyPopClip"
mkdir -p "${debug_dir}" 2>/dev/null || true

expand_path() {
  local p="$1"
  print -r -- "${p/#\~\//${HOME}/}"
}

show_error() {
  local msg="$1"
  if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
    print -r -- "${msg}"
    exit 0
  fi
  AI_REPLY_ERR="${msg}" osascript <<'APPLESCRIPT' 2>/dev/null || true
set m to system attribute "AI_REPLY_ERR"
display dialog m buttons {"Close"} default button "Close" with title "AI Reply — Get Models" with icon caution
APPLESCRIPT
  exit 0
}

# If the inline pool or pool file is set, pick the first valid entry from it.
resolve_from_pool() {
  local pool_pairs=""
  if [[ -n "${api_key_pool_file_raw}" ]]; then
    pool_pairs="$(AI_REPLY_POOL_FILE="$(expand_path "${api_key_pool_file_raw}")" \
      python3 "${lib_dir}/load_pool.py" </dev/null 2>/dev/null)" || pool_pairs=""
  fi
  if [[ -z "${pool_pairs}" && -n "${api_key_pool//[[:space:]]/}" ]]; then
    pool_pairs="$(print -r -- "${api_key_pool}" | python3 "${lib_dir}/load_pool.py" 2>/dev/null)" || pool_pairs=""
  fi
  if [[ -n "${pool_pairs}" ]]; then
    local first="${pool_pairs%% *}"
    api_key="${first%%|*}"
    endpoint="${first#*|}"
  fi
}

resolve_from_pool

if [[ -z "${api_key}" ]]; then
  api_key="${AI_REPLY_API_KEY:-}"
fi
if [[ -z "${api_key}" && -z "${api_key_file_raw}" ]]; then
  api_key_file_raw="~/.config/popclip-aireply/api_key"
fi
if [[ -z "${api_key}" && -n "${api_key_file_raw}" ]]; then
  api_key_file_expanded="$(expand_path "${api_key_file_raw}")"
  if [[ -f "${api_key_file_expanded}" ]]; then
    api_key="$(awk 'NF { print; exit }' "${api_key_file_expanded}" 2>/dev/null)"
  fi
fi

[[ -z "${endpoint}" ]] && endpoint="https://ai.hybgzs.com/v1"
[[ -z "${api_key}" ]] && show_error "Missing API key. Set one in PopClip settings or save to ~/.config/popclip-aireply/api_key"

endpoint="${endpoint%/}"

body_file="${debug_dir}/last_models_body.txt"
rm -f "${body_file}" 2>/dev/null || true

http_status="$(curl -sS \
  --compressed \
  --connect-timeout 10 \
  --max-time 30 \
  -o "${body_file}" \
  -w "%{http_code}" \
  -H "Authorization: Bearer ${api_key}" \
  -H "Accept: application/json" \
  "${endpoint}/models" \
  2>"${debug_dir}/last_models_curl_stderr.txt")"
curl_exit=$?

if (( curl_exit != 0 )); then
  show_error "Network error fetching models (curl exit ${curl_exit}). See ${debug_dir}/last_models_curl_stderr.txt"
fi

if [[ "${http_status}" != "200" ]]; then
  body_snippet=""
  [[ -f "${body_file}" ]] && body_snippet="$(head -c 400 "${body_file}")"
  show_error "HTTP ${http_status} from ${endpoint}/models${body_snippet:+\n\n${body_snippet}}"
fi

models_out="$(python3 "${lib_dir}/fetch_models.py" "${body_file}" 2>"${debug_dir}/last_models_err.txt")"
if [[ $? -ne 0 || -z "${models_out//[[:space:]]/}" ]]; then
  show_error "Failed to parse models. $(cat "${debug_dir}/last_models_err.txt" 2>/dev/null)"
fi

if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
  print -r -- "${models_out}"
  exit 0
fi

current_model="${POPCLIP_OPTION_MODEL:-}"

# AppleScript "choose from list" — pick one, copy to clipboard.
choice="$(MODELS="${models_out}" CURRENT="${current_model}" osascript <<'APPLESCRIPT' 2>/dev/null
set raw to system attribute "MODELS"
set cur to system attribute "CURRENT"

set AppleScript's text item delimiters to linefeed
set modelList to text items of raw
set AppleScript's text item delimiters to ""

set defaultItems to {}
if cur is not "" and cur is in modelList then
  set defaultItems to {cur}
end if

set picked to choose from list modelList with title "AI Reply — Models" with prompt "选择一个模型（确定后会复制到剪贴板，去 PopClip 设置里粘贴到 Model 字段）：" default items defaultItems OK button name "复制" cancel button name "取消"
if picked is false then
  return ""
end if

set chosen to item 1 of picked
set the clipboard to chosen
return chosen
APPLESCRIPT
)"

if [[ -n "${choice//[[:space:]]/}" ]]; then
  AI_REPLY_MSG="已复制到剪贴板：

${choice}

打开 PopClip 设置 → AI Reply Enhanced，把 Model 字段替换为该值。" osascript <<'APPLESCRIPT' 2>/dev/null || true
set m to system attribute "AI_REPLY_MSG"
display dialog m buttons {"OK"} default button "OK" with title "AI Reply — Models"
APPLESCRIPT
fi

print -r -- "${choice}"
