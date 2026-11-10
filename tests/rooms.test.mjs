import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("four combat seats and an independent read-only audience", { timeout: 15_000 }, async (t) => {
  const entry = fileURLToPath(new URL("../server/server.mjs", import.meta.url));
  const server = spawn(process.execPath, [entry], {
    windowsHide: true, env: { ...process.env, HOST: "127.0.0.1", PORT: "0", ICE_SERVERS: "[]" },
  });
  t.after(() => server.kill());
  const [started] = await Promise.race([
    once(server.stdout, "data"),
    once(server, "exit").then(() => { throw new Error("Signal server failed to start."); }),
  ]);
  const base = started.toString().match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];
  assert.ok(base);
  const post = async (action, fields = {}) => {
    const response = await fetch(base + "/signal", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action, version: 2, ...fields }),
    });
    return { status: response.status, data: response.status === 204 ? null : await response.json() };
  };
  const sync = ({ code, token }, fields = {}) => post("sync", { code, token, ...fields });

  assert.equal((await post("create", { version: 1 })).status, 426);
  assert.equal((await post("watch", { code: "000000" })).status, 404);
  const host = (await post("create")).data;
  const { code } = host;
  const guests = [];
  for (let i = 2; i <= 4; i++) {
    const guest = await post("join", { code });
    assert.equal(guest.status, 200);
    assert.equal(guest.data.id, i);
    guests.push(guest.data);
  }
  assert.match((await post("join", { code })).data.error, /full/i);

  const { data: watch } = await post("watch", { code });
  assert.deepEqual(Object.keys(watch).sort(), ["code", "watchKey"]);
  const viewUrl = base + "/spectate?" + new URLSearchParams({ code, key: watch.watchKey });
  const readers = [];
  t.after(async () => {
    await Promise.allSettled(readers.map((reader) => reader.cancel()));
  });
  const connectViewer = async () => {
    const reply = await fetch(viewUrl);
    assert.match(reply.headers.get("content-type"), /^text\/event-stream/);
    const reader = reply.body.getReader();
    readers.push(reader);
    const decode = new TextDecoder();
    let buffer = "";
    return async (expected) => {
      while (!buffer.includes(expected)) {
        const { value, done } = await reader.read();
        assert.ok(!done, "Spectator stream ended before the expected event.");
        buffer += decode.decode(value, { stream: true });
      }
      buffer = buffer.slice(buffer.indexOf(expected) + expected.length);
    };
  };
  const viewers = await Promise.all(Array.from({ length: 40 }, connectViewer));
  assert.equal((await sync(host)).data.viewers, 40);
  assert.equal((await sync({ code, token: watch.watchKey }, { seats: "open" })).status, 403);
  assert.equal((await post("publish", { ...guests[0], frame: "T0s=" })).status, 403);
  assert.equal((await sync(guests[0], { seats: "lock", active: [1] })).data.locked, false);

  const locked = await sync(host, { seats: "lock", active: [1, 2, 3] });
  assert.equal(locked.data.locked, true);
  assert.deepEqual(locked.data.events, [{ type: "peer_left", peer: 4 }]);
  assert.equal((await sync(guests[2])).status, 403);
  assert.match((await post("join", { code })).data.error, /in progress/i);
  assert.equal((await post("publish", { ...host, frame: "T0s=" })).status, 204);
  await Promise.all(viewers.map((read) => read("data: T0s=\n\n")));

  const lateViewer = await connectViewer();
  await lateViewer("data: T0s=\n\n");
  assert.equal((await sync(host, { seats: "open" })).data.locked, false);
  assert.equal((await post("join", { code })).status, 200);
  assert.equal((await post("leave", host)).status, 200);
  await Promise.all([...viewers, lateViewer].map((read) => read("event: room_closed\n")));
  assert.equal((await post("watch", { code })).status, 404);
});
