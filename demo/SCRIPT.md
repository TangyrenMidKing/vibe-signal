# Vibe Signal Demo Script

## Slide 1 — Vibe coding should move with you

“Vibe coding is changing how we build software, but the experience is still tied to the desk. You start an agent, watch the editor, and wait for the next moment when it needs you.

Vibe Signal lets the agent stay at the desk while its state and controls move with you.”

## Slide 2 — The inspiration

“The idea was inspired by retro physical vibe-coding controllers. They make AI work feel tangible, but they are still connected by a cable.

I wanted to take the same idea further: vibe coding should work anywhere around you, on devices you already carry.”

## Slide 3 — How it connects

“The flow is simple.

Codex emits lifecycle events. The Vibe Signal connector receives those events and turns them into a consistent state signal. A local WebSocket broadcasts that signal to the iPhone, and the iPhone mirrors it to Apple Watch.

Pairing takes one QR scan. The QR code contains the local connection information and a secure token, so there is no manual network setup.”

Point across the signal path:

“Codex. Connector. WebSocket. iPhone. Watch.”

## Slide 4 — Live demo

Let both videos begin automatically.

“In this demo, I tell Vibe Signal to center all the text in the Apple Watch interface.

My voice request is sent from the Watch, through the iPhone and connector, to Codex. That triggers Codex to inspect the SwiftUI code and fix the layout.

On the desktop, you can see Codex make the change. Vibe Signal keeps the Watch updated while the agent is working.”

When Codex finishes, rebuild the Apple Watch app.

“Now I rebuild the Watch interface and validate the result. The text is centered, so the issue is fixed.

The complete loop happened from the Watch: describe the problem, trigger Codex, rebuild the app, and verify the result.”

## Slide 5 — Five states, one glance

Select each state button while speaking:

- **Idle:** “The connector is ready, but no turn is active.”
- **Working:** “Codex is actively planning, editing, or running tools.”
- **Waiting:** “The agent needs an approval or another user decision.”
- **Done:** “The current turn completed successfully.”
- **Error:** “The task needs attention, and I can retry or return to the editor.”

“Each state has a label, color, and Watch haptic. I can understand what is happening with one glance and respond without returning to the desk.”

## Slide 6 — Close

“Vibe Signal is not remote desktop for AI. It is a small connector platform that exposes agent state to the devices around us.

Today it connects Codex, iPhone, and Apple Watch over local Wi-Fi. The larger idea is simple: the agent can stay at the desk. You do not have to.”
