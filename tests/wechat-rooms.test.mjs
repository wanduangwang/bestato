import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { WebSocket } from "ws";

test("WeChat relay keeps four combat seats and a read-only audience", { timeout: 15_000 }, async (t) => {
  const path = fileURLToPath(new URL("../server/server.mjs", import.meta.url));
  const server = spawn(process.execPath, [path], {
    windowsHide: true, env: { ...process.env, HOST: "127.0.0.1", PORT: "0", ICE_SERVERS: "[]" },
  });
  const clients = [];
  t.after(() => {
    for (const socket of clients) socket.terminate();
    server.kill();
  });
  const [output] = await Promise.race([
    once(server.stdout, "data"),
    once(server, "exit").then(() => { throw new Error("Room server exited before listening."); }),
  ]);
  const port = output.toString().match(/127\.0\.0\.1:(\d+)/)?.[1];
  assert.ok(port);

  const connect = async (type, code, version = 1) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/wechat-room`);
    clients.push(socket);
    const inbox = [];
    socket.on("message", (packet) => inbox.push(JSON.parse(packet)));
    await once(socket, "open");
    const send = (data) => socket.send(JSON.stringify(data));
    send({ type, code, version });
    const read = async (expectType, where = () => true) => {
      const deadline = Date.now() + 3500;
      while (Date.now() < deadline) {
        const index = inbox.findIndex((message) => message.type === expectType && where(message));
        if (index >= 0) return inbox.splice(index, 1)[0];
        await delay(10);
      }
      assert.fail(`Missing ${expectType}: ${JSON.stringify(inbox)}`);
    };
    const close = () => socket.terminate();
    return { close, inbox, read, send };
  };

  const old = await connect("create", "", 0);
  assert.match((await old.read("error")).error, /Reload/);
  const host = await connect("create");
  const { code, id } = await host.read("admitted");
  assert.equal(id, 1);
  const guests = await Promise.all(Array.from({ length: 3 }, () => connect("join", code)));
  const seats = await Promise.all(guests.map((guest) => guest.read("admitted")));
  assert.deepEqual(seats.map((seat) => seat.id).sort(), [2, 3, 4]);
  for (const seat of seats) await host.read("peer_joined", (message) => message.id === seat.id);
  const crowded = await connect("join", code);
  assert.match((await crowded.read("error")).error, /full/);

  const viewers = await Promise.all(Array.from({ length: 40 }, () => connect("watch", code)));
  for (const viewer of viewers) assert.equal((await viewer.read("admitted")).id, 0);
  await host.read("viewers", (message) => message.count === 40);
  host.send({ type: "profile", id: seats[0].id, data: "T0s=" });
  assert.equal((await guests[0].read("profile")).data, "T0s=");
  guests[0].send({ type: "input", x: 1, y: 0 });
  assert.deepEqual(await host.read("input"), { type: "input", id: seats[0].id, x: 1, y: 0 });

  host.send({ type: "seats", lock: true, active: [1, 2, 3, 4] });
  assert.equal((await host.read("seats")).locked, true);
  guests[2].close();
  assert.equal((await host.read("peer_left")).id, seats[2].id);
  viewers[0].send({ type: "seats", lock: false });
  viewers[0].send({ type: "input", x: 1, y: 0 });
  const vacant = await connect("join", code);
  assert.match((await vacant.read("error")).error, /in progress/);

  guests[0].send({ type: "snapshot", data: "RkFLRQ==" });
  host.send({ type: "snapshot", data: "T0s=" });
  for (const viewer of viewers) {
    assert.equal((await viewer.read("snapshot")).data, "T0s=");
    assert.equal(viewer.inbox.some(({ type }) => type === "profile" || type === "snapshot"), false);
  }
  assert.equal(host.inbox.some(({ type }) => type === "input" || type === "seats"), false);
  const late = await connect("watch", code);
  assert.equal((await late.read("admitted")).id, 0);
  assert.equal((await late.read("snapshot")).data, "T0s=");

  host.send({ type: "seats", lock: false, active: [] });
  assert.equal((await host.read("seats")).locked, false);
  const replacement = await connect("join", code);
  assert.equal((await replacement.read("admitted")).id, 5);

  host.close();
  await Promise.all([...viewers, late, guests[0], guests[1], replacement].map(async (client) => {
    assert.match((await client.read("error")).error, /host closed/);
  }));
});
