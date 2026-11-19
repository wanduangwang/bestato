import assert from "node:assert/strict";
import test from "node:test";
import install from "../platform/wechat/bestato-platform.js";

test("WeChat file bridge routes settings, invitations and the keyboard through native APIs", () => {
  const key = "bestato.settings.v1";
  const configPath = "/bestato-wechat/config.json";
  const eventsPath = "/bestato-wechat/events.json";
  const commandPath = "/bestato-wechat/command.json";
  const storage = new Map([[key, '{"language":"zh_CN","sound_muted":true}']]);
  const files = new Map();
  const callbacks = {};
  const fs = {
    mkdirTree() {},
    analyzePath: (path) => ({ exists: files.has(path) }),
    writeFile: (path, text) => files.set(path, text),
    readFile: (path) => files.get(path),
    close: () => {},
  };
  const wx = {
    getStorageSync: (name) => storage.get(name),
    setStorageSync: (name, value) => storage.set(name, value),
    onHide: (fn) => { callbacks.hide = fn; },
    onShow: (fn) => { callbacks.show = fn; },
    getLaunchOptionsSync: () => ({ query: { room: "ABC234" } }),
    getWindowInfo: () => ({
      windowWidth: 800, windowHeight: 400, safeArea: { left: 20, top: 0, right: 780, bottom: 380 },
    }),
    onKeyboardInput: (fn) => { callbacks.type = fn; },
    onKeyboardComplete: (fn) => { callbacks.done = fn; },
    showKeyboard: (options) => { callbacks.keyboard = options; },
    shareAppMessage: (options) => { callbacks.share = options; },
    setClipboardData: (options) => { callbacks.clipboard = options; },
  };
  install(fs, wx, "wss://example.test/wechat-room");
  assert.deepEqual(JSON.parse(files.get(configPath)), {
    relay_url: "wss://example.test/wechat-room",
    preferences: storage.get(key),
    safe_area: [800, 400, 20, 0, 780, 380],
    invite: "ABC234",
  });

  function command(action, value) {
    fs.writeFile(commandPath, JSON.stringify({ action, value }));
    fs.close({ path: commandPath, flags: 1 });
  }

  command("preferences", '{"language":"en","sound_muted":false}');
  assert.equal(storage.get(key), '{"language":"en","sound_muted":false}');
  command("share", "abc234");
  assert.equal(callbacks.share.query, "room=ABC234");
  command("copy", "abc234");
  assert.equal(callbacks.clipboard.data, "ABC234");

  callbacks.show({ query: { room: "bad" } });
  assert.equal(files.has(eventsPath), false);
  callbacks.show({ query: { room: "ZYX678" } });
  command("keyboard", "a");
  assert.equal(callbacks.keyboard.defaultValue, "A");
  assert.equal(callbacks.keyboard.maxLength, 6);
  callbacks.type({ value: "abc 2345" });
  assert.deepEqual(JSON.parse(files.get(eventsPath)).keyboard, ["ABC234", false]);
  callbacks.hide();
  callbacks.done({ value: "ZZZ222" });
  assert.deepEqual(JSON.parse(files.get(eventsPath)), {
    invite: "ZYX678", hidden: true, keyboard: ["ABC234", true],
  });

  files.delete(eventsPath);
  command("keyboard", "");
  callbacks.done({ value: "DEF789" });
  assert.deepEqual(JSON.parse(files.get(eventsPath)).keyboard, ["DEF789", true]);
});
