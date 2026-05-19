#!/bin/zsh
# Pick Model — fetches the model list from the configured endpoint, lets the
# user pick one, and saves the choice to ~/.config/popclip-aireply/selected_model.
# reply.zsh reads that file first, so the picked model wins over the PopClip
# settings field. Use "Reset" in the dialog to clear it and fall back to settings.

set -u

api_key="${POPCLIP_OPTION_API_KEY:-}"
api_key_file_raw="${POPCLIP_OPTION_API_KEY_FILE:-}"
endpoint="${POPCLIP_OPTION_ENDPOINT:-}"
api_key_pool_file_raw="${POPCLIP_OPTION_API_KEY_POOL_FILE:-}"
api_key_pool="${POPCLIP_OPTION_API_KEY_POOL:-}"
settings_model="${POPCLIP_OPTION_MODEL:-}"

script_dir="${0:A:h}"
lib_dir="${script_dir}/lib"
debug_dir="${HOME}/Library/Logs/AIReplyPopClip"
config_dir="${HOME}/.config/popclip-aireply"
selected_model_file="${config_dir}/selected_model"
mkdir -p "${debug_dir}" "${config_dir}" 2>/dev/null || true

expand_path() {
  local p="$1"
  print -r -- "${p/#\~\//${HOME}/}"
}

# AppleScript-safe dialog showing a UTF-8 string from a tmp file.
dialog_from_file() {
  local title="$1"
  local file="$2"
  local icon_kw="${3:-}"   # "" | "caution"
  AI_REPLY_TITLE="${title}" \
  AI_REPLY_FILE="${file}" \
  AI_REPLY_ICON_KW="${icon_kw}" \
  osascript <<'APPLESCRIPT' 2>/dev/null || true
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv

set t to my getenv("AI_REPLY_TITLE")
set f to my getenv("AI_REPLY_FILE")
set ico to my getenv("AI_REPLY_ICON_KW")
set m to read POSIX file f as «class utf8»

if ico is "caution" then
  display dialog m buttons {"Close"} default button "Close" with title t with icon caution
else
  display dialog m buttons {"OK"} default button "OK" with title t
end if
APPLESCRIPT
}

show_error() {
  local msg="$1"
  if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
    print -r -- "${msg}"
    exit 0
  fi
  local tmp
  tmp="$(mktemp -t aireply.pickerr.XXXXXX)"
  print -rn -- "${msg}" > "${tmp}"
  dialog_from_file "AI Reply — Pick Model" "${tmp}" "caution"
  rm -f "${tmp}" 2>/dev/null
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

# Current selection: prefer the picker file (what reply.zsh actually uses),
# fall back to the settings field for the "default selected row" in the list.
current_model=""
if [[ -s "${selected_model_file}" ]]; then
  current_model="$(awk 'NF { print; exit }' "${selected_model_file}" 2>/dev/null)"
fi
[[ -z "${current_model}" ]] && current_model="${settings_model}"

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

set picked to choose from list modelList with title "AI Reply — Pick Model" with prompt "选择一个模型作为默认。下次回复会立即使用此选择：" default items defaultItems OK button name "使用" cancel button name "取消"
if picked is false then
  return ""
end if

set chosen to item 1 of picked
return chosen
APPLESCRIPT
)"

if [[ -z "${choice//[[:space:]]/}" ]]; then
  exit 0
fi

# Persist the selection (one model name per file, first line wins).
print -r -- "${choice}" > "${selected_model_file}"

# Also copy to clipboard for convenience.
print -r -- "${choice}" | pbcopy 2>/dev/null || true

# Confirmation dialog — explain precedence so the user understands why their
# settings field value (if any) is being overridden.
msg_tmp="$(mktemp -t aireply.pickok.XXXXXX)"
{
  print -r -- "✅ 已选择：${choice}"
  print -r -- ""
  print -r -- "下次 AI Reply 会立即使用该模型。"
  print -r -- "选择已写入 ${selected_model_file}"
  print -r -- "（同时也复制到了剪贴板）"
  if [[ -n "${settings_model}" && "${settings_model}" != "${choice}" ]]; then
    print -r -- ""
    print -r -- "ℹ️ PopClip 设置面板里的 Model 字段当前是 \"${settings_model}\"，但 Pick Model 的选择优先。要回到设置面板的值，删除 ${selected_model_file} 即可。"
  fi
} > "${msg_tmp}"
dialog_from_file "AI Reply — Pick Model" "${msg_tmp}"
rm -f "${msg_tmp}" 2>/dev/null

print -r -- "${choice}"
