# 按设备隔离的配置档（Per-Device Profiles）— 设计

日期：2026-09-25
状态：草案，待评审

## 背景与问题

目前 FaceLift 的所有"资源"都是全局的，与连接的是哪台 iPhone 无关：

| 资源 | 现在的位置 | 代码 |
| --- | --- | --- |
| 卡片哈希列表 | `Application Support/FaceLift/cards.json`（单个数组） | `AppViewModel.cardsStoreURL`、`facelift.CARDS_STORE_PATH` |
| 卡面图片 | `Application Support/FaceLift/skins/<hash>.png` | `AppViewModel.storedSkinURL(for:)` |
| 当前设备 | 每 8 秒轮询 `--device`，后端从枚举结果里挑一台 | `MainWindow` 定时器、`facelift.get_connected_device()` |
| 密码缓存备份 | `PasscodeCacheBackups/<udid>/<version>/<token>`（**已经按设备隔离**） | `apply_card_skin.clear_passcode_cache` |
| 已载入 .passthm、主题创作器 | 仅内存 | `loadedPasscodeTheme`、`creator*` |

由此产生的具体故障：

1. **写错设备**：在 A 上扫描/导入的卡片，换接 B 后仍出现在列表中且默认可勾选；`applySkin()` 只校验 `device?.udid` 非空（`AppViewModel.swift` `applySkin` 开头），会把 A 的哈希写到 B 的 `/var/mobile/Library/Passes/Cards/<hash>.pkpass`。B 上不存在该 pass 时，结果是在 B 上创建垃圾目录或写入失败；若恰好存在同名哈希（iCloud 同步的非支付类 pass 在两台设备上哈希可能相同），则会用 A 的设计覆盖 B 的卡面。
2. **卡面串台**：`skins/<hash>.png` 全局唯一，B 上"读取卡面"会覆盖 A 保存的同名文件。
3. **异步任务跨设备**：`pumpSkinPulls()` 每次出队时重新读取 `device?.udid`，队列中途换机会用 B 的 UDID 去读 A 的卡片，结果写回共享的 `skins/`；扫描（syslog）结束后把结果并入"当前" `cards`，而那时 `cards` 可能已属于另一台设备。
4. **多台同时连接时来回跳**：`get_connected_device()` 在枚举顺序不稳定时只按"iPhone 优先 + USB 优先"选一台，A、B 同时插着且传输方式相同时，每次轮询都可能选中不同设备。一旦引入按设备切换，这会变成"每 8 秒切换一次配置档"。

## 目标

- 以 **UDID** 为单位管理环境：每台 iPhone 拥有独立的卡片列表、卡面图片、密码主题应用记录。
- 任何写设备的操作（刷卡面、刷密码主题、恢复默认密码）只能针对 **当前活动配置档对应且此刻已连接** 的那台设备，并且只能使用该配置档里的数据。
- 换机时自动切换配置档，不需要用户操作；断开时不丢数据。
- 旧版本的全局数据安全迁移，不猜测归属。

非目标（本期不做）：

- 跨设备复制卡片（哈希通常不同，没有可靠映射）。可以后续做"把 A 的某张卡面图片应用到 B 的某张卡"的手动操作。
- 同时对多台设备批量写入。

## 核心原则

1. **配置档键 = UDID**。同一台手机通过 USB 或 Wi‑Fi 连接 UDID 相同，属于同一配置档；名称（"xx 的 iPhone"）只是展示字段，可改名、可重复，不能作键。
2. **(udid, hash) 才是卡片的唯一标识**，卡面文件放在设备目录下，永不跨设备共享。
3. **操作绑定设备**：每个异步操作在开始时捕获 `targetUDID`，整个生命周期（包括结果回写）只针对这个 UDID 的配置档，与 UI 此刻显示哪个配置档无关。
4. **写入前三重校验**（见"安全护栏"）。

## 1. 存储布局

```
~/Library/Application Support/FaceLift/
├── devices.json                      # 设备索引
├── Devices/
│   └── <udid>/
│       ├── profile.json              # 该设备的卡片与状态
│       └── skins/<hash>.png          # 该设备的卡面
├── PasscodeCacheBackups/<udid>/...   # 维持现状（已按设备隔离）
└── Legacy/                           # 迁移后留存的旧全局数据（见 §5）
    ├── cards.json
    └── skins/
```

`devices.json`：

