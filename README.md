# bestato

用 Godot 4 和 GDScript 实现的《土豆兄弟》风格原型。支持单机、2–4 人网页合作和只读观战。角色、敌人、武器造型和音效均由项目代码生成。

## 试玩

从仓库克隆后，先按下文生成 `web/index.html`。在项目根目录用 Node.js 20 或更高版本运行 `npm ci` 和 `npm start`，打开 [本机游戏](http://127.0.0.1:8787)。

- **语言和音效**可在右上角切换。首次默认为 English，切换后即时生效。网页保留当前标签页的设置供刷新时使用，最近保存的偏好作为新标签页的默认值。桌面版将偏好保存在 `user://settings.cfg`。
- **单机**：点 **Deploy Solo**，选择角色和初始武器，再点 **Deploy**。
- **联机**：一个窗口点 **Create Room**，其余窗口在同一地址输入六位房间码并点 **Join**。每人选择自己的角色和武器，客机点 **Ready Up**，房主点 **Deploy**。开局后本轮锁定战斗席，退房者可重新输入码观战。房主开始新一局时重新开放战斗席。更新版本后请刷新所有窗口。
- **观战**：输入同一房间码后点 **Watch**。大厅、战斗、波间和结算都可加入，包括四个战斗席满员时。观众看到公开战斗画面和队伍状态，可随时点 **Leave** 退出。观战不占战斗席，不计入难度、掉落和准备人数。
- **战斗**：WASD 移动，武器自动瞄准射程内的目标。绿色材料同时增加经验和商店余额，水果回血，箱子在波间开。未捡的材料进袋，后续会加到新的掉落上。
- **波间**：先选升级、开箱，再从四个商品中买武器或被动物品。**Lock** 同时保留商品和价格，**Reroll** 刷新未锁货架。两把同名同级武器可以 **Merge**，**Sell** 可回收。每人有独立商店，全部 **Ready** 后进入下一波，血量回满并复活倒下的队友。

共 20 波。首波 20 秒，常规波逐步增长至 60 秒，终波 90 秒。部署前可选择 **Danger 0–5**。从 Danger 2 起有精英，从 Danger 4 起增加群潮和第二场精英战，Danger 5 的终波有双首领。撑过终波胜利，全队倒地结束。当前内容池有 4 个角色、13 种武器、24 件被动物品和 16 项升级属性。[机制调研与数值表](docs/design-notes.md)

## 源码与网页导出

使用 Godot 4.3 或更高版本的标准版编辑器，打开 `project.godot` 后按 **F5** 可玩单机。网页构建使用 **Compatibility** 与单线程模板。在编辑器的导出模板管理器安装同版本模板，再导出自带的 **Web** 预设。命令行示例中的 `godot` 可换成实际可执行文件路径。

```powershell
godot --headless --path . --export-release Web web/index.html
npm ci
npm start
```

| 路径 | 职责 |
| --- | --- |
| `scenes/` | 主场景、玩家和敌人节点 |
| `scripts/game/catalog.gd` | 角色、武器、物品与属性数据 |
| `scripts/game/balance.gd` | 合作缩放、经验曲线、品质和刷新公式 |
| `scripts/game/build.gd` | 个人构筑、品质、套装、升级和商店 |
| `scripts/game/arena.gd`、`waves.gd` | 房主权威的战斗、波次、掉落与结算 |
| `scripts/game/player.gd`、`enemy.gd`、`world_view.gd`、`sounds.gd` | 角色状态、敌人行为、效果与程序音效 |
| `scripts/network/` | WebRTC 战斗同步、房间信令和只读观战流 |
| `scripts/platform.gd`、`platform/wechat/` | 触屏能力、微信存储、房间码输入和分享 |
| `scripts/ui/interface.gd` | 菜单、角色选择、HUD、升级与个人商店 |
| `scripts/settings.gd`、`i18n/zh_CN.po` | 本地偏好及简体中文译文 |
| `server/server.mjs` | 同源网页托管与房间信令 |
| `server/wechat-relay.mjs` | 微信 WebSocket 房间、锁席和只读观战 |

简体中文界面使用 Bestato UI 字体。它是 Noto Sans CJK SC Regular 2.004 的界面用字子集，随附 [SIL OFL 1.1 许可证](assets/fonts/OFL-NotoSansCJK.txt)。新增译文时需确认字体涵盖所用字符。[Noto CJK 字体源](https://github.com/notofonts/noto-cjk/tree/Sans2.004/Sans)

## 微信小游戏构建

在 PowerShell 7 用官方 Godot 4.6.3 的控制台程序执行构建脚本。脚本校验导出工具和兼容模板的 SHA-256，在临时工程中打包，输出到 `dist/wechat`。这个目录是微信开发者工具的导入路径，默认使用测试 AppID 生成单人预览包。正式联机体验包使用自己的小游戏 AppID 和已配置的 WSS 域名。[微信版开发方案](docs/wechat-minigame-plan.md)

```powershell
./tools/build-wechat.ps1 -Godot 'C:/path/to/Godot_v4.6.3-stable_win64_console.exe'
./tools/build-wechat.ps1 -Godot 'C:/path/to/Godot_v4.6.3-stable_win64_console.exe' -AppId 'wx0123456789abcdef' -RelayUrl 'wss://game.example.com/wechat-room'
```

启动 `npm start` 后，反向代理将 HTTPS/WSS 域名的 `/wechat-room` 和 WebSocket 升级请求转给 Node。开发者在小游戏后台的开发设置中登记该 WSS 域名。手机端用摇杆移动，房主可从大厅分享房间码。房间分享只包含房间码，打开后从菜单选择参加或观战。只读观战和战斗席由服务器分别管理。[微信网络配置](https://developers.weixin.qq.com/minigame/dev/guide/base-ability/network.html)

浏览器 localhost 预览加 `?relay=1` 可验证同一套房间中继逻辑。默认网页入口使用 WebRTC，两个入口使用各自的房间。真机体验版通过微信开发者工具扫码验收。

## 联机部署

房主是 Peer 1。信令服务以六位房间码管理内存中的房间，转发 SDP/ICE。每位客机与房主建立一条 WebRTC 连接，房主负责刷怪、弹丸、伤害、材料分配与交易校验。位置和战斗画面走短周期快照，个人构筑和商店命令走可靠 RPC，命令附带版本号以阻止旧界面重复扣款。服务器确认战斗席锁定后，房主才开始模拟第一波。

有观众时，房主以约 8 Hz 上传一份公开快照，服务器通过 `/spectate` 的 SSE 流转发。应用层没有观众席位上限，实际容量取决于服务器连接数和出口带宽。个人商店和输入权限留在战斗连接上。房主退出时，服务器关闭房间与观战流。

每波开始时，房主按当时仍连接的战斗玩家人数确定刷怪、敌人生命、伤害及掉落缩放。战斗 HUD 显示该波的人数和敌人倍率，客机和观众看到同一数值。波中掉线后，下一波按剩余战斗玩家人数重新计算。

异地试玩时，把 Node 服务通过 HTTPS 反向代理对外提供，保持网页、`/signal` 和 `/spectate` 同源。反向代理需要流式转发 `/spectate`，并允许长连接。默认监听 `127.0.0.1:8787`，可用 `HOST` 和 `PORT` 修改。默认 ICE 使用公共 STUN，严格 NAT 环境可在 `ICE_SERVERS` 加入自己的 TURN 并重启服务。

```powershell
$env:ICE_SERVERS = '[{"urls":["stun:stun.l.google.com:19302"]},{"urls":["turn:turn.example.net:3478"],"username":"demo","credential":"replace-me"}]'
node server/server.mjs
```

## 机制参考

- [Blobfish 的 Brotato 游戏说明](https://store.steampowered.com/app/1942280/Brotato/)
- [Brotato Wiki 波次时长](https://brotato.wiki.spellsandguns.com/Waves)
- [Brotato Wiki Danger 难度](https://brotato.wiki.spellsandguns.com/Danger_Levels)
- [Brotato Wiki 材料与材料袋](https://brotato.wiki.spellsandguns.com/Materials)
- [Brotato Wiki 商店与刷新](https://brotato.wiki.spellsandguns.com/Shop)
- [Brotato Wiki 武器与套装](https://brotato.wiki.spellsandguns.com/Weapons)

## 自动回归

```powershell
godot --headless --path . --script tests/balance_test.gd
npm test
```
