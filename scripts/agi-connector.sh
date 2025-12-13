#!/bin/bash
# =============================================================================
# AGI Connector Script - Script-Based Calls with Conversation Recording
# =============================================================================
# Supports:
# - Custom script narration (from API)
# - AI-powered conversation via n8n webhook
# - Full conversation recording with callback
# =============================================================================

# Load config
if [ -f /etc/asterisk/ai.env ]; then
    source /etc/asterisk/ai.env
fi

# Configuration
STT_SERVICE_URL="${STT_SERVICE_URL:-http://localhost:5051/transcribe}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-https://n8n.shravanpandala.me/webhook-test/phone-agent}"

# AI Personality (fallback if n8n fails)
AI_NAME="${AI_NAME:-Alex}"
AI_FALLBACK_MESSAGE="${AI_FALLBACK_MESSAGE:-I'm sorry, I didn't quite catch that. Could you please repeat?}"
AI_GOODBYE_MESSAGE="${AI_GOODBYE_MESSAGE:-Thank you for calling! Goodbye!}"

# Paths
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
CONV_DIR="/var/lib/asterisk/conversations"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

# Commands from Asterisk
CMD_MODE="${1:-welcome}"
RECORDING_FILE="$2"

# Create directories
mkdir -p "$SOUNDS_DIR" 2>/dev/null
mkdir -p "$CONV_DIR" 2>/dev/null
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

# Logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# AGI commands
agi_command() {
    echo "$1"
    read response
}

set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

get_variable() {
    echo "GET VARIABLE $1"
    read response
    echo "$response" | grep -oP '(?<=\().*(?=\))' | sed 's/^1 //'
}

# Read AGI environment
read_agi_vars() {
    while read line; do
        [ -z "$line" ] && break
        case "$line" in
            agi_callerid:*) AGI_CALLERID="${line#*: }" ;;
            agi_uniqueid:*) AGI_UNIQUEID="${line#*: }" ;;
        esac
    done
}

# Add to conversation log
add_to_conversation() {
    local role="$1"
    local text="$2"
    local session_file="$CONV_DIR/${SESSION_ID}.json"
    
    if [ -f "$session_file" ]; then
        # Append to conversation array using jq
        local temp_file=$(mktemp)
        jq --arg role "$role" --arg text "$text" --arg time "$(date -Iseconds)" \
            '.conversation += [{"role": $role, "text": $text, "timestamp": $time}]' \
            "$session_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$session_file"
    fi
}

# Send conversation to callback URL
send_callback() {
    local session_file="$CONV_DIR/${SESSION_ID}.json"
    
    if [ -n "$CALLBACK_URL" ] && [ -f "$session_file" ]; then
        log_message "Sending conversation to callback: $CALLBACK_URL"
        
        # Update end time
        local temp_file=$(mktemp)
        jq --arg endTime "$(date -Iseconds)" '.endTime = $endTime | .status = "completed"' \
            "$session_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$session_file"
        
        # POST to callback URL
        curl -s -X POST "$CALLBACK_URL" \
            -H "Content-Type: application/json" \
            -d @"$session_file" \
            --max-time 10 > /dev/null 2>&1
        
        log_message "Callback sent"
    fi
}

# Generate TTS
generate_tts() {
    local text="$1"
    local output_file="$2"
    local TTS_TEMP="${output_file}.mp3"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"tts-1\",\"input\":\"$text\",\"voice\":\"${TTS_VOICE:-alloy}\",\"response_format\":\"mp3\"}" \
        --max-time $TIMEOUT \
        -o "$TTS_TEMP" \
        "$TTS_SERVICE_URL"
    
    if [ -f "$TTS_TEMP" ] && [ -s "$TTS_TEMP" ]; then
        sox "$TTS_TEMP" -r 8000 -c 1 "$output_file" 2>/dev/null
        rm -f "$TTS_TEMP"
        return 0
    fi
    return 1
}

# Transcribe audio
transcribe_audio() {
    local audio_file="$1"
    local RESPONSE=$(curl -s -X POST -F "file=@${audio_file}" --max-time $TIMEOUT "$STT_SERVICE_URL")
    echo "$RESPONSE" | jq -r '.text // empty' 2>/dev/null
}

