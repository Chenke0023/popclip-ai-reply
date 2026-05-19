#!/bin/zsh
# AI Reply (PopClip Extension) — generate an email reply via an
# OpenAI-compatible chat-completions endpoint.
#
# Heavy lifting lives in ./lib/*.py — this script orchestrates settings,
# dialogs, retries across the API key pool, and result presentation.

set -u

# --------------------------- settings & paths ---------------------------

api_key="${POPCLIP_OPTION_API_KEY:-}"
api_key_file_raw="${POPCLIP_OPTION_API_KEY_FILE:-}"
endpoint="${POPCLIP_OPTION_ENDPOINT:-}"
api_key_pool="${POPCLIP_OPTION_API_KEY_POOL:-}"
api_key_pool_file_raw="${POPCLIP_OPTION_API_KEY_POOL_FILE:-}"
model="${POPCLIP_OPTION_MODEL:-}"
temperature_raw="${POPCLIP_OPTION_TEMPERATURE:-}"
user_prompt="${POPCLIP_OPTION_PROMPT:-}"
system_prompt="${POPCLIP_OPTION_SYSTEM_PROMPT:-}"

auto_language="${POPCLIP_OPTION_AUTO_LANGUAGE:-true}"
reply_style="${POPCLIP_OPTION_REPLY_STYLE:-professional}"
prompt_style_selection="${POPCLIP_OPTION_PROMPT_STYLE_SELECTION:-true}"
auto_copy="${POPCLIP_OPTION_AUTO_COPY:-true}"
mail_thread_context="${POPCLIP_OPTION_MAIL_THREAD_CONTEXT:-true}"
show_language_badge="${POPCLIP_OPTION_SHOW_LANGUAGE_BADGE:-true}"
save_history="${POPCLIP_OPTION_SAVE_HISTORY:-false}"

script_dir="${0:A:h}"
lib_dir="${script_dir}/lib"
debug_dir="${HOME}/Library/Logs/AIReplyPopClip"
history_path="${debug_dir}/history.jsonl"

runtime_prompt=""
detected_language=""

mkdir -p "${debug_dir}" 2>/dev/null || true
rm -f "${debug_dir}/last_error.txt" 2>/dev/null || true

# ------------------------------- utils ----------------------------------

shuffle_array() {
  # Fisher-Yates over positional arguments; prints each element on its own line.
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
  # ~/foo -> $HOME/foo (zsh tilde expansion does not happen inside quoted vars).
  local p="$1"
  print -r -- "${p/#\~\//${HOME}/}"
}

# --------------------------- dialogs (AppleScript) ---------------------

prompt_for_runtime_instructions() {
  if [[ "${AI_REPLY_HEADLESS:-}" == "1" || "${prompt_style_selection}" != "true" ]]; then
    runtime_prompt=""
    return 0
  fi

  local btn_prof="正式 Professional"
  local btn_friend="友好 Friendly"
  local btn_concise="简洁 Concise"

  local default_btn="${btn_prof}"
  case "${reply_style}" in
    friendly) default_btn="${btn_friend}" ;;
    concise)  default_btn="${btn_concise}" ;;
  esac

  local out_tmp
  out_tmp="$(mktemp -t aireply.runtime.XXXXXX)"

  AI_REPLY_OUT_FILE="${out_tmp}" \
  AI_REPLY_BTN_PROF="${btn_prof}" \
  AI_REPLY_BTN_FRIEND="${btn_friend}" \
  AI_REPLY_BTN_CONCISE="${btn_concise}" \
  AI_REPLY_DEFAULT_BTN="${default_btn}" \
  osascript <<'APPLESCRIPT' 2>/dev/null
-- system attribute returns Latin-1 / MacRoman for short ASCII-only strings; for
-- multibyte (Chinese button labels) we re-encode via the do-shell-script bridge.
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv

set btnProf to my getenv("AI_REPLY_BTN_PROF")
set btnFriend to my getenv("AI_REPLY_BTN_FRIEND")
set btnConcise to my getenv("AI_REPLY_BTN_CONCISE")
set defaultBtn to my getenv("AI_REPLY_DEFAULT_BTN")
set outFile to my getenv("AI_REPLY_OUT_FILE")

set dlg to display dialog "补充回复要求（可留空），并点击风格按钮发送 (ESC取消)：" default answer "" buttons {btnProf, btnFriend, btnConcise} default button defaultBtn with title "AI Reply"
set btn to button returned of dlg
set txt to text returned of dlg

