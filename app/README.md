# Vibe Signal App — Install on iPhone (Mac)

`app/` is **source code**, not an App Store build. You need a **Mac + Xcode** to compile and install on a physical iPhone (Simulator cannot scan the pairing QR).

## Requirements

| Need | Notes |
|------|--------|
| Mac | macOS + Xcode 15+ (from the Mac App Store) |
| Apple ID | Free Personal Team is enough |
| iPhone | iOS 17+, USB cable to the Mac |
| This repo | Copy `vibe-signal` to the Mac, or `git clone` |

Checklist:

1. Unlock the iPhone and tap **Trust This Computer**
2. Open Xcode once so extra components finish installing
3. Xcode → **Settings → Accounts** → sign in with your Apple ID

---

## Generate the Xcode project

On the Mac terminal:

```bash
# If you don't have Homebrew yet: https://brew.sh
brew install xcodegen

cd /path/to/vibe-signal/app
xcodegen generate
open VibeSignal.xcodeproj
```

Close any old **AgentPulse.xcodeproj** if you still have one — targets and file membership can lag behind `project.yml`. Always open **VibeSignal.xcodeproj** after `xcodegen generate`.

`iOS/VoicePromptView.swift` is kept only so older AgentPulse projects that still reference it can compile; the live UI uses **Hold to talk** (defined in `RootView.swift` so AgentPulse.xcodeproj does not need new file membership).

Without XcodeGen you can create an App project in Xcode and drag in `iOS/`, `Shared/`, and `Watch/` — XcodeGen is usually faster.

App icons (chain-link mark) live in:

- `iOS/Assets.xcassets/AppIcon.appiconset`
- `Watch/Assets.xcassets/AppIcon.appiconset`

---

## Sign and run on your iPhone

1. Select the **VibeSignal** project in the sidebar
2. **TARGETS → VibeSignal** → **Signing & Capabilities**
   - Enable **Automatically manage signing**
   - **Team**: your Apple ID Personal Team
   - If `com.vibesignal.app` is taken, change it to something unique, e.g. `com.yourname.vibesignal`
3. Set the same **Team** on **VibeSignalWatch**
4. In the scheme device menu, pick your **physical iPhone** (not Simulator)
5. Press **▶ Run**

### Install fails — CoreDeviceError 3002

`Failed to install the app on the device` (code **3002**) is almost always signing / Watch / stale build — not Swift compile.

Try in order:

1. **Unlock the iPhone**, keep it on the Lock/Home screen during install  
2. **Delete** any old AgentPulse / Vibe Signal app from the phone  
3. Xcode → **Product → Clean Build Folder**, then delete DerivedData for this project  
4. **Signing**: both iOS and Watch targets → same Team, “Automatically manage signing”  
5. **Companion ID must match iOS Bundle ID**  
   - iOS target Bundle Identifier (e.g. `com.yourname.vibesignal`)  
   - Watch target / `Watch/Info.plist` → `WKCompanionAppBundleIdentifier` **exactly the same string**  
   - If you still use **AgentPulse.xcodeproj**, the Watch plist was pointing at `com.vibesignal.app` while the phone app may still be `com.…AgentPulse` — that mismatch alone can trigger 3002  
6. **Bypass Watch once** (to confirm phone install works):  
   - Select the iOS target → **Build Phases** → remove **Embed Watch Content** (or uncheck the Watch product) → Run  
   - Or regenerate with XcodeGen and temporarily comment the Watch `dependencies:` embed in `project.yml`  
7. iPhone → **Settings → Privacy & Security → Developer Mode** = On  
8. After first install: **Settings → General → VPN & Device Management → Trust** your Apple ID  

Prefer generating a fresh project instead of the old AgentPulse one:

```bash
cd app
xcodegen generate
open VibeSignal.xcodeproj
```

### First install: trust the developer

If the app won’t open (“Untrusted Developer”):

**iPhone → Settings → General → VPN & Device Management → your Apple ID → Trust**

Then Run again from Xcode.

### Apple Watch (optional)

After the iPhone app installs, the Watch companion may install automatically. If not:

**iPhone → Watch app → My Watch → Installed / Available Apps → Vibe Signal → Install**

Watch must be paired; watchOS 10+.

---

## Pair with the desktop connector

1. On the PC, open the Vibe Signal VS Code / Cursor extension → sidebar → **Connector On**
2. Phone and PC on the **same Wi‑Fi**
3. Sidebar → **Show Pairing QR** (or Pair Device)
4. On iPhone, open Vibe Signal → scan (allow Camera)
5. Desktop sidebar **clients** should become `1`

If it won’t connect:

- Pairing host must be a LAN IP like `192.168.x.x:8787`, not `127.0.0.1`
- Turn off VPN / guest-network client isolation
- Allow port `8787` through the PC firewall
- Or use **Copy Pairing JSON** and enter it manually in the app

---

## Permissions

On first use, allow:

- **Camera** — QR pairing
- **Microphone / Speech Recognition** — hold-to-talk prompts
- **Local Network** — talk to the desktop connector

---

## Voice input

**Press and hold** the mic to speak; **release** to send the transcript to the agent.

---

## Common errors

| Symptom | Fix |
|---------|-----|
| Signing / App Store Connect errors | Xcode → Settings → Accounts → sign in; select Personal Team |
| Bundle ID unavailable | Use a unique bundle identifier |
| Failed to launch / Developer Mode | iOS 16+: **Settings → Privacy & Security → Developer Mode → On**, reboot, Allow |
| Device grayed out | Cable + Trust Computer; Xcode → Window → Devices and Simulators |
| `xcodegen: command not found` | `brew install xcodegen` |
| Watch signing fails | Fix Watch target Team, or ship iPhone-only first |

---

## Updating later

```bash
cd /path/to/vibe-signal/app
# if project.yml changed:
xcodegen generate
```

Then **▶ Run** in Xcode to overwrite the installed app.
