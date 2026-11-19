const BESTATO_DIR = "/bestato-wechat";
const BESTATO_PREFERENCES = "bestato.settings.v1";

module.exports = function installBestatoWechat(fs, wx, relayUrl) {
  const eventsPath = BESTATO_DIR + "/events.json";
  const commandPath = BESTATO_DIR + "/command.json";
  let editing = false;
  let draft = "";
  const cleanCode = (value) => String(value ?? "").toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, "").slice(0, 6);
  const inviteCode = (options) => {
    const room = options?.query?.room;
    return typeof room === "string" && /^[A-HJ-NP-Z2-9]{6}$/.test(room) ? room : "";
  };

  function queueEvent(event) {
    let pending = {};
    if (fs.analyzePath(eventsPath).exists) {
      pending = JSON.parse(fs.readFile(eventsPath, { encoding: "utf8" }));
    }
    fs.writeFile(eventsPath, JSON.stringify({ ...pending, ...event }));
  }

  function finishKeyboard(code) {
    if (!editing) return;
    editing = false;
    queueEvent({ keyboard: [code, true] });
  }

  let preferences = "{}";
  try { preferences = wx.getStorageSync(BESTATO_PREFERENCES) || "{}"; }
  catch { /* The default preferences can be used when storage is unavailable. */ }
  const info = wx.getWindowInfo?.() || wx.getSystemInfoSync?.();
  const area = info?.safeArea;
  const safeArea = area ? [info.windowWidth, info.windowHeight, area.left, area.top, area.right, area.bottom] : [];
  fs.mkdirTree(BESTATO_DIR);
  fs.writeFile(BESTATO_DIR + "/config.json", JSON.stringify({
    relay_url: relayUrl,
    preferences,
    safe_area: safeArea,
    invite: inviteCode(wx.getLaunchOptionsSync?.()),
  }));

  wx.onShow((options) => {
    const invite = inviteCode(options);
    if (invite) queueEvent({ invite });
  });
  wx.onHide(() => {
    finishKeyboard(draft);
    queueEvent({ hidden: true });
  });
  wx.onKeyboardInput?.((event) => {
    if (!editing) return;
    draft = cleanCode(event.value);
    queueEvent({ keyboard: [draft, false] });
  });
  wx.onKeyboardComplete?.((event) => finishKeyboard(event?.value == null ? draft : cleanCode(event.value)));

  // This engine template disables JavaScriptBridge. FileAccess and the host
  // share Emscripten memory, so closing the command file calls wx immediately.
  const close = fs.close;
  fs.close = function closeWithBestatoCommand(stream) {
    const isCommand = stream.path === commandPath && (stream.flags & 3) !== 0;
    const result = close.call(fs, stream);
    if (!isCommand) return result;
    const command = JSON.parse(fs.readFile(commandPath, { encoding: "utf8" }));
    try {
      switch (command.action) {
        case "preferences":
          wx.setStorageSync(BESTATO_PREFERENCES, command.value);
          break;
        case "keyboard":
          draft = cleanCode(command.value);
          editing = true;
          wx.showKeyboard({
            defaultValue: draft,
            maxLength: 6,
            multiple: false,
            confirmHold: false,
            confirmType: "done",
            fail: () => finishKeyboard(draft),
          });
          break;
        case "share":
          wx.shareAppMessage({ title: "bestato", query: "room=" + cleanCode(command.value) });
          break;
        case "copy":
          wx.setClipboardData({ data: cleanCode(command.value) });
          break;
      }
    } catch (error) {
      if (command.action === "keyboard") finishKeyboard(draft);
      console.warn("[bestato] WeChat action failed:", command.action, error);
    }
    return result;
  };
};
