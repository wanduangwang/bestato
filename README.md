# bestato

用 Godot 4 和 GDScript 实现的《土豆兄弟》风格原型。支持单机和 2–4 人网页合作。角色、敌人、武器造型和音效均由项目代码生成。

## 试玩

从仓库克隆后，先按下文的导出步骤生成 `web/index.html`。在项目根目录用 Node.js 20 或更高版本运行 `node server/server.mjs`，打开 [本机游戏](http://127.0.0.1:8787)。

- **单机**：点 **Deploy Solo**，选择角色和初始武器，再点 **Deploy**。
- **联机**：一个窗口点 **Create Room**，其余窗口在同一地址输入六位房间码并点 **Join**。每人选择自己的角色和武器，客机点 **Ready Up**，房主点 **Deploy**。更新版本后请刷新所有窗口。
- **战斗**：WASD 移动，武器自动瞄准射程内的目标。绿色材料同时增加经验和商店余额，水果回血，箱子在波间开。未捡的材料进袋，后续会加到新的掉落上。
- **波间**：先选升级、开箱，再从四个商品中买武器或被动物品。**Lock** 保留商品，**Reroll** 刷新货架。两把同名同级武器可以 **Merge**，**Sell** 可回收。每人有独立商店，全部 **Ready** 后进入下一波，血量回满并复活倒下的队友。

共 20 波。首波 20 秒，常规波逐步增长至 60 秒，终波 90 秒。部署前可选择 **Danger 0–5**。从 Danger 2 起有精英，从 Danger 4 起增加群潮和第二场精英战，Danger 5 的终波有双首领。撑过终波胜利，全队倒地结束。当前内容池有 4 个角色、13 种武器、24 件被动物品和 16 项升级属性，数值针对这套内容池调校。

## 源码与网页导出

使用 Godot 4.3 或更高版本的标准版编辑器，打开 `project.godot` 后按 **F5** 可玩单机。网页构建使用 **Compatibility** 与单线程模板。在编辑器的导出模板管理器安装同版本模板，再导出自带的 **Web** 预设。命令行示例中的 `godot` 可换成实际可执行文件路径。

```powershell
godot --headless --path . --export-release Web web/index.html
node server/server.mjs
```

| 路径 | 职责 |
| --- | --- |
| `scenes/` | 主场景、玩家和敌人节点 |
| `scripts/game/catalog.gd` | 角色、武器、物品与属性数据 |
| `scripts/game/build.gd` | 个人构筑、品质、套装、升级和商店 |
| `scripts/game/arena.gd`、`waves.gd` | 房主权威的战斗、波次、掉落与结算 |
| `scripts/game/player.gd`、`enemy.gd`、`world_view.gd`、`sounds.gd` | 角色状态、敌人行为、效果与程序音效 |
| `scripts/network/network.gd` | 信令、WebRTC 和游戏 RPC |
| `scripts/ui/interface.gd` | 菜单、角色选择、HUD、升级与个人商店 |
| `server/server.mjs` | 同源网页托管与房间信令 |

## 联机部署

房主是 Peer 1。信令服务以六位房间码管理内存中的房间，转发 SDP/ICE。每位客机与房主建立一条 WebRTC 连接，房主负责刷怪、弹丸、伤害、材料分配与交易校验。位置和战斗画面走短周期快照，个人构筑和商店命令走可靠 RPC，命令附带版本号以阻止旧界面重复扣款。客机加入进行中的房间时会获得按波次计算的基础装备和材料。房主退出后房间关闭。

异地试玩时，把 Node 服务通过 HTTPS 反向代理对外提供，保持网页和 `/signal` 同源。默认监听 `127.0.0.1:8787`，可用 `HOST` 和 `PORT` 修改。默认 ICE 使用公共 STUN，严格 NAT 环境可在 `ICE_SERVERS` 加入自己的 TURN 并重启服务。

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
