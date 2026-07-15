const test = require("node:test");
const assert = require("node:assert/strict");
const { ConnectorServer } = require("../out/server");
const { StateMachine } = require("../out/state");
const { DecisionHub } = require("../out/decisionHub");

test("voice prompt starts a Codex turn when no Stop hook is active", async () => {
  const started = [];
  const server = new ConnectorServer({
    port: 0,
    token: "test",
    state: new StateMachine(),
    decisions: new DecisionHub(),
    permissionTimeoutMs: 100,
    stopTimeoutMs: 100,
    onStartTurn: async (request) => {
      started.push(request);
      return true;
    },
  });

  const ack = await server.handleCommand({
    type: "command",
    command: "voice_prompt",
    text: "Inspect the failing tests",
  });

  assert.deepEqual(ack, {
    type: "ack",
    command: "voice_prompt",
    ok: true,
  });
  assert.equal(started.length, 1);
  assert.equal(started[0].prompt, "Inspect the failing tests");
});
