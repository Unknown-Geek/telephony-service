# Telephony Service - Implementation Walkthrough

## Overview

This document summarizes the implementation of an Asterisk-based telephony service integrated with n8n and TTS on an Oracle ARM64 VM.

## What Was Accomplished

### Phase 1: Asterisk Setup ✅

1. **Installed prerequisites** - Build tools, development libraries, and dependencies for ARM64 compilation
2. **Compiled Asterisk 22.7.0** - Built from source with optimizations for aarch64 architecture
3. **Configured systemd service** - Asterisk runs automatically on system startup

### Phase 2: Service Integration ✅

1. **PJSIP Configuration** - Configured SIP transport with NAT handling for Oracle Cloud
2. **TTS Service** - Deployed Edge-TTS in Docker container on port 5050
3. **n8n Verification** - Confirmed n8n is accessible at https://n8n.shravanpandala.me

### Phase 3: Communication Bridge ✅

1. **AGI Script** - Created `agi-connector.sh` to bridge Asterisk → n8n → TTS
2. **Dialplan** - Configured `extensions.conf` for incoming call handling
3. **n8n Workflow Template** - Created importable workflow for LLM + TTS processing

## Service Status

| Service | Status | Port |
|---------|--------|------|
| Asterisk 22.7.0 | ✅ Running | 5060 (SIP), 10000-20000 (RTP) |
| TTS (Edge-TTS) | ✅ Running | 5050 (localhost only) |
| n8n | ✅ Running | 5678 via nginx proxy |

## Files Created

```
/home/ubuntu/Telephony Service/
├── configs/
│   ├── pjsip.conf                 # PJSIP transport & trunk config
│   ├── extensions.conf            # Dialplan
│   ├── modules.conf               # Module loading
│   └── n8n-workflow-template.json # n8n workflow to import
├── scripts/
│   ├── agi-connector.sh           # AGI bridge script
│   └── tts-server.py              # TTS API server
├── sounds/
│   ├── welcome.wav                # Greeting audio
│   ├── sorry.wav                  # Error audio
│   └── goodbye.wav                # Farewell audio
├── docs/
│   ├── implementation_plan.md     # Original plan
│   └── setup-guide.md             # Setup instructions
├── docker-compose.yml             # TTS container
└── task.md                        # Progress tracker
```

## Remaining User Actions

1. **Configure SIP Trunk**
   - Sign up with a SIP provider (Twilio, Telnyx, etc.)
   - Update `/etc/asterisk/pjsip.conf` with credentials
   - Run `sudo asterisk -rx "pjsip reload"`

2. **Open Firewall Ports**
   - Add ingress rules in Oracle Cloud NSG
   - UDP 5060-5061 (SIP)
   - UDP 10000-20000 (RTP)

3. **Import n8n Workflow**
   - Open n8n dashboard
   - Import `configs/n8n-workflow-template.json`
   - Configure OpenAI/LLM credentials
   - Activate the workflow

4. **Test End-to-End**
   - Call your DID number
   - Verify audio playback works
   - Check logs for any issues

## Verification Commands

```bash
# Check all services
sudo systemctl status asterisk
docker ps --filter name=telephony-tts

# View Asterisk CLI
sudo asterisk -rvvv

# Test TTS
curl -X POST http://localhost:5050/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input":"Test message","voice":"alloy"}' \
  -o test.mp3 && play test.mp3

# Check PJSIP endpoints
sudo asterisk -rx "pjsip show endpoints"
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Phone Call    │────▶│    Asterisk     │────▶│   AGI Script    │
│   (SIP Trunk)   │     │   (Port 5060)   │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│ Audio Playback  │◀────│   TTS Service   │◀────│   n8n Webhook   │
│   (Asterisk)    │     │   (Port 5050)   │     │  (LLM + TTS)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Notes

- All existing services (Dreamstime bot, n8n, WhatsApp webhook) remain unaffected
- TTS container runs on isolated Docker network
- No system restarts were required
- All changes pushed to GitHub: https://github.com/Unknown-Geek/telephony-service
