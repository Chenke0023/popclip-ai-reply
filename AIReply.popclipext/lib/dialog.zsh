#!/bin/zsh
# Background dialog + follow-up handler for AI Reply.
# Reads session state from a JSON file written by reply.zsh.

set -u

session_file="${1:-}"
lib_dir="${0:A:h}"
debug_dir="${HOME}/Library/Logs/AIReplyPopClip"
mkdir -p "${debug_dir}" 2>/dev/null || true
dialog_log="${debug_dir}/last_dialog.log"

log_dialog() {
  print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${dialog_log}" 2>/dev/null || true
}

exec 2>>"${dialog_log}"

log_dialog "dialog.zsh starting; session=${session_file}"

if [[ -z "${session_file}" || ! -f "${session_file}" ]]; then
  log_dialog "missing session file"
  exit 1
fi

# Clean up session file on exit.
cleanup_session() {
  local rc=$?
  log_dialog "dialog.zsh exiting rc=${rc}"
  rm -f "${session_file}" 2>/dev/null || true
}
trap cleanup_session EXIT

# --------------------------- load session --------------------------------
# Parse the JSON session file once and emit shell variable assignments.
local session_vars
session_vars="$(python3 - "${session_file}" \
  current_reply input_from_stdin user_prompt runtime_prompt \
  system_prompt model temperature_raw auto_language reply_style \
  auto_copy show_language_badge save_history history_path \
  detected_language api_key endpoint api_key_pool \
  api_key_pool_file_raw mail_thread_json <<'PY'
import json
import shlex
import sys

with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)

for key in sys.argv[2:]:
    val = data.get(key, '')
    print(f"{key}={shlex.quote(str(val))}")
PY
)"

eval "${session_vars}"

log_dialog "session loaded; reply_chars=${#current_reply}; input_chars=${#input_from_stdin}; model=${model}; endpoint=${endpoint}"

: "${current_reply}" "${lib_dir}" "${debug_dir}" "${history_path}"

# ------------------------------- utils ----------------------------------

source "${lib_dir}/common.zsh"

# --------------------------- dialogs ------------------------------------

show_reply_dialog() {
  log_dialog "show_reply_dialog starting; reply_chars=${#1}"
  local style_label
  case "${reply_style}" in
    friendly) style_label="😊 Friendly" ;;
    concise)  style_label="📝 Concise" ;;
    *)        style_label="✨ Professional" ;;
  esac

  local meta="${style_label}"
  if [[ "${show_language_badge}" == "true" && -n "${detected_language}" ]]; then
    meta="🌐 ${detected_language} | ${style_label}"
  fi

  local reply_tmp meta_tmp out_tmp
  reply_tmp="$(mktemp -t aireply.reply.XXXXXX)"
  meta_tmp="$(mktemp -t aireply.meta.XXXXXX)"
  out_tmp="$(mktemp -t aireply.out.XXXXXX)"
  print -rn -- "$1" > "${reply_tmp}"
  print -rn -- "${meta}" > "${meta_tmp}"

  AI_REPLY_REPLY_FILE="${reply_tmp}" \
  AI_REPLY_META_FILE="${meta_tmp}" \
  AI_REPLY_OUT_FILE="${out_tmp}" \
  osascript <<'APPLESCRIPT'
set replyFile to system attribute "AI_REPLY_REPLY_FILE"
set metaFile to system attribute "AI_REPLY_META_FILE"
set outFile to system attribute "AI_REPLY_OUT_FILE"

set replyText to read POSIX file replyFile as «class utf8»
set metaText to read POSIX file metaFile as «class utf8»

set msg to metaText & "

生成的回复如下（可复制/可编辑）：

点 Follow Up 可以继续提要求并让 AI 重新改写。"
set dlg to display dialog msg default answer replyText buttons {"Follow Up", "Copy", "OK"} default button "OK" with title "AI Reply"
set btn to button returned of dlg
set txt to text returned of dlg
if btn is "Copy" then
  set the clipboard to txt
end if

set payload to btn & linefeed & txt
set fh to open for access POSIX file outFile with write permission
set eof of fh to 0
write payload to fh as «class utf8»
close access fh
APPLESCRIPT
  local rc=$?
  log_dialog "show_reply_dialog osascript rc=${rc}; out_size=$(wc -c < "${out_tmp}" 2>/dev/null || print 0)"
  if (( rc == 0 )) && [[ -s "${out_tmp}" ]]; then
    cat "${out_tmp}"
  fi
  rm -f "${reply_tmp}" "${meta_tmp}" "${out_tmp}" 2>/dev/null
  return ${rc}
}

