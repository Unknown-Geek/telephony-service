#!/bin/bash
# =============================================================================
# AGI Connector Script - Bridge between Asterisk and n8n
# =============================================================================
# This script receives call information from Asterisk and triggers an n8n
# webhook to process the call with AI and generate TTS responses.
#
# Location: /var/lib/asterisk/agi-bin/agi-connector.sh
# =============================================================================

# Configuration
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-https://n8n.shravanpandala.me/webhook/asterisk-call}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to read AGI variables
read_agi_vars() {
    while read line; do
        # AGI variables end with empty line
        [ -z "$line" ] && break
        
        # Parse AGI variable
        var_name=$(echo "$line" | cut -d: -f1)
        var_value=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
        
        # Export as environment variable
        case "$var_name" in
            agi_callerid)
                export AGI_CALLERID="$var_value"
                ;;
            agi_calleridname)
                export AGI_CALLERIDNAME="$var_value"
                ;;
            agi_extension)
                export AGI_EXTENSION="$var_value"
                ;;
            agi_uniqueid)
                export AGI_UNIQUEID="$var_value"
                ;;
            agi_context)
                export AGI_CONTEXT="$var_value"
                ;;
            agi_channel)
                export AGI_CHANNEL="$var_value"
                ;;
        esac
    done
}

# Function to send AGI command
agi_command() {
    echo "$1"
    read response
    echo "$(date '+%Y-%m-%d %H:%M:%S') - AGI Response: $response" >> "$LOG_FILE"
}

# Function to set Asterisk channel variable
set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Main execution
main() {
    log_message "=== AGI Connector Started ==="
    
    # Read AGI variables from Asterisk
    read_agi_vars
    
    log_message "Call from: ${AGI_CALLERID:-unknown}"
    log_message "To extension: ${AGI_EXTENSION:-unknown}"
    log_message "Unique ID: ${AGI_UNIQUEID:-unknown}"
    
    # Prepare payload for n8n webhook
    PAYLOAD=$(cat <<EOF
{
    "caller_id": "${AGI_CALLERID:-unknown}",
    "caller_name": "${AGI_CALLERIDNAME:-unknown}",
    "extension": "${AGI_EXTENSION:-unknown}",
    "unique_id": "${AGI_UNIQUEID:-unknown}",
    "context": "${AGI_CONTEXT:-unknown}",
    "channel": "${AGI_CHANNEL:-unknown}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    log_message "Sending to n8n webhook: $N8N_WEBHOOK_URL"
    log_message "Payload: $PAYLOAD"
    
    # Send request to n8n webhook
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time $TIMEOUT \
        "$N8N_WEBHOOK_URL" 2>&1)
    
    CURL_STATUS=$?
    
    if [ $CURL_STATUS -ne 0 ]; then
        log_message "ERROR: Failed to contact n8n webhook (exit code: $CURL_STATUS)"
        set_variable "AGI_STATUS" "ERROR"
        exit 1
    fi
    
    log_message "n8n Response: $RESPONSE"
    
    # Parse response - expecting JSON with audio_file or text_response
    AUDIO_FILE=$(echo "$RESPONSE" | jq -r '.audio_file // empty' 2>/dev/null)
    TEXT_RESPONSE=$(echo "$RESPONSE" | jq -r '.text_response // empty' 2>/dev/null)
    
    if [ -n "$AUDIO_FILE" ] && [ -f "$AUDIO_FILE" ]; then
        # Audio file already exists, copy to sounds directory
        cp "$AUDIO_FILE" "${SOUNDS_DIR}/response_${AGI_UNIQUEID}.wav"
        set_variable "AGI_STATUS" "SUCCESS"
        log_message "Audio file ready: response_${AGI_UNIQUEID}.wav"
        
    elif [ -n "$TEXT_RESPONSE" ]; then
        # Generate TTS from text response
        log_message "Generating TTS for: $TEXT_RESPONSE"
        
        TTS_PAYLOAD=$(cat <<EOF
{
    "model": "tts-1",
    "input": "$TEXT_RESPONSE",
    "voice": "alloy",
    "response_format": "mp3"
}
EOF
)
        
        # Call TTS service
        TTS_AUDIO="${SOUNDS_DIR}/response_${AGI_UNIQUEID}_temp.mp3"
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$TTS_PAYLOAD" \
            --max-time $TIMEOUT \
            -o "$TTS_AUDIO" \
            "$TTS_SERVICE_URL"
        
        if [ -f "$TTS_AUDIO" ] && [ -s "$TTS_AUDIO" ]; then
            # Convert MP3 to WAV for Asterisk (8kHz mono for telephony)
            sox "$TTS_AUDIO" -r 8000 -c 1 "${SOUNDS_DIR}/response_${AGI_UNIQUEID}.wav" 2>/dev/null
            rm -f "$TTS_AUDIO"
            set_variable "AGI_STATUS" "SUCCESS"
            log_message "TTS audio generated: response_${AGI_UNIQUEID}.wav"
        else
            log_message "ERROR: TTS generation failed"
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
    else
        log_message "WARNING: No audio or text response from n8n"
        set_variable "AGI_STATUS" "NO_RESPONSE"
    fi
    
    log_message "=== AGI Connector Finished ==="
}

# Run main function
main
