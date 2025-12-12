# Telephony Service Setup - Task Tracker

## Phase 1: VM and Asterisk Setup
- [x] 1.1 Install system prerequisites and dependencies
- [x] 1.2 Download and compile Asterisk for ARM64
- [x] 1.3 Install Asterisk configuration samples and systemd service

## Phase 2: Telephony and Service Integration
- [x] 2.1 Configure Asterisk (PJSIP, extensions, modules)
- [x] 2.2 Set up openai-edge-tts service (Docker)
- [x] 2.3 Verify n8n is accessible and configure webhook

## Phase 3: Real-Time Communication Bridge
- [x] 3.1 Create AGI connector script
- [x] 3.2 Configure dialplan for incoming calls
- [x] 3.3 Set up n8n workflow for TTS integration
- [ ] 3.4 Test end-to-end call flow (requires SIP trunk)

## Documentation
- [x] Create setup documentation
- [x] Document firewall/networking requirements

---

## Summary

All components are installed and configured:

| Component | Status | Details |
|-----------|--------|---------|
| Asterisk 22.7.0 | ✅ Running | Compiled for ARM64, systemd service active |
| PJSIP Transport | ✅ Configured | UDP/5060, NAT settings applied |
| TTS Service | ✅ Running | Edge-TTS on Docker, port 5050 |
| AGI Script | ✅ Installed | `/var/lib/asterisk/agi-bin/agi-connector.sh` |
| Custom Sounds | ✅ Generated | welcome.wav, goodbye.wav, sorry.wav |
| n8n | ✅ Accessible | https://n8n.shravanpandala.me |

## Next Steps

1. **Configure SIP Trunk**: Update `/etc/asterisk/pjsip.conf` with your provider credentials
2. **Import n8n Workflow**: Use `configs/n8n-workflow-template.json`
3. **Open Firewall Ports**: UDP 5060, 10000-20000 in Oracle Cloud NSG
4. **Test Calls**: Make a test call to your DID number
