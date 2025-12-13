#!/bin/bash
# =============================================================================
# AGI Connector Script - Local Free AI Stack
# =============================================================================
# Customizable AI phone assistant using:
# - Edge-TTS (Text-to-Speech)
# - Whisper (Speech-to-Text)
# - Ollama/Llama (AI Responses)
# 
# Location: /var/lib/asterisk/agi-bin/agi-connector.sh
# =============================================================================

# Load environment config if exists
[ -f /etc/asterisk/ai.env ] && source /etc/asterisk/ai.env

# ---------------------------------------------------------------------------
# CONFIGURATION (with defaults)
# ---------------------------------------------------------------------------
# Service URLs
STT_SERVICE_URL="${STT_SERVICE_URL:-http://localhost:5051/transcribe}"
LLM_SERVICE_URL="${LLM_SERVICE_URL:-http://localhost:11434/api/generate}"
TTS_SERVICE_URL="${TTS_SERVICE_URL:-http://localhost:5050/v1/audio/speech}"

# LLM Settings
LLM_MODEL="${LLM_MODEL:-llama3.2:1b}"
LLM_MAX_TOKENS="${LLM_MAX_TOKENS:-100}"

# AI Personality (CUSTOMIZABLE!)
AI_NAME="${AI_NAME:-Alex}"
AI_SYSTEM_PROMPT="${AI_SYSTEM_PROMPT:-You are a friendly and helpful AI phone assistant named $AI_NAME. Keep responses brief (under 50 words) and conversational. Be warm and professional.}"
AI_WELCOME_MESSAGE="${AI_WELCOME_MESSAGE:-Hello! I'm $AI_NAME, your AI assistant. How can I help you today?}"
AI_GOODBYE_MESSAGE="${AI_GOODBYE_MESSAGE:-Thank you for calling! Have a wonderful day. Goodbye!}"
AI_FALLBACK_MESSAGE="${AI_FALLBACK_MESSAGE:-I'm sorry, I didn't quite catch that. Could you please repeat?}"

# TTS Settings
TTS_VOICE="${TTS_VOICE:-alloy}"

# Paths
SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
LOG_FILE="/var/log/asterisk/agi-connector.log"
TIMEOUT=30

# Commands from Asterisk
CMD_MODE="${1:-welcome}"
RECORDING_FILE="$2"

# ---------------------------------------------------------------------------
# FUNCTIONS
# ---------------------------------------------------------------------------

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$SOUNDS_DIR"

# Read AGI variables from Asterisk
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

# Send AGI command to Asterisk
agi_command() {
    echo "$1"
    read response
    echo "$(date '+%Y-%m-%d %H:%M:%S') - AGI: $response" >> "$LOG_FILE"
}

# Set Asterisk channel variable
set_variable() {
    agi_command "SET VARIABLE $1 \"$2\""
}

# Log message
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Generate TTS audio using Edge-TTS
generate_tts() {
    local text="$1"
    local output_file="$2"
    
    log_message "TTS: $text"
    
    # Call Edge-TTS service
    TTS_PAYLOAD="{\"model\":\"tts-1\",\"input\":\"$text\",\"voice\":\"$TTS_VOICE\",\"response_format\":\"mp3\"}"
    TTS_TEMP="${output_file}.mp3"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$TTS_PAYLOAD" \
        --max-time $TIMEOUT \
        -o "$TTS_TEMP" \
        "$TTS_SERVICE_URL"
    
    if [ -f "$TTS_TEMP" ] && [ -s "$TTS_TEMP" ]; then
        # Convert to WAV (8kHz mono for telephony)
        sox "$TTS_TEMP" -r 8000 -c 1 "$output_file" 2>/dev/null
        rm -f "$TTS_TEMP"
        return 0
    else
        log_message "ERROR: TTS failed"
        return 1
    fi
}

# Transcribe audio using Whisper
transcribe_audio() {
    local audio_file="$1"
    
    log_message "STT: $audio_file"
    
    RESPONSE=$(curl -s -X POST \
        -F "file=@${audio_file}" \
        --max-time $TIMEOUT \
        "$STT_SERVICE_URL")
    
    TEXT=$(echo "$RESPONSE" | jq -r '.text // empty' 2>/dev/null)
    
    if [ -n "$TEXT" ] && [ "$TEXT" != "" ]; then
        log_message "Heard: $TEXT"
        echo "$TEXT"
        return 0
    else
        log_message "STT returned empty"
        return 1
    fi
}

# Get AI response using Ollama
get_ai_response() {
    local user_text="$1"
    
    log_message "User: $user_text"
    
    # Build prompt with system context
    PROMPT="$AI_SYSTEM_PROMPT\n\nUser: $user_text\nAssistant:"
    
    # Call Ollama
    PAYLOAD=$(jq -n \
        --arg model "$LLM_MODEL" \
        --arg prompt "$PROMPT" \
        --argjson num_predict "${LLM_MAX_TOKENS}" \
        '{model: $model, prompt: $prompt, stream: false, options: {num_predict: $num_predict}}')
    
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time $TIMEOUT \
        "$LLM_SERVICE_URL")
    
    AI_TEXT=$(echo "$RESPONSE" | jq -r '.response // empty' 2>/dev/null)
    
    if [ -n "$AI_TEXT" ]; then
        # Clean up response (remove extra whitespace)
        AI_TEXT=$(echo "$AI_TEXT" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ //;s/ $//')
        log_message "AI: $AI_TEXT"
        echo "$AI_TEXT"
        return 0
    else
        log_message "LLM failed: $RESPONSE"
        echo "$AI_FALLBACK_MESSAGE"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------------------
main() {
    log_message "=== AGI Started (Mode: $CMD_MODE) ==="
    read_agi_vars
    
    # Generate unique filename for response audio
    RESP_FILENAME="response_$(date +%s)_$RANDOM"
    RESP_WAV="${SOUNDS_DIR}/${RESP_FILENAME}.wav"
    
    case "$CMD_MODE" in
        welcome)
            # Play welcome message
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
            
            # Step 1: Transcribe audio
            USER_TEXT=$(transcribe_audio "$RECORDING_FILE")
            
            if [ -z "$USER_TEXT" ]; then
                # Failed to transcribe - ask to repeat
                if generate_tts "$AI_FALLBACK_MESSAGE" "$RESP_WAV"; then
                    set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
                    set_variable "AGI_STATUS" "SUCCESS"
                else
                    set_variable "AGI_STATUS" "TTS_ERROR"
                fi
                rm -f "$RECORDING_FILE"
                exit 0
            fi
            
            # Check for hangup keywords
            if echo "$USER_TEXT" | grep -iqE "goodbye|bye|hang up|end call|that's all|thank you.*bye"; then
                if generate_tts "$AI_GOODBYE_MESSAGE" "$RESP_WAV"; then
                    set_variable "SOUND_FILE" "${SOUNDS_DIR}/${RESP_FILENAME}"
                    set_variable "AGI_STATUS" "HANGUP"
                else
                    set_variable "AGI_STATUS" "HANGUP"
                fi
                rm -f "$RECORDING_FILE"
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
            ;;
            
        *)
            log_message "Unknown mode: $CMD_MODE"
            set_variable "AGI_STATUS" "ERROR"
            ;;
    esac
    
    log_message "=== AGI Finished ==="
}

main