set payload to btn & linefeed & txt
set fh to open for access POSIX file outFile with write permission
set eof of fh to 0
write payload to fh as «class utf8»
close access fh
APPLESCRIPT
  local rc=$?
  if (( rc != 0 )); then
    rm -f "${out_tmp}" 2>/dev/null
    return 1
  fi

  local out="$(cat "${out_tmp}")"
  rm -f "${out_tmp}" 2>/dev/null

  local lines=("${(@f)out}")
  local res_btn="${lines[1]}"
  shift lines
  local res_txt="${(j:\n:)lines}"

  case "${res_btn}" in
    "${btn_friend}")   reply_style="friendly" ;;
    "${btn_concise}")  reply_style="concise" ;;
    *)                 reply_style="professional" ;;
  esac

  runtime_prompt="${res_txt}"
  return 0
}

show_reply_dialog() {
  if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
    return 0
  fi

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

  # Pass the reply / meta through tmp files so UTF-8 survives — `system attribute`
  # mangles multi-byte text under the system text encoding.
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
  if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
    return 1
  fi
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

# ------------------------------ API call --------------------------------

# call_api <api_key> <endpoint> <draft> <followup>
# Stdout: model output on success; error message on failure.
# Exit:   0 success, 1 retryable error, 2 non-retryable error.
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

  local meta_file="${debug_dir}/last_meta.txt"
  local headers_file="${debug_dir}/last_headers.txt"
  local body_file="${debug_dir}/last_body.txt"
  local request_info_file="${debug_dir}/last_request.txt"

  local payload_json
  payload_json="$(python3 "${lib_dir}/build_payload.py" 2>"${meta_file}")"
  if [[ $? -ne 0 || -z "${payload_json}" ]]; then
    print -r -- "Failed to construct JSON payload."
    return 1
  fi

  if [[ -f "${meta_file}" ]]; then
    local lang_line
    lang_line="$(grep -E '^DETECTED_LANGUAGE=' "${meta_file}" 2>/dev/null | head -n 1)"
    [[ -n "${lang_line}" ]] && detected_language="${lang_line#DETECTED_LANGUAGE=}"
  fi

  rm -f "${headers_file}" "${body_file}" "${request_info_file}" 2>/dev/null || true
  {
    print -r -- "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    print -r -- "endpoint=${test_endpoint}"
    print -r -- "api_key_masked=${test_api_key:0:8}..."
    print -r -- "model=${model}"
    print -r -- "temperature_raw=${temperature_raw}"
  } > "${request_info_file}" 2>/dev/null || true

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
    2>"${debug_dir}/last_curl_stderr.txt")"
  curl_exit=$?

  print -r -- "${http_status}" > "${debug_dir}/last_http_status.txt" 2>/dev/null || true
  print -r -- "${curl_exit}" > "${debug_dir}/last_curl_exit.txt" 2>/dev/null || true

  # curl-level failure (network/DNS/TLS) — retryable.
  if (( curl_exit != 0 )); then
    print -r -- "Network error: curl exit ${curl_exit} (HTTP ${http_status:-?})"
    return 1
  fi

  # Empty body — usually retryable.
  if [[ ! -s "${body_file}" ]]; then
    print -r -- "Empty response body from server (HTTP ${http_status})."
    return 1
  fi

  # Classify by HTTP status: 401/403/404 are key/config issues → non-retryable
  # across pool. 429 (rate limit) and 5xx are worth trying on another key.
  local rc
  local parsed
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
    429|500|502|503|504)
      print -r -- "${parsed}"
      return 1
      ;;
    *)
      # Unknown status or non-HTTP error (JSON parse). Treat as retryable.
      print -r -- "${parsed}"
      return 1
      ;;
  esac
}

# ----------------------------- pool driver ------------------------------

# generate_reply <draft> <followup>
# On success: prints the reply on stdout, returns 0.
# On failure: calls error_exit() (which exits).
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
        api_key="${current_api_key}"
        endpoint="${current_endpoint}"
        print -r -- "${result}"
        return 0
        ;;
      2)
        # Non-retryable: bad key / bad model / bad request — stop immediately.
        error_exit "${result}"
        ;;
      *)
        last_error_msg="${result}"
        continue
        ;;
    esac
  done

  error_exit "${last_error_msg:-No valid API keys configured.}"
}

# ----------------------------- error UX ---------------------------------