```json
{
  "schema": 1,
  "lastActiveUDID": "00008140-000A1B2C3D4E5F6A",
  "devices": [
    {
      "udid": "00008140-000A1B2C3D4E5F6A",
      "name": "A 的 iPhone",
      "customName": null,
      "product": "iPhone17,1",
      "lastVersion": "27.0",
      "firstSeen": "2026-09-25T10:00:00Z",
      "lastSeen": "2026-09-25T12:30:00Z"
    }
  ]
}
```

`Devices/<udid>/profile.json`：

```json
{
  "schema": 1,
  "udid": "00008140-000A1B2C3D4E5F6A",
  "cards": [
    { "id": "M6nD...=", "addedAt": "2026-09-25T10:05:00Z", "source": "scan" }
  ],
  "passcode": {
    "lastAppliedTheme": "Ocean",
    "lastAppliedVersion": "TelephonyUI-10",
    "lastAppliedAt": "2026-09-25T11:00:00Z",
    "languageTarget": "zh",
    "boldTarget": "both"
  }
}
```

说明：

- `source` 取值 `scan | manual | legacy`，便于排查"这张卡从哪来的"。
- 目录名使用 UDID，写入前用与 `clear_passcode_cache` 相同的正则 `^[A-Za-z0-9-]{16,80}$` 校验，避免路径注入。
- 所有写入走"写临时文件 + 原子替换"（Swift `.atomic`，Python `os.replace`），防止 Swift 与 Python CLI 并发写坏文件。
- `cards.json`（旧全局文件）不再写入。

## 2. 运行时模型

新增 `Model/DeviceProfileStore.swift`，只做文件读写，不依赖 UI，便于测试：

```swift
struct DeviceRecord: Codable, Identifiable { let udid: String; var name, customName, product, lastVersion: String?; var firstSeen, lastSeen: Date; var id: String { udid } }
struct StoredCard: Codable { let id: String; var addedAt: Date; var source: String }
struct DeviceProfile: Codable { var schema = 1; let udid: String; var cards: [StoredCard]; var passcode: PasscodeRecord? }

enum DeviceProfileStore {
    static func loadIndex() -> DeviceIndex
    static func saveIndex(_: DeviceIndex)
    static func loadProfile(udid: String) -> DeviceProfile      // 不存在则返回空配置档
    static func saveProfile(_: DeviceProfile)
    static func skinURL(udid: String, cardId: String) -> URL
    static func deleteProfile(udid: String)                     // "忘记此设备"
}
```

`AppViewModel` 的变化：

- 新增 `@Published private(set) var activeProfileUDID: String?` 和 `@Published var knownDevices: [DeviceRecord]`。
- `cards` 语义改为"活动配置档的卡片"，其余视图代码基本不变。
- `saveCards()`、`storeSkin`、`clearCardImage`、`addCardHash`、`deleteCard`、`clearAllCards` 全部改为作用于 `activeProfileUDID`；`activeProfileUDID == nil` 时这些入口禁用。
- 新增 `var canWriteToDevice: Bool { device?.connected == true && device?.udid == activeProfileUDID }`，工具栏 Flash、读取卡面、扫描、恢复默认密码统一依赖它。
- `storedSkinURL(for:)` 改为 `DeviceProfileStore.skinURL(udid:cardId:)`，调用方必须显式传 UDID。

## 3. 设备切换流程

在 `checkDevice()` 拿到结果后执行 `reconcileActiveProfile(with: dev)`：

```
已连接 且 dev.udid != activeProfileUDID:
    1. 若正在扫描 → stopCardScanning()（扫描绑定旧 UDID，结果写回旧配置档）
    2. 清空 skinPullQueue（队列项属于旧设备）
    3. 保存旧配置档
    4. 载入/创建 dev.udid 的配置档；更新 devices.json 的 name/product/lastVersion/lastSeen/lastActiveUDID
    5. cards = 新配置档卡片；previewCardIndex 归零；selection 全部清空
    6. 状态栏 + 日志："已切换到「B 的 iPhone」的配置（N 张卡片）"
已连接 且 udid 相同:
    仅刷新 lastSeen / name / 版本（不重新加载列表，避免打断编辑）
未连接:
    保留当前配置档（离线态），不切换、不清空
```

启动时：先按 `lastActiveUDID` 载入配置档（离线显示），首次 `checkDevice` 后再按上面的规则校正。

