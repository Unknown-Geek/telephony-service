#!/bin/bash
# AGI Connector Script - Local Free AI Stack

# Load config
if [ -f /etc/asterisk/ai.env ]; then
    source /etc/asterisk/ai.env
fi

# Configuration with defaults
STT_SERVICE_URL="${STT_SERVICE_URL:-http://localhost:5051/transcribe}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"

# Groq API (fast cloud LLM - FREE tier: 30 req/min, 14400 req/day)
GROQ_API_KEY="${GROQ_API_KEY:-}"
LLM_MODEL="${LLM_MODEL:-llama-3.3-70b-versatile}"
LLM_MAX_TOKENS="${LLM_MAX_TOKENS:-100}"
AI_NAME="${AI_NAME:-Alex}"
AI_WELCOME_MESSAGE="${AI_WELCOME_MESSAGE:-Hello! I am $AI_NAME, your AI assistant. How can I help you today?}"
AI_GOODBYE_MESSAGE="${AI_GOODBYE_MESSAGE:-Thank you for calling! Have a wonderful day. Goodbye!}"
AI_FALLBACK_MESSAGE="${AI_FALLBACK_MESSAGE:-I am sorry, I did not quite catch that. Could you please repeat?}"
AI_SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-You are a friendly AI phone assistant named $AI_NAME. Keep responses brief under 50 words. Be warm and professional.}"
TTS_VOICE="${TTS_VOICE:-alloy}"
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

CMD_MODE="${1:-welcome}"
RECORDING_FILE="$2"

# Create directories
mkdir -p "$SOUNDS_DIR" 2>/dev/null
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

agi_command() {
    echo "$1"
    read response
}

set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

read_agi_vars() {
    while read line; do
        [ -z "$line" ] && break
        case "$line" in
            agi_callerid:*) AGI_CALLERID="${line#*: }" ;;
            agi_uniqueid:*) AGI_UNIQUEID="${line#*: }" ;;
        esac
    done
}

generate_tts() {
    local text="$1"
    local output_file="$2"
    local TTS_TEMP="${output_file}.mp3"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"tts-1\",\"input\":\"$text\",\"voice\":\"$TTS_VOICE\",\"response_format\":\"mp3\"}" \
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

transcribe_audio() {
    local audio_file="$1"
    local RESPONSE
    
    RESPONSE=$(curl -s -X POST -F "file=@${audio_file}" --max-time $TIMEOUT "$STT_SERVICE_URL")
    echo "$RESPONSE" | jq -r '.text // empty' 2>/dev/null
}

get_ai_response() {
    local user_text="$1"
    local RESPONSE
    local AI_TEXT
    
    # Use Groq API (much faster than local Ollama)
    RESPONSE=$(curl -s -X POST "https://api.groq.com/openai/v1/chat/completions" \
        -H "Authorization: Bearer $GROQ_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"$LLM_MODEL\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"$AI_SYSTEM_PROMPT\"},
                {\"role\": \"user\", \"content\": \"$user_text\"}
            ],
            \"max_tokens\": $LLM_MAX_TOKENS,
            \"temperature\": 0.7
        }" \
        --max-time $TIMEOUT)
    
    AI_TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    
    if [ -n "$AI_TEXT" ]; then
        echo "$AI_TEXT" | tr '\n' ' ' | sed 's/  */ /g'
    else
        log_message "Groq error: $RESPONSE"
        echo "$AI_FALLBACK_MESSAGE"
    fi
}

# Main
read_agi_vars
log_message "=== AGI Started (Mode: $CMD_MODE) ==="

RESP_FILENAME="response_$(date +%s)_$RANDOM"
RESP_WAV="${SOUNDS_DIR}/${RESP_FILENAME}.wav"

case "$CMD_MODE" in
    welcome)
        log_message "Generating welcome TTS"
        if generate_tts "$AI_WELCOME_MESSAGE" "$RESP_WAV"; then
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
        log_message "Heard: $USER_TEXT"
        
        if [ -z "$USER_TEXT" ]; then
            generate_tts "$AI_FALLBACK_MESSAGE" "$RESP_WAV"
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
            rm -f "$RECORDING_FILE"
            exit 0
        fi
        
        # Check for goodbye
        if echo "$USER_TEXT" | grep -iqE "goodbye|bye|hang up|end call"; then
            generate_tts "$AI_GOODBYE_MESSAGE" "$RESP_WAV"
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "HANGUP"
            rm -f "$RECORDING_FILE"
            exit 0
        fi
        
        AI_RESPONSE=$(get_ai_response "$USER_TEXT")
        log_message "AI: $AI_RESPONSE"
        
        if generate_tts "$AI_RESPONSE" "$RESP_WAV"; then
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
        
        rm -f "$RECORDING_FILE"
        ;;
esac

log_message "=== AGI Finished ==="
