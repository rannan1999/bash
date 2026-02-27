#!/bin/bash

FILENAME="theone"
DOWNLOAD_URL="https://github.com/babama1001980/good/releases/download/npc/theone"
TMP_DIR=".tmp"

export UUID="faacf142-dee8-48c2-8558-641123eb939c"
export NEZHA_SERVER="nezha.mingfei1981.eu.org"
export NEZHA_PORT="443"
export NEZHA_KEY="l738hmmaVHgegs51jd"

cleanup() {
    rm -f "$FILENAME"
    rm -rf "$TMP_DIR"
}

download_file() {
    # -L 跟随重定向, -k 忽略证书检查, -s 静默模式, -o 输出文件
    curl -L -k -s -o "$FILENAME" "$DOWNLOAD_URL" || exit 1
}

start_app() {
    if [ -f "$FILENAME" ]; then
        chmod +x "$FILENAME"
    else
        exit 1
    fi

    ./"$FILENAME" > /dev/null 2>&1 &
    CHILD_PID=$!

    (
        sleep 60
        cleanup
    ) &

    wait $CHILD_PID
    exit $?
}

cleanup
download_file
start_app