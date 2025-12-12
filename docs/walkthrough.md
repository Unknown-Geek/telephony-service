# Twilio Elastic SIP Trunking Integration
**Date:** December 12, 2025
**Status:** ✅ Complete & Verified

This document details the successful integration of Asterisk with Twilio Elastic SIP Trunking for outbound calls.

## Configuration Summary

### Twilio Console Settings
| Setting | Value |
|---------|-------|
| **Trunk Name** | `Asterisk-SIP-Trunk` |
| **Termination URI** | `asterisk-pbx1.pstn.twilio.com` |
| **Authentication** | IP ACL (`Asterisk-Server`) + Credential List (`Asterisk-Credentials`) |
| **Secure Media** | Disabled (RTP) |
| **PSTN Transfer** | Disabled |

### Asterisk Configuration (`pjsip.conf`)
- **Key Settings:**
  - `contact=sip:asterisk-pbx1.pstn.twilio.com` (PSTN Termination URI)
  - `outbound_auth=twilio-auth` (Credentials: `Asterisk`)
  - `from_domain=asterisk-pbx1.pstn.twilio.com`
  - `from_user=+17756187988` (Required for Caller ID)
  - `callerid="Asterisk PBX" <+17756187988>`

### Dialplan (`extensions.conf`)
- **Outbound Context:**
  - Configured to set Caller ID explicitly for all calls.
  - **Important:** Twilio **requires** a valid Caller ID (purchased or verified number) for all outbound calls.
  - Setting: `Set(CALLERID(num)=+17756187988)`

## Setup Validation

### 1. SIP Connectivity
- **Status:** OPTIONS requests receive `200 OK`
- **Latency:** ~557ms RTT (US1 region)

### 2. Call Flow Verification
- **Test:** Outbound call to Indian mobile number (`+91...`) via `Local` channel
- **Result:**
  - SIP INVITE sent with Authentication headers
  - Twilio responded `183 Session Progress` (Ring)
  - Audio playback confirmed (congratulations message)

### 3. Common Error Codes Encountered & Solved
- **404 Not Found:** Caused by using SIP Domain URI instead of PSTN Termination URI.
  - *Fix:* Changed URI to `asterisk-pbx1.pstn.twilio.com`.
- **403 Forbidden:** Caused by missing IP in Twilio IP ACL.
  - *Fix:* Added server IP to `Asterisk-Server` ACL.
- **403 Caller ID is unauthorized:** Caused by missing/invalid Caller ID header.
  - *Fix:* Set `from_user` and `callerid` in `pjsip.conf` + explicit `Set(CALLERID(num))` in dialplan.

## Next Steps
- Implement incoming call handling in `n8n`.
- Configure production dialplan logic.

## Real-Time Conversational AI Service
**Status:** ✅ Implemented & Deployed

### 1. Outbound Call Trigger
Start an AI call by sending a POST request to the internal API:
- **URL:** `http://<your-server-ip>:3030/call`
- **Method:** `POST`
- **Body:**
```json
{
  "phoneNumber": "+919074691700",
  "context": "outbound-ai-conversational"
}
```

### 2. Conversational Logic
The system implements a continuous loop:
1.  **Call Triggered** -> User Answers.
2.  **Greetings**: Asterisk calls n8n (`mode=welcome`).
3.  **Recording**: Asterisk records user audio (max 10s or silence).
4.  **Processing**: AGI uploads audio to n8n Webhook (`mode=process_input`).
5.  **Response**: n8n returns Audio URL or Text (handled by local TTS).
6.  **Loop**: Plays response and goes back to Recording.

### 3. n8n Configuration (Required)
To activate the intelligence, you must configure n8n:
1.  **Import Workflow**: Use `configs/n8n-workflow-template.json`.
2.  **Webhook Node**: Ensure it accepts `POST` and has **Binary Data** enabled (property: `file`).
3.  **Credentials**: Add your OpenAI API key to the Whisper and ChatGPT nodes.
4.  **Activate**: Turn on the workflow.

**Note:** If n8n is not configured, the call will connect but result in silence or fallback behavior.