prompt_follow_up() {
  log_dialog "prompt_follow_up starting"
  local out_tmp
  out_tmp="$(mktemp -t aireply.followup.XXXXXX)"

  AI_REPLY_OUT_FILE="${out_tmp}" \
  osascript <<'APPLESCRIPT'
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv

set outFile to my getenv("AI_REPLY_OUT_FILE")
set dlg to display dialog "输入追加要求（例如：更短、更礼貌、补充时间点…）。回复风格使用 Settings 里的 Default Style。" default answer "" buttons {"取消", "发送"} default button "发送" cancel button "取消" with title "AI Reply — Follow Up"
set txt to text returned of dlg

set fh to open for access POSIX file outFile with write permission
set eof of fh to 0
write txt to fh as «class utf8»
close access fh
APPLESCRIPT
  local rc=$?
  if (( rc != 0 )); then
    rm -f "${out_tmp}" 2>/dev/null
    return 1
  fi
  local res="$(cat "${out_tmp}")"
  rm -f "${out_tmp}" 2>/dev/null
  log_dialog "prompt_follow_up submitted; style=${reply_style}; chars=${#res}"
  print -r -- "${res}"
}

show_processing_notice() {
  log_dialog "show_processing_notice"
  osascript <<'APPLESCRIPT' >/dev/null 2>&1 || true
display notification "正在根据 Follow Up 改写，完成后会自动弹出结果。" with title "AI Reply" subtitle "Working…"
APPLESCRIPT
}

# --------------------------- error dialog -------------------------------

error_dialog() {
  local msg="$1"
  local msg_tmp
  msg_tmp="$(mktemp -t aireply.err.XXXXXX)"
  print -rn -- "${msg}" > "${msg_tmp}"

  AI_REPLY_MSG_FILE="${msg_tmp}" \
  osascript <<'APPLESCRIPT' || true
set msgFile to system attribute "AI_REPLY_MSG_FILE"
set userMsg to read POSIX file msgFile as «class utf8»
display dialog userMsg buttons {"OK"} default button "OK" with title "AI Reply Error"
APPLESCRIPT
  rm -f "${msg_tmp}" 2>/dev/null
}

# ------------------------------ API call --------------------------------

call_api() {
  local test_api_key="$1"
  local test_endpoint="$2"
  local draft="$3"
  local followup="$4"

  export AI_REPLY_INPUT_TEXT="${input_from_stdin}"
  export AI_REPLY_USER_PROMPT="${user_prompt}"
  export AI_REPLY_RUNTIME_PROMPT="${runtime_prompt}"
  export AI_REPLY_SYSTEM_PROMPT="${system_prompt}"
  export AI_REPLY_MODEL="${model}"
  export AI_REPLY_TEMPERATURE_RAW="${temperature_raw}"
  export AI_REPLY_AUTO_LANGUAGE="${auto_language}"
  export AI_REPLY_STYLE="${reply_style}"
  export AI_REPLY_DRAFT_REPLY="${draft}"
  export AI_REPLY_FOLLOWUP_PROMPT="${followup}"
  export AI_REPLY_MAIL_THREAD_JSON="${mail_thread_json}"

  local meta_file="${debug_dir}/last_meta.txt"
  local body_file="${debug_dir}/last_body.txt"
  local headers_file="${debug_dir}/last_headers.txt"
  local curl_stderr_file="${debug_dir}/last_curl_stderr.txt"
  local http_status_file="${debug_dir}/last_http_status.txt"
  local curl_exit_file="${debug_dir}/last_curl_exit.txt"

  local payload_json
  payload_json="$(python3 "${lib_dir}/build_payload.py" 2>"${meta_file}")"
  if [[ $? -ne 0 || -z "${payload_json}" ]]; then
    print -r -- "Failed to construct JSON payload."
    return 1
  fi

  local http_status curl_exit
  http_status="$(curl -sS \
    --compressed \
    --connect-timeout 10 \
    --max-time 90 \
    -D "${headers_file}" \
    -o "${body_file}" \
    -w "%{http_code}" \
    -X POST "${test_endpoint}/chat/completions" \
    -H "Authorization: Bearer ${test_api_key}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary "${payload_json}" \
    2>"${curl_stderr_file}")"
  curl_exit=$?
  print -r -- "${http_status}" > "${http_status_file}" 2>/dev/null || true
  print -r -- "${curl_exit}" > "${curl_exit_file}" 2>/dev/null || true

  if (( curl_exit != 0 )); then
    local curl_msg
    curl_msg="$(cat "${curl_stderr_file}" 2>/dev/null)"
    if [[ -n "${curl_msg}" ]]; then
      print -r -- "Network error: curl exit ${curl_exit}. ${curl_msg}"
    else
      print -r -- "Network error: curl exit ${curl_exit} (HTTP ${http_status:-000})."
    fi
    return 1
  fi
  if [[ ! -s "${body_file}" ]]; then
    print -r -- "Empty response body from server (HTTP ${http_status})."
    return 1
  fi

  local parsed rc
  parsed="$(python3 "${lib_dir}/parse_response.py" "${http_status}" "${body_file}")"
  rc=$?

  if (( rc == 0 )); then
    print -r -- "${parsed}"
    return 0
  fi

  case "${http_status}" in
    401|403|404|400|422)
      print -r -- "${parsed}"
      return 2
      ;;
    *)
      print -r -- "${parsed}"
      return 1
      ;;
  esac
}

