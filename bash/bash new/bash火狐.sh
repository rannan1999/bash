#!/bin/sh

# 将你的完整命令赋值给 SERVICE_COMMAND
SERVICE_COMMAND="ARGO_AUTH=eyJhIjoiNjgyNWI4YTZjODBhYWQxODlmYWI5ZWEwMDI5YzY2NjgiLCJ0IjoiMDkyYTQzYjktN2ExMi00NjUxLTgzYjMtM2VjY2RjMzZlNTJlIiwicyI6IllqVTBOak16T0RndE4yWmxPQzAwWWpreExUaGpZMll0TkRBNE1UZzVPRGRqTW1SaSJ9 FF_PASS=babama123 FF_PORT=8002 bash <(curl -Ls https://gbjs.serv00.net/sh/ff_lite.sh) start"

run_service() {
    echo "[BASH] Running service command..."
    
    # 核心改动：把标准输入重定向到 /dev/null
    # 这样即使火狐脚本倒计时结束进行“清屏”操作，也不会因为检测不到终端而异常退出
    bash -c "$SERVICE_COMMAND" < /dev/null
    
    echo "[BASH] Service exited with code: $?"
}

keep_alive() {
    echo "[SYSTEM] Keeping container alive..."
    tail -f /dev/null
}

main() {
    run_service
    keep_alive
}

main "$@"