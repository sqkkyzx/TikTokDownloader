#!/usr/bin/env bash
set -euo pipefail

# Normalize environment vars (support multiple spellings)
LANGUAGE="${LANGUAGE:-${LANG:-}}"
case "${LANGUAGE,,}" in
  zh_cn|zh|zh-cn) LANG_OPT="zh" ;;
  en_us|en|en-us) LANG_OPT="en" ;;
  *) LANG_OPT="" ;;
esac

COOKIE="${COOKIE:-}"
RUN_MODE="${RUN_MODE:-}"

# Map RUN_MODE to menu number
case "${RUN_MODE,,}" in
  observe) MODE_NUM="6" ;;
  api)     MODE_NUM="7" ;;
  web)     MODE_NUM="8" ;;
  6|7|8)   MODE_NUM="${RUN_MODE}" ;;
  *)       MODE_NUM="" ;;
esac

# Export for expect
export LANG_OPT COOKIE MODE_NUM

# Create expect script
cat > /tmp/auto_input.expect <<'EXPECT_EOF'
#!/usr/bin/expect -f
# auto_input.expect - drive main.py prompts using env vars LANG_OPT, COOKIE, MODE_NUM

log_user 1
set timeout -1

# Read env variables via Tcl env array
set lang_opt $env(LANG_OPT)
set cookie_env $env(COOKIE)
set mode_num $env(MODE_NUM)

# spawn python (no -noecho to keep compatibility)
spawn python main.py

# helper: try multiple regex patterns; return 1 if any matched
proc wait_for_patterns {patterns timeout_ms} {
    set saved_timeout $::timeout
    set ::timeout -1
    foreach p $patterns {
        expect {
            -re $p { set ::timeout $saved_timeout; return 1 }
            timeout { }
            eof { set ::timeout $saved_timeout; return 0 }
        }
    }
    set ::timeout $saved_timeout
    return 0
}

# respond to language prompt if requested
if {$lang_opt ne ""} {
    # Wait for language selection prompt
    wait_for_patterns { "请选择语言\\(Please Select Language\\)" "Please Select Language" "请选择语言" } 0
    if {$lang_opt == "zh"} {
        send -- "1\r"
    } else {
        send -- "2\r"
    }
}

# wait for disclaimer prompt and send YES
wait_for_patterns { "Have you carefully read the above disclaimer" "是否已仔细阅读上述免责声明" "Have you carefully read" } 0
send -- "YES\r"

# wait for main menu to appear
wait_for_patterns { "TikTokDownloader 功能选项" "功能选项" "Please Select" } 0

# choose option 1 (paste cookie)
send -- "1\r"

# wait for cookie "press Enter to continue" prompt and press Enter
wait_for_patterns { "请粘贴 DouYin Cookie 内容" "Press Enter" } 0
send -- "\r"

# send COOKIE if provided, else send empty line
if {$cookie_env ne ""} {
    # try to wait for a cue to input cookie or otherwise send it after short pause
    if {[wait_for_patterns { "请粘贴 DouYin Cookie 内容" "Press Enter" } 0]} {
        send -- "$cookie_env\r"
    } else {
        # small sleep to let program reach input stage, then send cookie
        sleep 1
        send -- "$cookie_env\r"
    }
} else {
    send -- "\r"
}

# wait for menu again and select MODE_NUM if provided
if {$mode_num ne ""} {
    wait_for_patterns { "TikTokDownloader 功能选项" "功能选项" "Please Select" } 0
    send -- "$mode_num\r"
}

# Hand control over to the user/process; keep python running
interact
EXPECT_EOF

chmod +x /tmp/auto_input.expect

# exec expect (it spawns python inside)
exec expect /tmp/auto_input.expect
