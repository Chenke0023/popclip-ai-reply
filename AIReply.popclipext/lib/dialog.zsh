#!/bin/zsh
# Background dialog + follow-up handler for AI Reply.
# Called with a session file path (zsh source file created by reply.zsh).

set -u

session_file="${1:-}"
if [[ -z "${session_file}" || ! -f "${session_file}" ]]; then
  exit 1
fi

source "${session_file}"

# Ensure required vars exist
: "${current_reply}" "${lib_dir}" "${debug_dir}"

# Clean up session file on exit
cleanup_session() {
  rm -f "${session_file}" 2>/dev/null || true
}
trap cleanup_session EXIT

# ------------------------------- utils ----------------------------------

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

expand_path() {
  local p="$1"
  print -r -- "${p/#\~\//${HOME}/}"
}

# --------------------------- dialogs ------------------------------------

show_reply_dialog() {
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
  osascript <<'APPLESCRIPT' 2>/dev/null
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
  if (( rc == 0 )) && [[ -s "${out_tmp}" ]]; then
    cat "${out_tmp}"
  fi
  rm -f "${reply_tmp}" "${meta_tmp}" "${out_tmp}" 2>/dev/null
  return ${rc}
}

prompt_follow_up() {
  local out_tmp
  out_tmp="$(mktemp -t aireply.followup.XXXXXX)"

  AI_REPLY_OUT_FILE="${out_tmp}" \
  osascript <<'APPLESCRIPT' 2>/dev/null
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv

set outFile to my getenv("AI_REPLY_OUT_FILE")
set dlg to display dialog "输入追加要求（例如：更短、更礼貌、补充时间点…）：" default answer "" buttons {"取消","发送"} default button "发送" with title "AI Reply"
if button returned of dlg is "取消" then
  error number -128
end if
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
  print -r -- "${res}"
}

# --------------------------- error dialog -------------------------------

error_dialog() {
  local msg="$1"
  local msg_tmp
  msg_tmp="$(mktemp -t aireply.err.XXXXXX)"
  print -rn -- "${msg}" > "${msg_tmp}"

  AI_REPLY_MSG_FILE="${msg_tmp}" \
  osascript <<'APPLESCRIPT' 2>/dev/null || true
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
    -o "${body_file}" \
    -w "%{http_code}" \
    -X POST "${test_endpoint}/chat/completions" \
    -H "Authorization: Bearer ${test_api_key}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data-binary "${payload_json}" \
    2>/dev/null)"
  curl_exit=$?

  if (( curl_exit != 0 )); then
    print -r -- "Network error: curl exit ${curl_exit}"
    return 1
  fi
  if [[ ! -s "${body_file}" ]]; then
    print -r -- "Empty response body"
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
  for pair in "${tried_pairs[@]}"; do
    local current_api_key="${pair%%|*}"
    local current_endpoint="${pair#*|}"

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
        last_error_msg="${result}"
        continue
        ;;
    esac
  done

  print -r -- "${last_error_msg:-No valid API keys configured.}"
  return 1
}

# ------------------------------- main loop ------------------------------

while true; do
  dlg_out="$(show_reply_dialog "${current_reply}")" || break

  dlg_lines=("${(@f)dlg_out}")
  dlg_btn="${dlg_lines[1]}"
  dlg_text="${(j:\n:)dlg_lines[2,-1]}"
  current_reply="${dlg_text}"

  case "${dlg_btn}" in
    OK)
      break
      ;;
    Copy)
      break
      ;;
    "Follow Up")
      followup="$(prompt_follow_up)" || continue
      [[ -z "${followup//[[:space:]]/}" ]] && continue

      current_reply="$(generate_reply "${current_reply}" "${followup}")"
      if (( $? != 0 )); then
        error_dialog "Follow-up request failed. Keeping previous reply."
        continue
      fi

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
