#!/bin/bash

# ====================================================================
# Go SO_REUSEPORT Graceful Restart Script (macOS / Linux Compatible)
# ====================================================================

# Current PID file name
PID_FILE="server.pid"
# Server port (without colon, used for curl)
PORT="8080"
# Server binary name (executable file name)
SERVER_BIN="./server"
# Timeout setting
MAX_WAIT_SECONDS=15

echo "--- 1. 🛠️ Build ---"
# Build the binary
go build -o $SERVER_BIN ./cmd/server/

# Get old process ID
if [ -f $PID_FILE ]; then
    OLD_PID=$(cat $PID_FILE)
else
    OLD_PID=""
fi

echo "--- 2. 🚀 Start new process ---"
# New process start
./$SERVER_BIN &
NEW_PID=$!

echo "New Server (PID: $NEW_PID) started."

# Wait a moment for the new process to fully start listening
sleep 1

# --- 3. 🩺 Health Check (Retry until new PID responds) ---
echo "--- 3. 🩺 Health Check (Waiting for new process to respond) ---"
CHECK_SUCCESS=0

for i in $(seq 1 $MAX_WAIT_SECONDS); do
    # Execute health check
    RESPONSE=$(curl -s http://localhost:$PORT)

    # Check if the new PID is included in the response
    if echo "$RESPONSE" | grep "OK. Handled by PID: $NEW_PID" > /dev/null; then
        echo "✅ Attempt $i: New server (PID: $NEW_PID) is healthy and accepting traffic."
        CHECK_SUCCESS=1
        break
    else
        # Old PID is likely responding. Wait a moment before retrying.
        # If the old PID is responding, it means there is no downtime and processing continues.
        OLD_PID_CHECK=$(echo "$RESPONSE" | awk '/PID/ {print $NF}')
        echo "Attempt $i: Old PID ($OLD_PID_CHECK) responded. Waiting for new PID..."
        sleep 1
    fi
done

if [ $CHECK_SUCCESS -eq 1 ]; then
    # If successful, update the PID file with the new PID
    echo $NEW_PID > $PID_FILE
else
    # If timed out
    echo "❌ ERROR: New server failed to respond with its PID after $MAX_WAIT_SECONDS seconds. Aborting."
    kill -9 $NEW_PID # Force kill the failed process
    exit 1
fi

# --- 4. 🛑 Graceful Shutdown of Old Process ---

if [ -n "$OLD_PID" ]; then
    echo "--- 4. 🛑 Sending SIGTERM to old process (PID: $OLD_PID) (Graceful Shutdown) ---"

    # Send SIGTERM (graceful shutdown signal)
    kill -SIGTERM $OLD_PID

    # Wait for the old process to exit gracefully
    echo "Waiting for old process to exit gracefully (Max $MAX_WAIT_SECONDS seconds)..."

    for i in $(seq 1 $MAX_WAIT_SECONDS); do
        if ! kill -0 $OLD_PID 2>/dev/null; then
            echo "Old process (PID: $OLD_PID) shut down successfully."
            break
        fi
        sleep 1
    done

    # If still running after timeout, force kill
    if kill -0 $OLD_PID 2>/dev/null; then
        echo "⚠️ WARNING: Old process (PID: $OLD_PID) did not shut down gracefully. Forcing kill."
        kill -9 $OLD_PID
    fi
else
    echo "No old process found. Deployment complete."
fi

echo "--- ✅ Graceful Restart Complete ---"
