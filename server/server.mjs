import { randomBytes, randomInt } from "node:crypto";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const capacity = 4;
const roomLimit = 128;
const idleMs = 25_000;
const bodyLimit = 256 * 1024;
const webRoot = fileURLToPath(new URL("../web/", import.meta.url));
const rooms = new Map();
const defaultIce = [{ urls: ["stun:stun.l.google.com:19302"] }];
const iceServers = process.env.ICE_SERVERS ? JSON.parse(process.env.ICE_SERVERS) : defaultIce;

if (!Array.isArray(iceServers)) {
  throw new TypeError("ICE_SERVERS must be a JSON array of RTCIceServer entries.");
}

function json(res, status, data) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  res.end(JSON.stringify(data));
}

function newCode() {
  let code;
  do {
    code = Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join("");
  } while (rooms.has(code));
  return code;
}

function addMember(room) {
  const member = {
    id: room.nextId++,
    token: randomBytes(24).toString("base64url"),
    touched: Date.now(),
    events: [],
  };
  room.members.set(member.id, member);
  return member;
}

function removeMember(code, room, id) {
  if (id === 1) {
    rooms.delete(code);
    return;
  }
  if (room.members.delete(id)) {
    const host = room.members.get(1);
    host.events = host.events.filter((event) => event.peer !== id);
    host.events.push({ type: "peer_left", peer: id });
  }
}

function reapRooms() {
  const now = Date.now();
  for (const [code, room] of rooms) {
    if (now - room.members.get(1).touched > idleMs) {
      rooms.delete(code);
      continue;
    }
    for (const member of room.members.values()) {
      if (now - member.touched > idleMs) {
        removeMember(code, room, member.id);
      }
    }
  }
}

function sendAdmission(res, code, member) {
  json(res, 200, { code, id: member.id, token: member.token, iceServers });
}

function relay(room, sender, packet) {
  if (!packet || !Number.isInteger(packet.to)) return;
  const recipient = room.members.get(packet.to);
  if (!recipient || recipient.id === sender.id || recipient.events.length >= 128) return;
  if (sender.id !== 1 && recipient.id !== 1) return;

  // Routing metadata comes from the room, never from an untrusted packet field.
  const event = { type: packet.type, peer: sender.id };
  if (packet.type === "ice") {
    if (typeof packet.media !== "string" || packet.media.length > 32 ||
        !Number.isInteger(packet.index) || packet.index < 0 || packet.index > 16 ||
        typeof packet.candidate !== "string" || packet.candidate.length > 2048) return;
    event.media = packet.media;
    event.index = packet.index;
    event.candidate = packet.candidate;
  } else {
    const expected = sender.id === 1 ? "offer" : "answer";
    if (packet.type !== expected || typeof packet.sdp !== "string" || packet.sdp.length > 16_384) return;
    event.sdp = packet.sdp;
  }
  recipient.events.push(event);
}

async function signal(req, res) {
  if (req.method !== "POST") return json(res, 405, { error: "Use POST for signaling." });
  if (Number(req.headers["content-length"]) > bodyLimit) {
    return json(res, 413, { error: "Signaling request is too large." });
  }
  let data;
  try {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > bodyLimit) {
        json(res, 413, { error: "Signaling request is too large." });
        return;
      }
      chunks.push(chunk);
    }
    data = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!data || typeof data.action !== "string") throw new Error("Missing action");
  } catch {
    return json(res, 400, { error: "Invalid signaling request." });
  }

  reapRooms();
  if (data.action === "create") {
    if (rooms.size >= roomLimit) return json(res, 503, { error: "Room server is full." });
    const code = newCode();
    const room = { members: new Map(), nextId: 1 };
    rooms.set(code, room);
    return sendAdmission(res, code, addMember(room));
  }

  const room = rooms.get(data.code);
  if (!room) return json(res, 404, { error: "Room not found or the host left." });
  if (data.action === "join") {
    if (room.members.size >= capacity) return json(res, 409, { error: "This room is full." });
    const member = addMember(room);
    room.members.get(1).events.push({ type: "peer_joined", peer: member.id });
    return sendAdmission(res, data.code, member);
  }

  const member = [...room.members.values()].find((entry) => entry.token === data.token);
  if (!member) return json(res, 403, { error: "Your room slot has expired." });
  if (data.action === "leave") {
    removeMember(data.code, room, member.id);
    return json(res, 200, {});
  }
  if (data.action !== "sync") return json(res, 400, { error: "Unknown signaling action." });

  member.touched = Date.now();
  if (member.id === 1 && Array.isArray(data.drop)) {
    for (const id of data.drop.slice(0, capacity - 1)) {
      if (Number.isInteger(id) && id > 1) removeMember(data.code, room, id);
    }
  }
  if (Array.isArray(data.messages)) {
    for (const packet of data.messages.slice(0, 64)) relay(room, member, packet);
  }
  return json(res, 200, { events: member.events.splice(0, 64) });
}

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".wasm": "application/wasm",
  ".pck": "application/octet-stream",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".json": "application/json",
  ".webmanifest": "application/manifest+json",
};

async function serveWeb(req, res, pathname) {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.writeHead(405, { Allow: "GET, HEAD" }).end();
    return;
  }
  const file = resolve(webRoot, "." + (pathname === "/" ? "/index.html" : pathname));
  const local = relative(webRoot, file);
  if (local === ".." || local.startsWith(".." + sep) || resolve(webRoot, local) !== file) {
    res.writeHead(403).end();
    return;
  }
  try {
    const info = await stat(file);
    if (!info.isFile()) throw new Error("Expected a file");
    res.writeHead(200, {
      "Content-Type": mimeTypes[extname(file)] || "application/octet-stream",
      "Content-Length": info.size,
      "Cache-Control": "no-cache",
      "X-Content-Type-Options": "nosniff",
    });
    if (req.method === "HEAD") res.end();
    else createReadStream(file).on("error", () => res.destroy()).pipe(res);
  } catch {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Web export missing. Export the Godot Web preset to web/index.html.");
  }
}

const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
    if (pathname === "/signal") await signal(req, res);
    else await serveWeb(req, res, pathname);
  } catch {
    if (res.headersSent) res.destroy();
    else json(res, 400, { error: "Invalid request." });
  }
});

setInterval(reapRooms, 5000).unref();
const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || 8787);
server.listen(port, host, () => {
  console.log(`bestato listening on http://${host}:${server.address().port}`);
});
