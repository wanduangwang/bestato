import { randomInt } from "node:crypto";
import { WebSocket, WebSocketServer } from "ws";

const PATH = "/wechat-room";
const VERSION = 1;
const CAPACITY = 4;
const ROOM_LIMIT = 128;
const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const FRAME_LIMIT = 64 * 1024;
const BACKLOG_LIMIT = 128 * 1024;
const ADMISSION_TIMEOUT = 6000;
const HEARTBEAT = 10_000;

function send(socket, message, snapshot = false) {
  if (socket.readyState !== WebSocket.OPEN) return;
  if (socket.bufferedAmount >= BACKLOG_LIMIT) {
    if (snapshot) return;
    if (socket.bufferedAmount >= BACKLOG_LIMIT * 4) {
      socket.terminate();
      return;
    }
  }
  socket.send(typeof message === "string" ? message : JSON.stringify(message), { compress: false });
}

function fail(socket, error) {
  socket.rejected = true;
  send(socket, { type: "error", error });
  // The game polls its inbox once per frame. Let it see the reason before closing.
  const timer = setTimeout(() => socket.close(), 400);
  socket.once("close", () => clearTimeout(timer));
}

function validFrame(data) {
  return typeof data === "string" && data.length > 0 && data.length <= FRAME_LIMIT &&
    data.length % 4 === 0 && /^[A-Za-z0-9+/]+={0,2}$/.test(data);
}

function parse(data) {
  try {
    const value = JSON.parse(data.toString());
    return value && typeof value.type === "string" ? value : null;
  } catch {
    return null;
  }
}

export function attachWechatRelay(server) {
  const rooms = new Map();
  const relay = new WebSocketServer({ noServer: true, maxPayload: FRAME_LIMIT + 1024, perMessageDeflate: false });

  server.on("upgrade", (request, socket, head) => {
    if (request.url !== PATH) {
      socket.end("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
      return;
    }
    relay.handleUpgrade(request, socket, head, (peer) => relay.emit("connection", peer));
  });

  function newRoom(host) {
    let code;
    do {
      code = Array.from({ length: 6 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
    } while (rooms.has(code));
    const room = {
      code, host, players: new Map([[1, host]]), viewers: new Set(),
      nextId: 2, locked: false, frame: "", frameAt: 0,
    };
    rooms.set(code, room);
    return room;
  }

  function dropPlayer(room, id) {
    if (!room.players.delete(id)) return;
    send(room.host, { type: "peer_left", id });
  }

  function closeRoom(room) {
    rooms.delete(room.code);
    for (const [id, player] of room.players) {
      if (id !== 1) fail(player, "The host closed the room.");
    }
    for (const viewer of room.viewers) fail(viewer, "The host closed the room.");
  }

  function handleHost(room, message) {
    switch (message.type) {
      case "seats": {
        const { lock, active } = message;
        if (lock === true && Array.isArray(active) && active.length <= CAPACITY && active.includes(1) &&
            active.every((id) => Number.isSafeInteger(id))) {
          room.locked = true;
          for (const [id, player] of room.players) {
            if (!active.includes(id)) {
              dropPlayer(room, id);
              fail(player, "Run in progress. Choose Watch.");
            }
          }
        } else if (lock === false) {
          room.locked = false;
        }
        send(room.host, { type: "seats", locked: room.locked });
        break;
      }
      case "drop": {
        const player = room.players.get(message.id);
        if (message.id > 1 && player) {
          dropPlayer(room, message.id);
          fail(player, "Your room slot has expired.");
        }
        break;
      }
      case "profile": {
        const player = room.players.get(message.id);
        if (message.id > 1 && player && validFrame(message.data)) {
          send(player, { type: "profile", data: message.data });
        }
        break;
      }
      case "snapshot": {
        if (!validFrame(message.data)) return;
        const frame = JSON.stringify({ type: "snapshot", data: message.data });
        room.frame = frame;
        room.frameAt = Date.now();
        for (const [id, player] of room.players) {
          if (id !== 1) send(player, frame, true);
        }
        for (const viewer of room.viewers) send(viewer, frame, true);
        break;
      }
    }
  }

  relay.on("connection", (socket) => {
    let room;
    let peerId = 0;
    socket.alive = true;
    const timeout = setTimeout(() => socket.close(1008, "Admission timed out"), ADMISSION_TIMEOUT);
    socket.on("error", () => socket.terminate());
    socket.on("pong", () => { socket.alive = true; });
    socket.on("close", () => {
      clearTimeout(timeout);
      if (!room || rooms.get(room.code) !== room) return;
      if (peerId === 1) closeRoom(room);
      else if (peerId > 1) dropPlayer(room, peerId);
      else if (room.viewers.delete(socket)) send(room.host, { type: "viewers", count: room.viewers.size });
    });
    socket.on("message", (data, binary) => {
      if (socket.readyState !== WebSocket.OPEN || socket.rejected || binary) return;
      const message = parse(data);
      if (!message) return;
      if (!room) {
        if (message.version !== VERSION) return fail(socket, "Reload the game to get the current room version.");
        const action = message.type;
        if (action === "create") {
          if (rooms.size >= ROOM_LIMIT) return fail(socket, "Room server is full.");
          room = newRoom(socket);
          peerId = 1;
        } else {
          if (action !== "join" && action !== "watch") return fail(socket, "The room request failed.");
          const found = rooms.get(message.code);
          if (!found) return fail(socket, "Room not found or the host left.");
          if (action === "join") {
            if (found.locked) return fail(socket, "Run in progress. Choose Watch.");
            if (found.players.size >= CAPACITY) return fail(socket, "This room is full. Choose Watch.");
            peerId = found.nextId++;
            found.players.set(peerId, socket);
          } else {
            found.viewers.add(socket);
          }
          room = found;
        }
        clearTimeout(timeout);
        send(socket, { type: "admitted", code: room.code, id: peerId });
        if (peerId > 1) send(room.host, { type: "peer_joined", id: peerId });
        else if (peerId === 0) {
          send(room.host, { type: "viewers", count: room.viewers.size });
          if (room.frame && Date.now() - room.frameAt < 1000) send(socket, room.frame, true);
        }
        return;
      }
      if (rooms.get(room.code) !== room) return;
      if (peerId === 1) handleHost(room, message);
      else if (peerId > 1 && room.players.has(peerId)) {
        if (message.type === "input" && Number.isFinite(message.x) && Number.isFinite(message.y)) {
          send(room.host, { type: "input", id: peerId, x: message.x, y: message.y });
        } else if (message.type === "choice" &&
                   [message.action, message.slot, message.revision].every(Number.isSafeInteger)) {
          send(room.host, { type: "choice", id: peerId, action: message.action, slot: message.slot,
            revision: message.revision });
        }
      }
    });
  });

  const pulse = setInterval(() => {
    for (const socket of relay.clients) {
      if (!socket.alive) socket.terminate();
      else if (socket.readyState === WebSocket.OPEN) {
        socket.alive = false;
        socket.ping();
      }
    }
  }, HEARTBEAT);
  pulse.unref();
  server.on("close", () => clearInterval(pulse));
}