**进行中的写操作不允许被切换打断**：现有定时器在 `isFlashing / isScanningCards / isPullingSkins` 时已跳过轮询；手动"刷新设备"也要加同样的判断。刷写过程中拔线由后端失败路径处理，结束后下一次轮询才切换。

### 多台设备同时连接

后端 `--device` 增加可选参数 `--prefer <udid>`，选择规则变为：

1. `prefer` 仍在可用列表里 → 选它（**粘性**，消除来回跳）；
2. 否则沿用现有"iPhone 优先 + USB 优先"。

同时在输出中附带 `"available": [{udid, name, product, connection}, ...]`。当 `available` 里有多台 iPhone 时，侧边栏设备行变为 `Menu`，允许用户手动切换；手动选择写入 `lastActiveUDID`，下一次轮询即作为 `prefer` 传入。

## 4. 安全护栏（防止把 A 的卡写进 B）

三层，任意一层不通过都拒绝写入：

1. **UI 层**：`canWriteToDevice` 为假时 Flash / 读取 / 扫描按钮禁用，并在状态栏说明原因（例如"当前显示的是「A 的 iPhone」的配置，但连接的是「B 的 iPhone」"——正常情况下切换是自动的，这一条主要覆盖切换尚未完成的窗口期）。
2. **ViewModel 层**：`applySkin()`、`flashPasscodeTheme()`、`restoreDefaultPasscode()`、`queueSkinPulls()` 开头统一调用
   ```swift
   func beginDeviceOperation() -> String? // 返回 targetUDID；不满足 canWriteToDevice 返回 nil 并报错
   ```
   待写卡片从 `DeviceProfileStore.loadProfile(udid: targetUDID)` 与当前选择求交集，而不是直接用 `self.cards`。异步回写（读取卡面结果、扫描到的新哈希）一律写入 `targetUDID` 的配置档；只有当 `targetUDID == activeProfileUDID` 时才同步刷新 UI 的 `cards`。
3. **后端层**：`facelift_backend.py --flash <udid> <hash> <image>` 在写入前读取 `Devices/<udid>/profile.json`，若 `hash` 不在其中则输出 `{"type":"error","reason":"card_not_in_profile"}` 并退出 1。这样即使将来 UI 出 bug，也不会向错误的设备写入不属于它的哈希。`--pull-card` 同样校验，并把目标路径限制在 `Devices/<udid>/skins/` 下。

`pumpSkinPulls()` 的队列项改为 `(udid, cardId)`，出队时若 `udid != device?.udid` 直接丢弃，不再读取"当前设备"。

## 5. 旧数据迁移

旧的 `cards.json` / `skins/` **无法知道属于哪台设备**，因此不自动归属，避免一上来就把 A 的卡归给 B：

1. 首次启动新版本时，把 `cards.json` 和 `skins/` 移动到 `Legacy/`（原地移动，不复制，不删除）。旧 dotfile / UserDefaults 迁移逻辑保持不变，但目标改为 `Legacy/cards.json`。
2. 首次连接任意设备时，若 `Legacy/` 非空且该设备配置档为空，弹出一次性提示：
   > 发现旧版本保存的 N 张卡片，它们属于当前连接的「B 的 iPhone」吗？
   > [归入此 iPhone]　[稍后决定]　[不再提示]
3. "归入"：把哈希写入该设备配置档（`source: "legacy"`），把对应 `skins/<hash>.png` **复制**到该设备目录；`Legacy/` 保留（用户可能还有另一台手机需要认领）。
4. 设备页提供"从旧版数据导入…"入口，任何时候都可以把 Legacy 卡片按勾选导入到当前设备配置档。
5. 可选的核实：导入后可对导入的卡执行一次"读取卡面"——`read_card_artwork` 在设备上找不到该 pass 时返回 `missing`，据此把"此设备上不存在"的卡标灰并建议移除。这比较慢（每张卡一次 AirTraffic 同步），所以只做成手动按钮，不自动执行。

命令行 `facelift.py` 同步修改：它在 `main()` 中已经拿到 `device["udid"]`，把 `load_saved_cards()` / `save_cards()` 改为接收 `udid`，读写 `Devices/<udid>/profile.json`。

## 6. 密码主题与主题创作器