generate_reply() {
  local draft="$1"
  local followup="$2"

  local pool_pairs=""
  if [[ -n "${api_key_pool_file_raw}" ]]; then
    pool_pairs="$(AI_REPLY_POOL_FILE="$(expand_path "${api_key_pool_file_raw}")" \
      python3 "${lib_dir}/load_pool.py" </dev/null 2>/dev/null)" || pool_pairs=""
  fi
  if [[ -z "${pool_pairs}" && -n "${api_key_pool//[[:space:]]/}" ]]; then
    pool_pairs="$(print -r -- "${api_key_pool}" | python3 "${lib_dir}/load_pool.py" 2>/dev/null)" || pool_pairs=""
  fi

  local tried_pairs=()
  if [[ -n "${pool_pairs}" ]]; then
    local pool_arr=("${(@s/ /)pool_pairs}")
    tried_pairs=($(shuffle_array "${pool_arr[@]}"))
  else
    tried_pairs=("${api_key}|${endpoint%/}")
  fi

  local last_error_msg=""
  local attempt=0
  for pair in "${tried_pairs[@]}"; do
    ((attempt++))
    local current_api_key="${pair%%|*}"
    local current_endpoint="${pair#*|}"

    # Skip keys in cooldown.
    if [[ -f "${debug_dir}/key_health.json" ]]; then
      if [[ "$(python3 "${lib_dir}/retry.py" is-healthy "${current_api_key:0:8}***" 2>/dev/null)" != "true" ]]; then
        last_error_msg="Key ${current_api_key:0:8}... is in cooldown (skipping)"
        continue
      fi
    fi

    local result
    result="$(call_api "${current_api_key}" "${current_endpoint}" "${draft}" "${followup}")"
    local call_status=$?

    case ${call_status} in
      0)
        print -r -- "${result}"
        return 0
        ;;
      2)
        print -r -- "${result}"
        return 2
        ;;
      *)
        # Rate-limit: mark unhealthy and honour Retry-After.
        if print -r -- "${result}" | grep -qi '429\|rate.limit\|too many'; then
          local retry_sec
          retry_sec="$(python3 "${lib_dir}/retry.py" parse-retry-after "${debug_dir}/last_headers.txt" 2>/dev/null)"
          [[ -z "${retry_sec}" || "${retry_sec}" == "0" ]] && retry_sec=5
          python3 "${lib_dir}/retry.py" mark-unhealthy \
            "${current_api_key:0:8}***" "rate_limited" "${retry_sec}" 2>/dev/null || true
          last_error_msg="${result} (key cooled for ${retry_sec}s)"
        else
          last_error_msg="${result}"
        fi
        # Exponential backoff on retry.
        if (( attempt > 1 )); then
          python3 -c "
import time; t = min(0.5 * 2**(${attempt}-2), 4.0)
time.sleep(t)
" 2>/dev/null || true
        fi
        continue
        ;;
    esac
  done

  print -r -- "${last_error_msg:-No valid API keys configured.}"
  return 1
}

# ------------------------------- main loop ------------------------------

while true; do
  local dlg_out="$(show_reply_dialog "${current_reply}")" || break

  local dlg_lines=("${(@f)dlg_out}")
  local dlg_btn="${dlg_lines[1]}"
  local dlg_text="${(j:\n:)dlg_lines[2,-1]}"
  current_reply="${dlg_text}"

  case "${dlg_btn}" in
    OK)
      break
      ;;
    Copy)
      break
      ;;
    "Follow Up")
      local followup="$(prompt_follow_up)" || continue
      [[ -z "${followup//[[:space:]]/}" ]] && continue

      show_processing_notice
      log_dialog "follow-up API request starting; style=${reply_style}"
      local previous_reply="${current_reply}"
      local next_reply
      next_reply="$(generate_reply "${previous_reply}" "${followup}")"
      local followup_rc=$?
      log_dialog "follow-up API request finished; rc=${followup_rc}; reply_chars=${#next_reply}"
      if (( followup_rc != 0 )); then
        current_reply="${previous_reply}"
        log_dialog "follow-up failed; error=${next_reply}"
        error_dialog $'Follow-up request failed. Keeping previous reply.\n\n'"${next_reply}"
        continue
      fi
      current_reply="${next_reply}"

      if [[ "${auto_copy}" == "true" ]]; then
        print -r -- "${current_reply}" | pbcopy 2>/dev/null || true
      fi

      if [[ "${save_history}" == "true" ]]; then
        AI_REPLY_HISTORY_PATH="${history_path}" \
        AI_REPLY_INPUT_TEXT="${input_from_stdin}" \
        AI_REPLY_RUNTIME_PROMPT="${runtime_prompt} | followup: ${followup}" \
        AI_REPLY_MODEL="${model}" \
        AI_REPLY_STYLE="${reply_style}" \
        AI_REPLY_DETECTED_LANGUAGE="${detected_language}" \
        AI_REPLY_FINAL_REPLY="${current_reply}" \
        python3 "${lib_dir}/append_history.py" 2>/dev/null || true
      fi
      continue
      ;;
  esac
done
