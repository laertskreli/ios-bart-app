# Claw Talk iOS App

A personal iOS messaging app that connects to Claw Talk, your AI agent running on OpenClaw.

## Features

- **Secure Connection**: Connects via Tailscale (WireGuard encrypted)
- **Node Pairing**: Uses OpenClaw's native pairing system
- **Streaming Responses**: See Claw Talk's response as it types
- **Sub-Agent Tabs**: Visual tabs for parallel work streams (power user mode)
- **Location Sharing**: Share your location with configurable TTL
- **Liquid Glass UI**: Modern, minimalist design with translucent elements

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Tailscale installed on your iPhone
- OpenClaw Gateway running on your Mac Mini

## Setup

### 1. Configure Gateway Host

Edit `Claw TalkApp/Configuration.swift` and replace the gateway host with your Tailscale hostname:

```swift
return "your-mac-mini.tailnet-name.ts.net"
```

### 2. Mac Mini Setup

1. Install OpenClaw:
   ```bash
   curl -fsSL https://openclaw.ai/install.sh | bash
   openclaw onboard --install-daemon
   ```

2. Configure agents in `~/.openclaw/openclaw.json`:
   ```json
   {
     "agents": {
       "list": [
         { "id": "bart", "workspace": "~/.openclaw/workspace-bart", "default": true },
         { "id": "bart-wife", "workspace": "~/.openclaw/workspace-bart-wife" }
       ]
     },
     "bindings": [
       { "agentId": "bart", "match": { "channel": "node", "peer": { "id": "iphone-me" } } },
       { "agentId": "bart-wife", "match": { "channel": "node", "peer": { "id": "iphone-wife" } } }
     ]
   }
   ```

3. Start the Gateway:
   ```bash
   openclaw gateway --bind tailnet
   ```

### 3. Pairing

1. Open the app on your iPhone
2. The app will show a pairing code
3. On your Mac Mini, run:
   ```bash
   openclaw nodes pending
   openclaw nodes approve <requestId>
   ```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Mac Mini (Home)                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              OpenClaw Gateway                           ││
│  │              ws://<tailscale-ip>:18789                  ││
│  │                                                         ││
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             ││
│  │  │  Claw Talk    │  │ SubAgent │  │ SubAgent │  ...        ││
│  │  │  (main)  │  │ (research)│ │ (tasks)  │             ││
│  │  └──────────┘  └──────────┘  └──────────┘             ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                           │
                    Tailscale (WireGuard)
                           │
          ┌────────────────┴────────────────┐
          │                                 │
    ┌─────▼─────┐                    ┌──────▼─────┐
    │  My       │                    │  Wife's    │
    │  iPhone   │                    │  iPhone    │
    └───────────┘                    └────────────┘
```

## Project Structure

```
Claw TalkApp/
├── Claw TalkApp.swift           # App entry point
├── Configuration.swift     # Gateway configuration
├── Info.plist
├── Assets.xcassets/
├── Models/
│   ├── DeviceIdentity.swift
│   ├── Conversation.swift
│   ├── Message.swift
│   ├── SubAgentInfo.swift
│   ├── LocationShare.swift
│   └── GatewayTypes.swift
├── Services/
│   ├── GatewayConnection.swift
│   └── LocationManager.swift
├── Views/
│   ├── RootView.swift
│   ├── Components/
│   │   ├── GlassBackground.swift
│   │   └── ConnectionStatusView.swift
│   ├── Pairing/
│   │   ├── PairingView.swift
│   │   ├── PairingPendingView.swift
│   │   └── PairingFailedView.swift
│   ├── Chat/
│   │   ├── MainView.swift
│   │   ├── ChatThreadView.swift
│   │   ├── MessageBubble.swift
│   │   ├── SimpleChatView.swift
│   │   └── TabbedChatView.swift
│   ├── Location/
│   │   └── LocationShareSheet.swift
│   └── Settings/
│       └── SettingsView.swift
└── Utilities/
    ├── AnyCodable.swift
    └── KeychainHelper.swift
```

## Building

1. Open `Claw TalkApp.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your device or simulator

## TestFlight Distribution

1. Archive the app in Xcode
2. Upload to App Store Connect
3. Add testers to your TestFlight group
4. Distribute via TestFlight

## License

Private - For personal use only.
