# n8n AI Agent Integration Plan

## Goal
Route phone conversations through n8n AI Agent so the AI can access tools like Gmail, Calendar, and perform actions on behalf of the user.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     PHONE CALL FLOW                              │
├─────────────────────────────────────────────────────────────────┤
│  [User Speaks] → [Whisper STT] → [n8n Webhook]                  │
│                                       │                          │
│                              ┌────────▼────────┐                │
│                              │   n8n AI Agent   │                │
│                              │  (with tools)    │                │
│                              └────────┬────────┘                │
│                                       │                          │
│                        ┌──────────────┼──────────────┐          │
│                        ▼              ▼              ▼          │
│                    [Gmail]      [Calendar]     [Custom]         │
│                                       │                          │
│  [User Hears] ← [Edge TTS] ← [AI Response]                      │
└─────────────────────────────────────────────────────────────────┘
```

## Proposed Changes

### 1. AGI Script Modification
Update `agi-connector.sh` to call n8n webhook instead of Groq:
- Send transcribed text to `https://n8n.shravanpandala.me/webhook/phone-agent`
- Receive AI response as JSON `{"response": "..."}`
- Generate TTS from response

### 2. n8n Workflow
Create workflow with:
- **Webhook** trigger (receives transcribed text)
- **AI Agent** node with system prompt
- **Tools**: Gmail, Google Calendar, HTTP Request, etc.
- **Respond to Webhook** with AI response

## Verification
- Test Gmail integration: "Do I have any new emails?"
- Test Calendar: "What's on my schedule today?"
- Test reminders: "Remind me to call John at 3pm"
