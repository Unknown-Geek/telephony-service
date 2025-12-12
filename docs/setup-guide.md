# Telephony Service Setup Guide

This guide covers the complete setup of the Asterisk + n8n + TTS telephony service on your Oracle ARM64 VM.

## 📋 System Requirements Met

| Requirement | Status |
|------------|--------|
| Ubuntu 22.04 LTS (ARM64) | ✅ Installed |
| Docker | ✅ v28.4.0 |
| Asterisk | ✅ v22.7.0 |
| n8n | ✅ Running at https://n8n.shravanpandala.me |
| TTS Service | ✅ Edge-TTS on port 5050 |

## 🔧 Service Status Commands

```bash
# Check Asterisk status
sudo systemctl status asterisk

# View Asterisk CLI
sudo asterisk -rvvv

# Check TTS container
docker ps --filter name=telephony-tts

# Test TTS API
curl -s http://localhost:5050/health
```

## 🌐 Firewall Configuration

Open these ports in your Oracle Cloud Network Security Group:

| Port | Protocol | Source | Description |
|------|----------|--------|-------------|
| 5060 | UDP | 0.0.0.0/0 | SIP Signaling |
| 5061 | UDP | 0.0.0.0/0 | SIP TLS (optional) |
| 10000-20000 | UDP | 0.0.0.0/0 | RTP Media (Voice) |
| 5050 | TCP | 127.0.0.1 | TTS Service (internal only) |

## 📞 SIP Trunk Configuration

### Step 1: Choose a SIP Provider

Popular options:
- [Twilio](https://www.twilio.com/sip-trunking)
- [Vonage](https://www.vonage.com/communications-apis/sip-trunking/)
- [Telnyx](https://telnyx.com/products/sip-trunking)
- [SignalWire](https://signalwire.com/)

### Step 2: Update PJSIP Configuration

Edit `/etc/asterisk/pjsip.conf` and replace the placeholder values:

```ini
[sip-trunk-provider]
type=registration
server_uri=sip:YOUR_PROVIDER_SERVER    ; e.g., sip:sip.twilio.com
client_uri=sip:YOUR_USERNAME@YOUR_PROVIDER_SERVER

[sip-trunk-auth]
type=auth
username=YOUR_USERNAME
password=YOUR_PASSWORD

[sip-trunk-identify]
type=identify
match=YOUR_PROVIDER_IP   ; e.g., 54.171.127.192
```

### Step 3: Reload Asterisk

```bash
sudo asterisk -rx "pjsip reload"
sudo asterisk -rx "dialplan reload"
```

## 🤖 n8n Webhook Setup

### Step 1: Create the Webhook Workflow

1. Open n8n at https://n8n.shravanpandala.me
2. Create a new workflow
3. Add a **Webhook** trigger node:
   - HTTP Method: POST
   - Path: `asterisk-call`
   - The webhook URL will be: `https://n8n.shravanpandala.me/webhook/asterisk-call`

### Step 2: Add LLM Processing

Add an HTTP Request node to call your LLM:
- Method: POST
- URL: Your LLM endpoint (OpenAI, Ollama, etc.)
- Body:
  ```json
  {
    "messages": [
      {"role": "system", "content": "You are a helpful phone assistant."},
      {"role": "user", "content": "{{ $json.caller_id }} called. Respond briefly."}
    ]
  }
  ```

### Step 3: Generate TTS Response

Add another HTTP Request node for TTS:
- Method: POST  
- URL: `http://localhost:5050/v1/tts/generate`
- Body:
  ```json
  {
    "input": "{{ $json.response }}",
    "unique_id": "{{ $json.unique_id }}",
    "voice": "alloy"
  }
  ```

### Step 4: Return Response

Add a **Respond to Webhook** node:
```json
{
  "text_response": "{{ $json.llm_response }}",
  "audio_file": "{{ $json.audio_file }}"
}
```

## 🧪 Testing

### Test Asterisk

```bash
# Check PJSIP status
sudo asterisk -rx "pjsip show endpoints"
sudo asterisk -rx "pjsip show transports"

# Check dialplan
sudo asterisk -rx "dialplan show from-sip-provider"
```

### Test TTS Service

```bash
# Test health
curl http://localhost:5050/health

# Test speech generation
curl -X POST http://localhost:5050/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input":"Hello world", "voice":"alloy"}' \
  -o test.mp3
```

### Test AGI Script

```bash
# Test AGI script manually
sudo -u asterisk /var/lib/asterisk/agi-bin/agi-connector.sh
```

## 🔄 Managing Services

```bash
# Restart Asterisk
sudo systemctl restart asterisk

# Restart TTS Service
cd "/home/ubuntu/Telephony Service"
docker compose restart

# View logs
sudo tail -f /var/log/asterisk/full
docker logs -f telephony-tts
```

## 📁 File Locations

| Component | Location |
|-----------|----------|
| Asterisk configs | `/etc/asterisk/` |
| Custom sounds | `/var/lib/asterisk/sounds/custom/` |
| AGI scripts | `/var/lib/asterisk/agi-bin/` |
| Asterisk logs | `/var/log/asterisk/` |
| TTS container | `telephony-tts` |
| Project files | `/home/ubuntu/Telephony Service/` |

## ⚠️ Troubleshooting

### Asterisk won't start
```bash
sudo asterisk -cvvvvv   # Start in foreground with verbose output
```

### No audio on calls
- Check RTP port range is open (10000-20000 UDP)
- Verify `external_media_address` in pjsip.conf matches public IP
- Check `direct_media=no` is set

### TTS not working
```bash
docker logs telephony-tts
curl -v http://localhost:5050/health
```

### n8n webhook not responding
- Check n8n container is running
- Verify webhook is active in n8n workflow
- Check nginx proxy configuration
