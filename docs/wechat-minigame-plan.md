# bestato 微信小游戏开发方案

微信首版保留单人波次生存、2–4 人合作、房间码、只读观战和中英文偏好。开发分支为 `feature/wechat-minigame`，基于网页版本 `89d0c23`。现有战斗、波次、构筑和商店逻辑继续用 GDScript。微信运行环境的调用集中在输入、存储、网络和导出适配中。

## 第一阶段　真机玩完第一波

1. 用与 Godot 4.6.3 配套的微信兼容模板生成独立小游戏工程。先在隔离目录验证模板，再固定版本与 SHA-256。当前网页导出约 41 MiB，候选微信引擎经过 Brotli 压缩约 6 MiB。主包放启动代码和加载界面，引擎与游戏资源放普通分包。分别记录上传主包、总包和冷启动到可操作的时间。微信当前的上传限制为主包 4M、主包加分包 30M。[4.6.3 模板](https://github.com/AnranS/godot_for_minigame/releases/tag/template-4.6.3-stable-emsdk-4.0.3-2d-full-release-abi-1-r1) · [微信分包规则](https://developers.weixin.qq.com/minigame/dev/guide/base-ability/subPackage/useSubPackage.html)
2. 首版使用横屏。给自动攻击玩法加虚拟摇杆，手指抬起、触点取消或切后台时立刻清除移动输入。按手机安全区调整 HUD 和商店点击区域，检查中文换行、窄屏与圆角屏。录入房间码时使用微信键盘，语言和音效通过微信存储接口保存。[小游戏配置](https://developers.weixin.qq.com/minigame/dev/reference/configuration/app.html)
3. 在一台 iOS 和一台 Android 设备上从冷启动进游戏，用触屏打完第一波、进入商店并完成一次购买。重启后确认语言和音效设置恢复，切前后台后确认输入正常。记录机型、微信版本、启动耗时和帧率，作为后续性能对照。

## 第二阶段　四人联机与观战

- 微信客户端通过 `wx.connectSocket` 连接 Node 中继。复用现有房间码、席位管理和房主权威模拟。加入、观战和离开都由服务端确认角色，观众只收到公开快照，队员各自收到私有构筑与商店信息。观众席在应用层不设人数上限，按实测连接量和出站带宽评估服务器容量。[微信网络要求](https://developers.weixin.qq.com/minigame/dev/guide/base-ability/network.html)
- 玩家输入、商店操作、战斗快照沿用现有的职责边界。对慢连接只保留待发送的最新画面快照，可靠交付准备和购买等结果。房主断线时向参与者明确提示房间结束。需要从微信邀请进入时，分享携带房间码，让服务端按当前席位状态处理加入或观战。
- 用四个战斗端和一个观战端验收。同一房间满员时第五端可在战斗或波间加入观战。关闭一名客机后，空席继续锁定且本波仍按四人处理。剩余三人准备后，下一波刷怪和敌人生命显示 **×1.60**、伤害显示 **×1.16**，房主、客机与观众看到一致结果。用已登记的域名在 Wi‑Fi 和移动网络实测，并复跑多观众服务端回归。

## 第三阶段　体验版与提审

- 复测低配置 Android 在怪潮和多观众时的表现。用第一阶段的启动时间和帧率作对照，优先处理首屏等待、内存峰值和可降低的绘制开销。确认调整后同一波的刷怪、伤害和掉落倍率仍与规则一致。
- 与适配并行确认发布主体、小游戏 AppID、发布名和实际类目。当前方案按长期不开通虚拟支付评估。英文发布名 `bestato` 对应软著或相应授权材料要求。正式联机域名使用 HTTPS/WSS，按微信要求完成 ICP 备案和域名配置。[非内购资质](https://developers.weixin.qq.com/minigame/introduction/guide/zzsh-iaa.html) · [微信接入指南](https://developers.weixin.qq.com/minigame/introduction/guide/)
- 上传体验版后，用实际提审构建准备游戏截图、房间和观战说明、隐私指引及适龄提示。完成小游戏备案、小程序备案和版本审核后发布联机版。[小游戏备案](https://developers.weixin.qq.com/minigame/introduction/guide/nrjs.html) · [版本审核](https://developers.weixin.qq.com/minigame/introduction/guide/bbsh.html)

首个可验收交付是 **可扫码的横屏真机包**，包含触屏完成第一波、进入商店和重启恢复设置的记录。第二个交付是 **可邀请队友的联机体验版**，以跨设备四人和观战复验为验收依据。
