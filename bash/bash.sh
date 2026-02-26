#!/bin/sh

# Binary and config definitions
apps=(
  "bash:bash:"  # name:binary:args (args empty)
)

# Run binary with keep-alive
run_process() {
  local app_name="$1"
  local binary="$2"
  shift 2
  local args="$@"

  while true; do
    echo "[START] Starting $app_name..."
    $binary $args
    local code=$?
    echo "[EXIT] $app_name exited with code: $code"
    echo "[RESTART] Restarting $app_name..."
    sleep 3
  done
}

# Main execution
main() {
  for app in "${apps[@]}"; do
    IFS=':' read -r app_name binary args <<< "$app"
    run_process "$app_name" "$binary" $args
  done
}

main "$@"