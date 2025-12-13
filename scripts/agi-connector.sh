#!/bin/bash
# =============================================================================
# AGI Connector Script - Local Free AI Stack
# =============================================================================
# Uses: Edge-TTS (TTS), faster-whisper (STT), Ollama (LLM)
# Location: /var/lib/asterisk/agi-bin/agi-connector.sh
# =============================================================================

# Configuration - All Local Services
STT_SERVICE_URL="${STT_SERVICE_URL:-http://localhost:5051/transcribe}"
LLM_SERVICE_URL="${LLM_SERVICE_URL:-http://localhost:11434/api/generate}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"
LLM_MODEL="${LLM_MODEL:-llama3.2:1b}"

SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

# Commands
CMD_MODE="${1:-welcome}"
RECORDING_FILE="$2"

# System prompt for the AI
SYSTEM_PROMPT="You are a helpful AI phone assistant. Keep responses brief and conversational, under 50 words. Be friendly and helpful."

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$SOUNDS_DIR"

# Function to read AGI variables
read_agi_vars() {
    while read line; do
        [ -z "$line" ] && break
        var_name=$(echo "$line" | cut -d: -f1)
        var_value=$(echo "$line" | cut -d: -f2- | sed 's/^ //')
        
        case "$var_name" in
            agi_callerid) export AGI_CALLERID="$var_value" ;;
            agi_uniqueid) export AGI_UNIQUEID="$var_value" ;;
        esac
    done
}

# Function to send AGI command
agi_command() {
    echo "$1"
    read response
    echo "$(date '+%Y-%m-%d %H:%M:%S') - AGI: $response" >> "$LOG_FILE"
}

set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Generate TTS audio using Edge-TTS
generate_tts() {
    local text="$1"
    local output_file="$2"
    
    log_message "Generating TTS: $text"
    
    # Call Edge-TTS service
    TTS_PAYLOAD="{\"model\":\"tts-1\",\"input\":\"$text\",\"voice\":\"alloy\",\"response_format\":\"mp3\"}"
    TTS_TEMP="${output_file}.mp3"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$TTS_PAYLOAD" \
        --max-time $TIMEOUT \
        -o "$TTS_TEMP" \
        "$TTS_SERVICE_URL"
    
    if [ -f "$TTS_TEMP" ] && [ -s "$TTS_TEMP" ]; then
        # Convert MP3 to WAV (8kHz mono for telephony)
        sox "$TTS_TEMP" -r 8000 -c 1 "$output_file" 2>/dev/null
        rm -f "$TTS_TEMP"
        return 0
    else
        log_message "ERROR: TTS generation failed"
        return 1
    fi
}

# Transcribe audio using Whisper
transcribe_audio() {
    local audio_file="$1"
    
    log_message "Transcribing: $audio_file"
    
    RESPONSE=$(curl -s -X POST \
        -F "file=@${audio_file}" \
        --max-time $TIMEOUT \
        "$STT_SERVICE_URL")
    
    TEXT=$(echo "$RESPONSE" | jq -r '.text // empty' 2>/dev/null)
    
    if [ -n "$TEXT" ]; then
        log_message "Transcribed: $TEXT"
        echo "$TEXT"
        return 0
    else
        log_message "ERROR: Transcription failed - $RESPONSE"
        return 1
    fi
}

# Get AI response using Ollama
get_ai_response() {
    local user_text="$1"
    
    log_message "Getting AI response for: $user_text"
    
    # Build the prompt with system context
    PROMPT="$SYSTEM_PROMPT\n\nUser: $user_text\nAssistant:"
    
    # Call Ollama
    PAYLOAD=$(jq -n \
        --arg model "$LLM_MODEL" \
        --arg prompt "$PROMPT" \
        '{model: $model, prompt: $prompt, stream: false}')
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time $TIMEOUT \
        "$LLM_SERVICE_URL")
    
    AI_TEXT=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    
    if [ -n "$AI_TEXT" ]; then
        log_message "AI Response: $AI_TEXT"
        echo "$AI_TEXT"
        return 0
    else
        log_message "ERROR: LLM failed - $RESPONSE"
        echo "I'm sorry, I couldn't process that. Could you please repeat?"
        return 1
    fi
}

main() {
    log_message "=== AGI Connector Started (Mode: $CMD_MODE) ==="
    read_agi_vars
    
    # Generate unique filename
    RESP_FILENAME="response_$(date +%s)_$RANDOM"
    RESP_WAV="${SOUNDS_DIR}/${RESP_FILENAME}.wav"
    
    if [ "$CMD_MODE" == "welcome" ]; then
        # Generate welcome message
        WELCOME_TEXT="Hello! I'm your AI assistant. How can I help you today?"
        
        if generate_tts "$WELCOME_TEXT" "$RESP_WAV"; then
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
        
    elif [ "$CMD_MODE" == "process_input" ]; then
        if [ ! -f "$RECORDING_FILE" ]; then
            log_message "ERROR: Recording file not found: $RECORDING_FILE"
            set_variable "AGI_STATUS" "ERROR"
            exit 1
        fi
        
        # Step 1: Transcribe audio
        USER_TEXT=$(transcribe_audio "$RECORDING_FILE")
        
        if [ -z "$USER_TEXT" ]; then
            # Handle silence or failed transcription
            FALLBACK_TEXT="I didn't catch that. Could you please speak again?"
            if generate_tts "$FALLBACK_TEXT" "$RESP_WAV"; then
                set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
                set_variable "AGI_STATUS" "SUCCESS"
            else
                set_variable "AGI_STATUS" "TTS_ERROR"
            fi
            exit 0
        fi
        
        # Check for goodbye/hangup keywords
        if echo "$USER_TEXT" | grep -iqE "goodbye|bye|hang up|end call|that's all"; then
            GOODBYE_TEXT="Goodbye! Have a great day!"
            generate_tts "$GOODBYE_TEXT" "$RESP_WAV"
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "HANGUP"
            exit 0
        fi
        
        # Step 2: Get AI response
        AI_RESPONSE=$(get_ai_response "$USER_TEXT")
        
        # Step 3: Generate TTS
        if generate_tts "$AI_RESPONSE" "$RESP_WAV"; then
            set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
            set_variable "AGI_STATUS" "SUCCESS"
        else
            set_variable "AGI_STATUS" "TTS_ERROR"
        fi
        
        # Cleanup recording
        rm -f "$RECORDING_FILE"
    fi
    
    log_message "=== Finished ==="
}

main