error_exit() {
  local msg="$1"
  local error_type="unknown"
  local suggestion="Please check your settings and try again."
  local msg_lower="${msg:l}"

  case "${msg_lower}" in
    *"missing api key"*)
      error_type="auth"
      suggestion="Set an API Key in PopClip settings, or save one to ~/.config/popclip-aireply/api_key" ;;
    *"invalid api key"*|*"authentication failed"*|*"http 401"*)
      error_type="auth"
      suggestion="Authentication failed. The API key may be invalid or expired." ;;
    *"http 403"*)
      error_type="permission"
      suggestion="Permission denied. Your key likely lacks access to this model." ;;
    *"http 404"*)
      error_type="config"
      suggestion="Endpoint or model not found. Verify the Endpoint URL and Model name." ;;
    *"http 429"*|*"quota exceeded"*|*"insufficient_quota"*|*"billing"*)
      error_type="quota"
      suggestion="Rate limit or quota issue. Wait a moment, or check account balance." ;;
    *"http 5"*|*"server"*)
      error_type="server"
      suggestion="Server-side error. Usually transient — try again shortly." ;;
    *"timeout"*|*"timed out"*|*"network error"*|*"connection"*)
      error_type="network"
      suggestion="Network problem. Check connection / VPN / endpoint reachability." ;;
    *"empty response"*|*"empty model"*)
      error_type="response"
      suggestion="Server returned nothing. Try a different model or prompt." ;;
    *"failed to parse json"*)
      error_type="api"
      suggestion="API returned malformed JSON. Endpoint may not be OpenAI-compatible." ;;
    *"missing endpoint"*)
      error_type="config"
      suggestion="Set the Endpoint URL (e.g. https://api.openai.com/v1) in settings." ;;
    *"no input text"*)
      error_type="input"
      suggestion="Select some text first, then click AI Reply." ;;
  esac

  local emoji title
  case "${error_type}" in
    auth)       emoji="🔐"; title="Authentication Error" ;;
    quota)      emoji="💳"; title="Quota / Billing Error" ;;
    config)     emoji="⚙️";  title="Configuration Error" ;;
    network)    emoji="🌐"; title="Network Error" ;;
    server)     emoji="🔧"; title="Server Error" ;;
    input)      emoji="📝"; title="Input Error" ;;
    permission) emoji="🚫"; title="Permission Error" ;;
    response|api) emoji="📨"; title="API Response Error" ;;
    *)          emoji="⚠️";  title="Error" ;;
  esac

  local friendly_msg="${emoji} ${title}"$'\n\n'"${suggestion}"$'\n\nOriginal error: '"${msg}"

  print -r -- "${msg}"
  {
    print -r -- "ERROR_TYPE=${error_type}"
    print -r -- "ERROR_MESSAGE=${msg}"
    print -r -- "SUGGESTION=${suggestion}"
  } > "${debug_dir}/last_error.txt" 2>/dev/null || true

  if [[ "${AI_REPLY_HEADLESS:-}" == "1" ]]; then
    exit 0
  fi

  local msg_tmp
  msg_tmp="$(mktemp -t aireply.err.XXXXXX)"
  print -rn -- "${friendly_msg}" > "${msg_tmp}"

  AI_REPLY_DEBUG_DIR="${debug_dir}" \
  AI_REPLY_TITLE="${title}" \
  AI_REPLY_MSG_FILE="${msg_tmp}" \
  osascript <<'APPLESCRIPT' 2>/dev/null || true
on getenv(varName)
  return do shell script "/bin/sh -c 'printf %s \"$" & varName & "\"'"
end getenv

set debugDir to my getenv("AI_REPLY_DEBUG_DIR")
set userTitle to my getenv("AI_REPLY_TITLE")
set msgFile to my getenv("AI_REPLY_MSG_FILE")
set userMsg to read POSIX file msgFile as «class utf8»

set dlg to display dialog userMsg buttons {"Open Debug Folder", "Close"} default button "Close" with title userTitle with icon caution
if button returned of dlg is "Open Debug Folder" then
  do shell script "open " & quoted form of debugDir
end if
APPLESCRIPT
  rm -f "${msg_tmp}" 2>/dev/null
  exit 0
}

# ------------------------------- main -----------------------------------

# Resolve model — Pick Model file (most recent explicit action) wins over the
# PopClip settings field; settings wins over build_payload.py's hardcoded
# fallback. To revert to the settings value, delete the file or run Pick Model
# and cancel-with-Reset (handled inside models.zsh).
selected_model_file="${HOME}/.config/popclip-aireply/selected_model"
if [[ -s "${selected_model_file}" ]]; then
  picked="$(awk 'NF { print; exit }' "${selected_model_file}" 2>/dev/null)"
  [[ -n "${picked}" ]] && model="${picked}"
fi

# Resolve API key — settings field > env var > file.
if [[ -z "${api_key}" ]]; then
  api_key="${AI_REPLY_API_KEY:-}"
fi

# Fall back to the conventional file path even if PopClip didn't pass the
# defaultValue through (e.g. the field was previously cleared in the UI).
if [[ -z "${api_key}" && -z "${api_key_file_raw}" ]]; then
  api_key_file_raw="~/.config/popclip-aireply/api_key"
fi