- **主题创作器**：保持全局。它是"设计稿"，和设备无关，换机后继续编辑是合理的。
- **已载入的 .passthm**：保持全局（只是选中的文件），但刷写目标永远是活动配置档的设备，`TelephonyUI` 版本仍从该设备的 iOS 版本推导（现有逻辑）。
- **按设备记录**：`languageTarget` / `boldTarget` 按设备保存（两台手机系统语言可能不同），切换设备时恢复；每次成功刷写后记录 `lastApplied*`，在设备页展示"上次应用的密码主题"。
- `PasscodeCacheBackups/<udid>/` 已按设备隔离，不改。

## 7. 界面

- **侧边栏设备行**：显示活动配置档名称和状态点。已连接 = 现有绿/橙；离线 = 灰点 + "未连接（显示上次的配置）"。多台同时连接时变为可点开的菜单。
- **卡片页**：离线或 UDID 不匹配时，顶部 `NoticeBar` 显示"当前为「A 的 iPhone」的配置，连接此 iPhone 后才能写入"；列表仍可编辑（添加/删除卡片、换图），因为这些只改本地配置档。
- **设备页**新增"已知的 iPhone"分组（`Form` + `Section`）：每行显示名称、型号、iOS、上次连接时间、卡片数；操作：重命名（只改 `customName`）、切换查看（离线查看某设备配置档）、忘记此设备（删除 `Devices/<udid>/`，二次确认）、从旧版数据导入。
- 新增本地化字符串走 `tools/add_strings.py`，同时补 `en` 与 `zh-Hans`。

## 8. 边界情况

| 场景 | 处理 |
| --- | --- |
| 同一台手机 USB ↔ Wi‑Fi 切换 | UDID 不变，不切配置档，只更新 connection |
| 手机抹掉/恢复后重新添加卡片 | UDID 不变但哈希变了；旧卡通过"读取卡面 → missing"标灰，或用户"清空卡片"重扫 |
| 两台手机 iCloud 同步了同一张非支付 pass，哈希相同 | 各自配置档各有一份记录和卡面文件，互不影响 |
| 刷写途中拔线 | 后端失败返回；刷写结束前不切换；下一次轮询切换 |
| 扫描途中换机 | 切换前先停止扫描；扫描结果写回扫描开始时的 UDID |
| 读取队列途中换机 | 队列清空；已在执行的那一项结果写回原 UDID 的目录 |
| 同时插两台 | 粘性选择 + 手动菜单切换 |
| 离线查看 A、此时插入 B | 自动切到 B（连接的设备优先于离线查看），日志说明 |
| 用户"忘记"了当前连接的设备 | 删除后立即以空配置档重建（设备仍连接） |

## 9. 测试

- Python：扩展 `tests/test_card_store.py` → 按 UDID 读写、UDID 非法时拒绝、旧数据迁移到 `Legacy/` 且只迁一次、`--flash` 在哈希不属于该 UDID 时拒绝（mock `write_files_batch`，断言未被调用）。
- Swift（`tests/swift/`，沿用 `CreatorDropRoutingTests` 的形式）：把 `reconcileActiveProfile` 的决策抽成纯函数 `ProfileSwitchDecision.decide(active:, device:, busy:) -> .keep / .switchTo(udid) / .goOffline`，覆盖上表各行。
- 手动：A 导入卡片 → 换 B → 列表为空、Flash 禁用直到扫描到 B 的卡 → 换回 A → 列表与卡面恢复；A、B 同时连接不跳变。

## 10. 实施分期

1. **P1 数据隔离与护栏**（必须一起上线，否则切换引入的新风险大于收益）：`DeviceProfileStore`、存储布局、Legacy 迁移与认领提示、`reconcileActiveProfile`、粘性设备选择（`--prefer`）、ViewModel 层与后端层护栏、异步任务绑定 UDID、Python CLI 同步。
2. **P2 管理界面**：设备页"已知的 iPhone"、重命名/忘记/离线查看、多设备菜单、按设备记住密码主题语言与粗体选项。
3. **P3 核实**：导入后的"检查卡片是否在此设备上"。

## 待决策

| # | 问题 | 建议 |
| --- | --- | --- |
| 1 | 旧全局卡片如何归属 | 放入 `Legacy/`，首次连接时询问一次（§5）。不自动归给第一台连接的设备 |
| 2 | 未连接时显示什么 | 显示上次活动配置档，可编辑、不可写入 |
| 3 | 主题创作器 / 已载入 .passthm 是否按设备隔离 | 否，保持全局；只按设备记录应用历史与语言/粗体选项 |
| 4 | 后端是否强制校验哈希归属 | 是（§4 第 3 层），代价很小 |
