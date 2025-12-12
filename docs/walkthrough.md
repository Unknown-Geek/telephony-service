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
