#!/bin/zsh
# Manage API Key Pool — lets non-technical users create/edit pool.json
# via a simple AppleScript dialog. Writes to ~/.config/popclip-aireply/pool.json
# with 600 permissions.

set -u

config_dir="${HOME}/.config/popclip-aireply"
pool_file="${config_dir}/pool.json"
script_dir="${0:A:h}"
lib_dir="${script_dir}/lib"
debug_dir="${HOME}/Library/Logs/AIReplyPopClip"

mkdir -p "${config_dir}" "${debug_dir}" 2>/dev/null || true

endpoint="${POPCLIP_OPTION_ENDPOINT:-https://ai.hybgzs.com/v1}"
endpoint="${endpoint%/}"

# ---------- helpers ----------

dialog_from_file() {
  local title="$1"
  local file="$2"
  local icon_kw="${3:-}"
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
  local tmp
  tmp="$(mktemp -t aireply.poolerr.XXXXXX)"
  print -rn -- "${msg}" > "${tmp}"
  dialog_from_file "AI Reply — Key Pool" "${tmp}" "caution"
  rm -f "${tmp}" 2>/dev/null
  exit 0
}

# ---------- show current pool ----------

current_info=""
if [[ -f "${pool_file}" ]]; then
  key_count="$(python3 - "${pool_file}" <<'PY' 2>/dev/null
import json, sys

with open(sys.argv[1], encoding='utf-8') as file:
    pool = json.load(file)
print(len([p for p in pool if p.get('api_key') and p.get('endpoint')]))
PY
)"
  if [[ -n "${key_count}" && "${key_count}" != "0" ]]; then
    current_info="当前已配置 ${key_count} 个 key。
"
  fi
fi

# ---------- prompt ----------

pg_tmp="$(mktemp -t aireply.poolpg.XXXXXX)"
{
  print -rn -- "${current_info}请输入 API Key，每行一个。
支持两种格式：

格式 1（推荐，指定 endpoint）：
  sk-xxx|https://your-endpoint.com/v1

格式 2（纯 key，使用默认 endpoint ${endpoint}）：
  sk-xxx

留空并点 OK 则只显示当前状态不变更。"
} > "${pg_tmp}"

res_tmp="$(mktemp -t aireply.poolres.XXXXXX)"
AI_REPLY_PG_FILE="${pg_tmp}" \
AI_REPLY_RES_FILE="${res_tmp}" \
osascript <<'APPLESCRIPT' 2>/dev/null
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv
set pgFile to my getenv("AI_REPLY_PG_FILE")
set resFile to my getenv("AI_REPLY_RES_FILE")
set promptText to read POSIX file pgFile as «class utf8»
set dlg to display dialog promptText default answer "" buttons {"取消", "保存"} default button "保存" with title "AI Reply — Key Pool"
if button returned of dlg is "取消" then
  error number -128
end if
set txt to text returned of dlg
set fh to open for access POSIX file resFile with write permission
set eof of fh to 0
write txt to fh as «class utf8»
close access fh
APPLESCRIPT
if [[ $? -ne 0 ]]; then
  rm -f "${pg_tmp}" "${res_tmp}" 2>/dev/null
  exit 0
fi

input_text="$(cat "${res_tmp}")"
rm -f "${pg_tmp}" "${res_tmp}" 2>/dev/null

# If user left input empty, just show current status and exit.
if [[ -z "${input_text//[[:space:]]/}" ]]; then
  if [[ -f "${pool_file}" ]]; then
    show_error "No changes made.
当前 pool 中有 ${key_count:-0} 个 key。"
  else
    show_error "还没有配置 Key Pool。
文件路径：${pool_file}"
  fi
  exit 0
fi

# ---------- parse input into pool JSON ----------

input_tmp="$(mktemp -t aireply.poolinput.XXXXXX)"
print -rn -- "${input_text}" > "${input_tmp}"
key_count="$(python3 "${lib_dir}/write_pool.py" \
  --input-file "${input_tmp}" \
  --default-endpoint "${endpoint}" \
  --output "${pool_file}" 2>/dev/null)" || {
  rm -f "${input_tmp}" 2>/dev/null
  show_error "Failed to parse input. Check the format and try again."
}
rm -f "${input_tmp}" 2>/dev/null

ok_tmp="$(mktemp -t aireply.poolok.XXXXXX)"
{
  print -rn -- "已保存 ${key_count} 个 key 到：${pool_file}

文件权限为 600（仅当前用户可读写）。

现在 AI Reply 会在这些 key 之间自动切换，
遇到 429/5xx 错误自动换下一个。"
} > "${ok_tmp}"
dialog_from_file "AI Reply — Key Pool" "${ok_tmp}"
rm -f "${ok_tmp}" 2>/dev/null
