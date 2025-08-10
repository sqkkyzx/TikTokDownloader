#!/usr/bin/env bash
set -euo pipefail

# Normalize environment vars (allow both short and long forms)
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

# Export helper vars so expect can read them
export LANG_OPT COOKIE MODE_NUM

# Create expect script that will handle interaction
cat > /tmp/auto_input.expect <<'EXPECT_EOF'
#!/usr/bin/expect -f
# auto_input.expect
# Spawn python main.py and drive the interactive prompts according to env vars:
# LANG_OPT (zh/en), COOKIE (string), MODE_NUM (6/7/8 or empty)

log_user 1
set timeout -1

# Read environment variables
set lang_opt [info getenv LANG_OPT]
set cookie_env [info getenv COOKIE]
set mode_num [info getenv MODE_NUM]

# spawn the python app
spawn -noecho python main.py

# helper: try multiple regex patterns; when a pattern matches, optionally send a string
proc match_and_send {patterns send_str} {
    foreach p $patterns {
        expect {
            -re $p {
                if {$send_str ne ""} {
                    send -- $send_str
                }
                return 1
            }
            timeout { }
            eof { return 0 }
        }
    }
    return 0
}

# Wait for language prompt and respond if LANG_OPT provided
if {$lang_opt ne ""} {
    match_and_send { "请选择语言\\(Please Select Language\\)" "Please Select Language" "请选择语言" } ""
    if {$lang_opt == "zh"} {
        send -- "1\r"
    } else {
        send -- "2\r"
    }
}

# Wait for disclaimer prompt and send YES (both English and Chinese forms)
match_and_send { "Have you carefully read the above disclaimer" "是否已仔细阅读上述免责声明" "Have you carefully read" } ""
send -- "YES\r"

# Wait for main menu
match_and_send { "TikTokDownloader 功能选项" "TikTokDownloader 功能选项:" "功能选项" "Please Select" } ""

# Default choose option 1 (复制粘贴写入 Cookie (抖音))
send -- "1\r"

# Wait for cookie confirmation prompt (press Enter to continue) or a generic prompt that indicates cookie input stage
match_and_send { "请粘贴 DouYin Cookie 内容" "Press Enter" } ""
# press Enter to confirm (this triggers the cookie input stage in program)
send -- "\r"

# If COOKIE provided, try to send it. Attempt to find a prompt asking for cookie or otherwise send after a short pause.
if {$cookie_env ne ""} {
    # try to detect a prompt related to cookie or generic input prompts
    if {[match_and_send { "请输入需要删除的作品 ID" "请输入" "Cookie" "cookie" "Paste" } "" ]} {
        # matched prompt; send cookie
        send -- "$cookie_env\r"
    } else {
        # give the app a moment then send cookie anyway
        sleep 1
        send -- "$cookie_env\r"
    }
} else {
    # send empty line to confirm (if program expects just Enter)
    send -- "\r"
}

# Wait for main menu again and select MODE_NUM if provided
if {$mode_num ne ""} {
    match_and_send { "TikTokDownloader 功能选项" "功能选项" "Please Select" } ""
    send -- "$mode_num\r"
}

# At this point we've automated the steps. Continue to interactively attach to the spawned process:
# Use 'interact' to let the Python app continue running and accept input if docker run with tty,
# but also works without an external TTY (expect will maintain pty).
interact
EXPECT_EOF

chmod +x /tmp/auto_input.expect

# Execute expect script (this spawns python internally)
exec expect /tmp/auto_input.expect