# Get AI response from n8n
get_ai_response() {
    local user_text="$1"
    local RESPONSE
    local AI_TEXT
    
    RESPONSE=$(curl -s -X POST "$N8N_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"$user_text\",
            \"caller_id\": \"$AGI_CALLERID\",
            \"session_id\": \"$SESSION_ID\"
        }" \
        --max-time $TIMEOUT)
    
    AI_TEXT=$(echo "$RESPONSE" | jq -r '.response // .output // .text // .message // empty' 2>/dev/null)
    
    if [ -z "$AI_TEXT" ]; then
        AI_TEXT=$(echo "$RESPONSE" | head -c 500)
    fi
    
    if [ -n "$AI_TEXT" ] && [ "$AI_TEXT" != "null" ]; then
        echo "$AI_TEXT" | tr '\n' ' ' | sed 's/  */ /g'
    else
        log_message "n8n error: $RESPONSE"
        echo "$AI_FALLBACK_MESSAGE"
    fi
}

# Main execution
read_agi_vars
log_message "=== AGI Started (Mode: $CMD_MODE) ==="

# Get channel variables set by API
SESSION_ID=$(get_variable "SESSION_ID")
CUSTOM_SCRIPT=$(get_variable "SCRIPT")
CALLBACK_URL=$(get_variable "CALLBACK_URL")

# Fallback session ID
if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" = "(null)" ]; then
    SESSION_ID="session_${AGI_UNIQUEID}"
fi

log_message "Session: $SESSION_ID"
log_message "Script: ${CUSTOM_SCRIPT:0:100}..."
log_message "Callback: $CALLBACK_URL"

RESP_FILENAME="response_$(date +%s)_$RANDOM"
RESP_WAV="${SOUNDS_DIR}/${RESP_FILENAME}.wav"

case "$CMD_MODE" in
    welcome)
        # Use custom script if provided, otherwise default welcome
        if [ -n "$CUSTOM_SCRIPT" ] && [ "$CUSTOM_SCRIPT" != "(null)" ]; then
            WELCOME_TEXT="$CUSTOM_SCRIPT"
        else
            WELCOME_TEXT="Hello! I am ${AI_NAME}, your AI assistant. How can I help you today?"
        fi
        
        log_message "Welcome: $WELCOME_TEXT"
        add_to_conversation "assistant" "$WELCOME_TEXT"
        
        if generate_tts "$WELCOME_TEXT" "$RESP_WAV"; then
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
        ;;
        
    process_input)
        if [ ! -f "$RECORDING_FILE" ]; then
            log_message "ERROR: Recording not found: $RECORDING_FILE"
            set_variable "AGI_STATUS" "ERROR"
            exit 1
        fi
        
        USER_TEXT=$(transcribe_audio "$RECORDING_FILE")
        log_message "User: $USER_TEXT"
        add_to_conversation "user" "$USER_TEXT"
        
        if [ -z "$USER_TEXT" ]; then
            generate_tts "$AI_FALLBACK_MESSAGE" "$RESP_WAV"
            add_to_conversation "assistant" "$AI_FALLBACK_MESSAGE"
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
            rm -f "$RECORDING_FILE"
            exit 0
        fi
        
        # Check for goodbye
        if echo "$USER_TEXT" | grep -iqE "goodbye|bye|hang up|end call|that's all"; then
            generate_tts "$AI_GOODBYE_MESSAGE" "$RESP_WAV"
            add_to_conversation "assistant" "$AI_GOODBYE_MESSAGE"
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "HANGUP"
            send_callback
            rm -f "$RECORDING_FILE"
            exit 0
        fi
        
        # Get AI response
        AI_RESPONSE=$(get_ai_response "$USER_TEXT")
        log_message "AI: $AI_RESPONSE"
        add_to_conversation "assistant" "$AI_RESPONSE"
        
        if generate_tts "$AI_RESPONSE" "$RESP_WAV"; then
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
        
        rm -f "$RECORDING_FILE"
        ;;
        
    hangup)
        # Called when call ends
        log_message "Call ended, sending callback..."
        send_callback
        ;;
esac

log_message "=== AGI Finished ==="