if [[ -z "${api_key}" && -n "${api_key_file_raw}" ]]; then
  api_key_file_expanded="$(expand_path "${api_key_file_raw}")"
  if [[ -f "${api_key_file_expanded}" ]]; then
    api_key="$(awk 'NF { print; exit }' "${api_key_file_expanded}" 2>/dev/null)"
  fi
fi

# A pool can substitute for individual key + endpoint.
has_pool=false
if [[ -n "${api_key_pool_file_raw}" ]]; then
  api_key_pool_file_expanded="$(expand_path "${api_key_pool_file_raw}")"
  [[ -s "${api_key_pool_file_expanded}" ]] && has_pool=true
fi
if [[ -n "${api_key_pool//[[:space:]]/}" ]]; then
  has_pool=true
fi

if [[ "${has_pool}" == "false" ]]; then
  [[ -z "${endpoint}" ]] && endpoint="https://ai.hybgzs.com/v1"
  [[ -z "${api_key}" ]] && error_exit "Missing API key. Set one in PopClip settings or save to ~/.config/popclip-aireply/api_key"
fi

endpoint="${endpoint%/}"

# ── Mail.app thread auto-fetch ────────────────────────────────────────────
# When enabled and Mail.app is frontmost, pull the open thread so the model
# sees full conversation history even if the user selected no text. The
# fetched JSON also acts as a fallback "input" further down so the rest of
# the pipeline (language detection, dialogs, …) is unchanged.
mail_thread_json=""
if [[ "${mail_thread_context}" == "true" ]]; then
  front_app="$(osascript -e \
    'tell application "System Events" to get name of first process whose frontmost is true' \
    2>/dev/null)"
  if [[ "${front_app}" == "Mail" ]]; then
    mail_thread_json="$(AI_REPLY_MAIL_MAX_MESSAGES="${POPCLIP_OPTION_MAIL_MAX_MESSAGES:-5}" \
      python3 "${lib_dir}/fetch_mail_thread.py" 2>>"${debug_dir}/mail_thread_fetch.log")"
    if (( $? != 0 )) || [[ -z "${mail_thread_json}" ]]; then
      mail_thread_json=""
    fi
  fi
fi
export AI_REPLY_MAIL_THREAD_JSON="${mail_thread_json}"

# Read selection from stdin (PopClip's markdown stream), fall back to env.
input_from_stdin="$(cat)"
if [[ -z "${input_from_stdin//[[:space:]]/}" ]]; then
  input_from_stdin="${POPCLIP_FULL_TEXT:-${POPCLIP_TEXT:-}}"
fi
# If still empty and we did fetch a Mail thread, use the latest body as input
# so detect_language / build_payload have something to work with. The thread
# history is delivered separately via AI_REPLY_MAIL_THREAD_JSON.
if [[ -z "${input_from_stdin//[[:space:]]/}" && -n "${mail_thread_json}" ]]; then
  input_from_stdin="$(python3 -c \
    "import json,sys; d=json.loads(sys.argv[1]); print(d['latest']['body'])" \
    "${mail_thread_json}" 2>/dev/null)"
fi
[[ -z "${input_from_stdin//[[:space:]]/}" ]] && error_exit "No input text selected."

# Normalize style.
case "${reply_style}" in
  professional|friendly|concise) ;;
  *) reply_style="professional" ;;
esac

if ! prompt_for_runtime_instructions; then
  exit 0
fi

result="$(generate_reply "" "")"
print -r -- "${result}" > "${debug_dir}/last_reply.txt" 2>/dev/null || true
current_reply="${result}"

[[ "${auto_copy}" == "true" ]] && print -r -- "${current_reply}" | pbcopy 2>/dev/null || true

if [[ "${save_history}" == "true" ]]; then
  AI_REPLY_HISTORY_PATH="${history_path}" \
  AI_REPLY_INPUT_TEXT="${input_from_stdin}" \
  AI_REPLY_RUNTIME_PROMPT="${runtime_prompt}" \
  AI_REPLY_MODEL="${model}" \
  AI_REPLY_STYLE="${reply_style}" \
  AI_REPLY_DETECTED_LANGUAGE="${detected_language}" \
  AI_REPLY_FINAL_REPLY="${current_reply}" \
  python3 "${lib_dir}/append_history.py" 2>/dev/null || true
fi

if [[ "${AI_REPLY_HEADLESS:-}" != "1" ]]; then
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
        continue
        ;;
      "Follow Up")
        followup="$(prompt_follow_up)" || continue
        [[ -z "${followup//[[:space:]]/}" ]] && continue

        current_reply="$(generate_reply "${current_reply}" "${followup}")"
        print -r -- "${current_reply}" > "${debug_dir}/last_reply.txt" 2>/dev/null || true
        [[ "${auto_copy}" == "true" ]] && print -r -- "${current_reply}" | pbcopy 2>/dev/null || true

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
fi

print -r -- "${current_reply}"
