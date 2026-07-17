const test = require("node:test");
const assert = require("node:assert/strict");
const { ConnectorServer } = require("../out/server");
const { StateMachine } = require("../out/state");
const { DecisionHub } = require("../out/decisionHub");

function makeServer(overrides = {}) {
  const started = [];
  const state = new StateMachine({ workingTimeoutMs: 1_000_000 });
  const decisions = new DecisionHub();
  const server = new ConnectorServer({
    port: 0,
    token: "test",
    state,
    decisions,
    permissionTimeoutMs: 50,
    stopTimeoutMs: 50,
    onStartTurn: async (request) => {
      started.push(request);
      return true;
    },
    ...overrides,
  });
  return { server, state, decisions, started };
}

test("hook events drive the four UI states", () => {
  const { state } = makeServer();

  assert.equal(state.get().state, "idle");

  state.applyHookEvent({ hook_event_name: "SessionStart", session_id: "s1" });
  assert.equal(state.get().state, "working");

  state.applyHookEvent({ hook_event_name: "UserPromptSubmit", prompt: "hi" });
  assert.equal(state.get().state, "working");

  state.applyHookEvent({ hook_event_name: "PreToolUse", tool_name: "shell" });
  assert.equal(state.get().state, "working");

  state.applyHookEvent({
    hook_event_name: "PostToolUse",
    tool_name: "shell",
    tool_response: { exit_code: 0 },
  });
  assert.equal(state.get().state, "working");

  state.applyHookEvent({
    hook_event_name: "PostToolUse",
    tool_name: "shell",
    tool_response: { exit_code: 2 },
  });
  assert.equal(state.get().state, "error");

  state.applyHookEvent({
    hook_event_name: "PermissionRequest",
    tool_name: "shell",
    tool_input: { command: "rm -rf" },
  });
  assert.equal(state.get().state, "waiting");

  state.applyHookEvent({
    hook_event_name: "Stop",
    last_assistant_message: "done",
  });
  assert.equal(state.get().state, "completed");
  assert.equal(state.get().detail, "done");
});

test("approve resolves a long-polling permission hook exactly once", async () => {
  const { server, state, decisions } = makeServer();
  state.setState("waiting", "Approve?", { turnId: "turn-1" });

  // No active permission hook yet.
  let ack = await server.handleCommand({ type: "command", command: "approve" });
  assert.equal(ack.ok, false);

  // Hook begins and long-polls for a phone decision.
  decisions.beginPermission("turn-1");
  const waiter = decisions.waitPermission("turn-1", 1_000);

  ack = await server.handleCommand({ type: "command", command: "approve" });
  assert.equal(ack.ok, true);
  assert.deepEqual(await waiter, { decision: "allow" });
  assert.equal(state.get().state, "working", "leave waiting immediately");

  // The decision was consumed; a second approve fails.
  ack = await server.handleCommand({ type: "command", command: "approve" });
  assert.equal(ack.ok, false);
});

test("deny carries a message to the waiting hook", async () => {
  const { server, state, decisions } = makeServer();
  state.setState("waiting", "Approve?", { turnId: "turn-1" });
  decisions.beginPermission("turn-1");
  const waiter = decisions.waitPermission("turn-1", 1_000);

  const ack = await server.handleCommand({
    type: "command",
    command: "deny",
    text: "not safe",
  });
  assert.equal(ack.ok, true);
  assert.deepEqual(await waiter, { decision: "deny", message: "not safe" });
  assert.equal(state.get().state, "working");
});

test("continue resolves a long-polling stop hook exactly once", async () => {
  const { server, state, decisions } = makeServer();
  state.setState("completed", "done", { turnId: "turn-1" });

  let ack = await server.handleCommand({ type: "command", command: "continue" });
  assert.equal(ack.ok, false);

  decisions.beginStop("turn-1");
  const waiter = decisions.waitStop("turn-1", 1_000);

  ack = await server.handleCommand({
    type: "command",
    command: "continue",
    text: "keep going",
  });
  assert.equal(ack.ok, true);
  assert.deepEqual(await waiter, { decision: "continue", reason: "keep going" });
  assert.equal(state.get().state, "working");

  ack = await server.handleCommand({ type: "command", command: "continue" });
  assert.equal(ack.ok, false);
});

