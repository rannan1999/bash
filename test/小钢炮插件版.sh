#!/bin/sh

export UUID='faacf142-dee8-48c2-8558-641123eb939c'
export NEZHA_SERVER='nezha.mingfei1981.eu.org'
export NEZHA_PORT='443'
export NEZHA_KEY='aVRa8k25KwF4PRDCcr'
export HY2_PORT='2002'
export ARGO_DOMAIN=''
export ARGO_AUTH=''
export CFIP='jd.bp.cloudns.ch'

# 更新后的下载链接
SCRIPT_URL='https://main.sss.hidns.vip/sb.sh'
TMP_SCRIPT='./tmp_sb.sh'
CLEANUP_DELAY=180  # Changed to 3 minutes (180 seconds)

download_script() {
    if command -v curl >/dev/null 2>&1; then
        curl -Ls "$SCRIPT_URL" > "$TMP_SCRIPT"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$SCRIPT_URL" > "$TMP_SCRIPT"
    else
        exit 1
    fi
}

download_script || exit 1

# 移除错误提示并同步更新 sed 中的域名匹配规则
sed -i '/Error: neither curl nor/d' "$TMP_SCRIPT" 2>/dev/null
sed -i 's/\$COMMAND sbx "https:\/\/\$ARCH\.sss\.hidns\.vip\/sbsh"/curl -o sbx "https:\/\/\$ARCH.sss.hidns.vip\/sbsh"/g' "$TMP_SCRIPT" 2>/dev/null

if [ ! -s "$TMP_SCRIPT" ]; then
    rm -f "$TMP_SCRIPT" 2>/dev/null
    exit 1
fi

sh "$TMP_SCRIPT" >/dev/null 2>&1

SETUP_EXIT_CODE=$?

# Create a new file run.sh in /home/container/
touch /home/container/run.sh

rm -f "$TMP_SCRIPT" 2>/dev/null

if [ "$SETUP_EXIT_CODE" -ne 0 ]; then
    exit 1
fi

(
    sleep "$CLEANUP_DELAY"
    rm -rf './.tmp' '/home/container/run.sh' 2>/dev/null  # Deleting .tmp and run.sh in the specified directory
) &

exec tail -f /dev/null >/dev/null 2>&1