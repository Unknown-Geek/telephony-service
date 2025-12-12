#!/bin/bash
# =============================================================================
# AGI Connector Script - Bridge between Asterisk and n8n
# =============================================================================
# Location: /var/lib/asterisk/agi-bin/agi-connector.sh
# =============================================================================

# Configuration
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-https://n8n.shravanpandala.me/webhook/asterisk-call}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

# Commands
CMD_MODE="${1:-welcome}"
RECORDING_FILE="$2"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Function to read AGI variables
read_agi_vars() {
    while read line; do
        [ -z "$line" ] && break
        var_name=$(echo "$line" | cut -d: -f1)
        var_value=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
        
        case "$var_name" in
            agi_callerid) export AGI_CALLERID="$var_value" ;;
            agi_calleridname) export AGI_CALLERIDNAME="$var_value" ;;
            agi_extension) export AGI_EXTENSION="$var_value" ;;
            agi_uniqueid) export AGI_UNIQUEID="$var_value" ;;
            agi_context) export AGI_CONTEXT="$var_value" ;;
            agi_channel) export AGI_CHANNEL="$var_value" ;;
        esac
    done
}

# Function to send AGI command
agi_command() {
    echo "$1"
    read response
    echo "$(date '+%Y-%m-%d %H:%M:%S') - AGI Response: $response" >> "$LOG_FILE"
}

set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

handle_response() {
    RESPONSE="$1"
    
    # Check for simple text response (non-JSON) or JSON error
    if echo "$RESPONSE" | grep -q "\"message\":\""; then
         log_message "n8n response: $RESPONSE"
    fi

    # Parse response
    AUDIO_URL=$(echo "$RESPONSE" | jq -r '.audio_url // empty' 2>/dev/null)
    TEXT_RESPONSE=$(echo "$RESPONSE" | jq -r '.text_response // empty' 2>/dev/null)
    HANGUP_FLAG=$(echo "$RESPONSE" | jq -r '.hangup // empty' 2>/dev/null)
    
    # Generate unique filename for response
    # Use EPOCH + RANDOM to avoid collisions in fast loops
    RESP_FILENAME="response_$(date +%s)_$RANDOM"
    RESP_WAV="${SOUNDS_DIR}/${RESP_FILENAME}.wav"

    if [ "$HANGUP_FLAG" == "true" ]; then
        set_variable "AGI_STATUS" "HANGUP"
        return
    fi
    
    if [ -n "$AUDIO_URL" ]; then
        log_message "Downloading audio from: $AUDIO_URL"
        curl -s -o "$RESP_WAV" "$AUDIO_URL"
        
        if [ -f "$RESP_WAV" ]; then
            # Ensure it's correct format (convert if needed, but assuming n8n returns wav or compatible)
            # If n8n returns mp3, convert it
            FILE_TYPE=$(file -b --mime-type "$RESP_WAV")
            if [[ "$FILE_TYPE" == "audio/mpeg" ]]; then
                 mv "$RESP_WAV" "${RESP_WAV}.mp3"
                 sox "${RESP_WAV}.mp3" -r 8000 -c 1 "$RESP_WAV"
                 rm "${RESP_WAV}.mp3"
            elif [[ "$FILE_TYPE" == "audio/x-wav" ]]; then
                 # Ensure 8k mono
                 mv "$RESP_WAV" "${RESP_WAV}.tmp.wav"
                 sox "${RESP_WAV}.tmp.wav" -r 8000 -c 1 "$RESP_WAV"
                 rm "${RESP_WAV}.tmp.wav"
            fi
            
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}" # No extension for Playback
            set_variable "AGI_STATUS" "SUCCESS"
        else
            log_message "ERROR: Failed to download audio"
            set_variable "AGI_STATUS" "ERROR"
        fi

    elif [ -n "$TEXT_RESPONSE" ]; then
        log_message "Generating TTS for: $TEXT_RESPONSE"
        
        TTS_PAYLOAD="{\"model\":\"tts-1\",\"input\":\"$TEXT_RESPONSE\",\"voice\":\"alloy\",\"response_format\":\"mp3\"}"
        TTS_AUDIO="${SOUNDS_DIR}/${RESP_FILENAME}_temp.mp3"
        
        curl -s -X POST -H "Content-Type: application/json" -d "$TTS_PAYLOAD" --max-time $TIMEOUT -o "$TTS_AUDIO" "$TTS_SERVICE_URL"
        
        if [ -f "$TTS_AUDIO" ] && [ -s "$TTS_AUDIO" ]; then
            sox "$TTS_AUDIO" -r 8000 -c 1 "$RESP_WAV" 2>/dev/null
            rm -f "$TTS_AUDIO"
            
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            log_message "ERROR: TTS generation failed"
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
    else
        log_message "WARNING: No audio or text response. Response was: $RESPONSE"
        set_variable "AGI_STATUS" "NO_RESPONSE"
    fi
}

main() {
    log_message "=== AGI Connector Started (Mode: $CMD_MODE) ==="
    read_agi_vars
    
    # Common Metadata
    JSON_META="\"caller_id\": \"${AGI_CALLERID}\", \"unique_id\": \"${AGI_UNIQUEID}\", \"mode\": \"$CMD_MODE\""
    
    RESPONSE=""

    if [ "$CMD_MODE" == "process_input" ]; then
        if [ -f "$RECORDING_FILE" ]; then
            log_message "Uploading recording: $RECORDING_FILE"
            
            # Send file via multipart/form-data
            # Note: n8n webhook must separate binary and json fields if confusing, or put meta in query/header
            # Easiest: Send file as 'file', meta as JSON string in 'data' field
            
            RESPONSE=$(curl -s -X POST \
                -H "Content-Type: multipart/form-data" \
                -F "file=@${RECORDING_FILE}" \
                -F "caller_id=${AGI_CALLERID}" \
                -F "unique_id=${AGI_UNIQUEID}" \
                -F "mode=process_input" \
                --max-time $TIMEOUT \
                "$N8N_WEBHOOK_URL")
        else
            log_message "ERROR: Recording file not found: $RECORDING_FILE"
            set_variable "AGI_STATUS" "ERROR"
            return
        fi
    else
        # Welcome / Metadata only mode
        log_message "Sending metadata to n8n..."
        PAYLOAD="{ $JSON_META }"
        
        RESPONSE=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" \
            --max-time $TIMEOUT \
            "$N8N_WEBHOOK_URL")
    fi
    
    handle_response "$RESPONSE"
    log_message "=== Finished ==="
}

main