test("voice prompt injects into an active stop hook before starting a turn", async () => {
  const { server, state, decisions, started } = makeServer();
  state.setState("completed", "done", { turnId: "turn-1" });
  decisions.beginStop("turn-1");

  const ack = await server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "resume this",
  });

  assert.equal(ack.ok, true);
  assert.equal(started.length, 0, "should resume, not spawn a new turn");
  assert.equal(state.get().state, "working");

  // Same thread: a second voice must not spawn while resumed.
  const ack2 = await server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "another prompt",
  });
  assert.equal(ack2.ok, false);
  assert.equal(started.length, 0);
});

test("voice prompt starts a new turn from idle/completed/error", async () => {
  for (const s of ["idle", "completed", "error"]) {
    const { server, state, started } = makeServer();
    state.setState(s, "test");

    const ack = await server.handleCommand({
      type: "command",
      command: "voice_prompt",
      text: "do the thing",
    });

    assert.equal(ack.ok, true, `voice from ${s} should start a turn`);
    assert.equal(started.length, 1);
  }
});

test("voice prompt does NOT spawn a concurrent Codex while working or waiting", async () => {
  for (const s of ["working", "waiting"]) {
    const { server, state, started } = makeServer();
    state.setState(s, "busy");

    const ack = await server.handleCommand({
      type: "command",
      command: "voice_prompt",
      text: "do the thing",
    });

    assert.equal(ack.ok, false, `voice from ${s} should be rejected`);
    assert.equal(started.length, 0, `no turn should spawn from ${s}`);
    assert.match(ack.message ?? "", /busy/i);
  }
});

test("empty voice prompt is rejected", async () => {
  const { server, started } = makeServer();
  const ack = await server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "   ",
  });
  assert.equal(ack.ok, false);
  assert.equal(started.length, 0);
});

test("only one voice-started turn at a time (race)", async () => {
  const started = [];
  const state = new StateMachine({ workingTimeoutMs: 1_000_000 });
  const decisions = new DecisionHub();
  let release;
  const gate = new Promise((r) => {
    release = r;
  });
  const server = new ConnectorServer({
    port: 0,
    token: "test",
    state,
    decisions,
    permissionTimeoutMs: 50,
    stopTimeoutMs: 50,
    onStartTurn: async (request) => {
      started.push(request);
      // Mimic controller: mark working as soon as launch is accepted.
      state.setState("working", request.prompt);
      await gate;
      return true;
    },
  });

  const first = server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "first",
  });
  // Let the first onStartTurn claim the thread before the second arrives.
  await new Promise((r) => setImmediate(r));

  const second = await server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "second",
  });
  release();
  const firstAck = await first;

  assert.equal(firstAck.ok, true);
  assert.equal(second.ok, false);
  assert.equal(started.length, 1);
  assert.equal(started[0].prompt, "first");
});

test("session_id-only Stop aligns turnId for timeout reset", () => {
  const { state } = makeServer();
  state.applyHookEvent({
    hook_event_name: "Stop",
    session_id: "sess-abc",
    last_assistant_message: "done",
  });
  assert.equal(state.get().state, "completed");
  assert.equal(state.get().turnId, "sess-abc");
  assert.equal(state.get().sessionId, "sess-abc");
});

test("stop aborts a working turn and moves to completed", async () => {
  let stopped = 0;
  const { server, state } = makeServer({
    onStopTurn: () => {
      stopped += 1;
      return true;
    },
  });
  state.setState("working", "coding");

  const ack = await server.handleCommand({ type: "command", command: "stop" });
  assert.equal(ack.ok, true);
  assert.equal(stopped, 1);
  assert.equal(state.get().state, "completed");
  assert.match(state.get().detail, /Stopped/i);
});

test("stop is rejected when idle", async () => {
  const { server } = makeServer({ onStopTurn: () => true });
  const ack = await server.handleCommand({ type: "command", command: "stop" });
  assert.equal(ack.ok, false);
});
