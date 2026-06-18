# KeepAwake — ESP32-C3 BLE 防 iPhone 锁屏键盘

把一块 **ESP32-C3 SuperMini** 变成 **BLE 蓝牙键盘**,配对到 iPhone/iPad 后,只要它连着、通着电,就每隔 15 秒发一次按键。iOS 把它当成"有人在操作",重置自动锁屏计时器,屏幕就不会自动锁。

本质是一个 USB 供电的"防锁屏小配件":想防锁屏就插电连着,不想要了直接拔 USB。

## 工作原理

通电 → BLE 广播(LED 慢闪)→ iPhone 配对成功(LED 常亮)→ 此后每 15 秒发一个按键 → iOS 刷新自动锁屏计时器 → 不锁屏。

## 关键设计:为什么默认用 Shift(以及 F15 备选)

- **理论**:在 HID 协议里,修饰键(Shift/Ctrl/Alt)走的是独立的 1 字节 bitmask,和普通按键分开。多份资料显示 iOS 经常**不把单独的修饰键当成有效输入**,所以"只发 Shift"理论上不可靠,业界推荐发一个真实的非修饰键(如 **F15**,无字符、无可见效果、iOS 上无默认绑定)。
- **实测**:但本项目在真机 iPhone 上实测,`KEY_LEFT_SHIFT` **确实**防住了锁屏。
- **结论**:默认用 Shift;万一在你的设备上失效,把 `src/main.cpp` 里的 `WAKE_KEY` 从 `KEY_LEFT_SHIFT` 改成 `KEY_F15` 即可(一行)。

## 准备

- 一块 ESP32-C3 SuperMini
- 一根**能传数据**的 USB-C 线(很多廉价线只能充电,刷不进去也认不到设备)
- [PlatformIO](https://platformio.org/)(VS Code 插件或命令行)

## 烧录(PlatformIO,推荐)

> ⚠️ `platformio.ini` 里的版本号是**锁死的、不能升级**。T-vK 库只能在 arduino-esp32 core 2.0.x + NimBLE 1.4.x 上编译,升到 NimBLE 2.x 或 core 3.x 都会编译失败。原因见文件注释。

```bash
cd KeepAwake
pio run                 # 首次会自动下载工具链 + 库,要等几分钟
pio run -t upload       # 插上板子后烧录
pio device monitor      # 可选:看串口日志(115200),确认 connected / sent key / 芯片温度
```

如果 `upload` 卡在 `Connecting...`:按住板子上的 **BOOT** 键 → 点一下 **RESET** 键 → 松开 BOOT,进下载模式,再重新 `pio run -t upload`。

## 烧录(Arduino IDE 备选,未实测)

1. 开发板管理器装 **esp32 by Espressif 2.0.17**(不要 3.x)。
2. 库管理器装 **ESP32 BLE Keyboard by T-vK 0.3.2-beta** 和 **NimBLE-Arduino 1.4.3**。若搜不到 beta,从 [GitHub releases](https://github.com/T-vK/ESP32-BLE-Keyboard/releases) 下 zip 手动导入。
3. 在库的 `BleKeyboard.h` 顶部启用 `#define USE_NIMBLE`。
4. 开发板选 **ESP32C3 Dev Module**,设 **Tools → USB CDC On Boot → Enabled**。
5. 把 `src/main.cpp` 内容拷进 `.ino` 编译上传。

## 配对 iPhone

1. 烧录完成,板子蓝灯**慢闪**(= 上电、广播中、等连接)。
2. iPhone **设置 → 蓝牙**,"其他设备"里找到 **KeepAwake**,点它配对。
3. 配上后蓝灯**常亮**,串口打印 `connected`,之后每 15 秒打印一次 `sent key` + 芯片温度。
4. **设置 → 显示与亮度 → 自动锁定** 随便设;只要板子连着就不会到点锁屏。

## 重要行为说明(务必先读)

- **只在"连着 + 通电"时生效。** 想防锁屏就插着电;拔掉 USB,iPhone 立刻恢复正常自动锁屏。这就是最简单的开关。
- **它会把屏幕一直点亮。** 按键不仅阻止锁屏,还能把熄屏的 iPhone 唤醒。所以只要连着,屏幕基本一直亮。
- **连着硬件键盘时,iOS 不弹屏幕软键盘。** iOS 固有行为,对纯防锁屏配件无影响。
- **间隔 15 秒是有意为之。** iOS 自动锁定最短档 30 秒(低电量模式强制 30 秒),15 秒留 2 倍余量抗蓝牙抖动。别改到 25–30 秒。

## 关于发热(重要,有完整调查结论)

板子工作时芯片区会**温热甚至偏烫**,`temperatureRead()` 读到的芯片结温可能 ~70°C。**这基本是正常的**,结论如下(经多轮研究 + 实测):

- **70°C 结温是安全的。** ESP32-C3 结温上限 105°C 以上,70°C 远在安全区,不损坏、不减寿。表面"烫手"(约 50°C)是 ESP32 持续联网工作的常态。`temperatureRead()` 在 C3 上还**偏高**,真要判断应测电流而非看这个数。
- **真正的热源是板载 LDO,不是芯片。** C3 在 BLE 连接态只耗约 6–20 mA ≈ 20–66 mW,本身只比环境高 1–3°C。热主要来自板载 LDO 把 USB 的 5V 降到 3.3V 的压降发热(P=(5−3.3)×I);2×2cm 小板上 LDO 紧挨 C3,热会传导到芯片区。
- **降 CPU 频率几乎无效。** 实测把 CPU 从 160→80MHz,温度稳态**纹丝不动**(降频只省约 6 mA ≈ 20 mW,而 LDO 烧 ~42 mW,核心这点变化在封装上 <1°C,测不出)。
- **不能再往下降频。** 80MHz 是 BLE 工作的实际下限(射频需 APB=80MHz)。`setCpuFrequencyMhz(40)` 不会报错但会真降,APB 掉到 40MHz → **蓝牙断连 + 串口乱码**(arduino-esp32 issue #6032/#7182)。
- **light sleep 在这条路上行不通,而且也不降温。** PlatformIO 的预编译 arduino 库里 `CONFIG_PM_ENABLE` 是关闭的,`esp_pm_configure()` 能编译但运行时返回"不支持",芯片永不睡;要真开启必须切 ESP-IDF 框架或自己重编 core。即便做成,芯片本就只发几十 mW,对 LDO 压降发热也几乎无用。
- **想真正降温,只能从 LDO 下手**:实测换一块全新同款板**也没用**(两块结温几乎一样、都烫),坐实这是 SuperMini 的设计通病、不是个别板缺陷。唯一有效的硬办法是用干净的 3.3V 从 3V3 引脚直供、绕过板载 LDO(**注意不可超过 3.6V,否则烧芯片**)。否则——接受现状,它是安全的。

## 故障排查

| 现象 | 处理 |
|---|---|
| 电脑认不到板子 / `pio device list` 没有 ESP32 串口 | 多半是**纯充电 USB 线**——换数据线;确认直插电脑 USB 口;换口多插拔几次 |
| 串口监视器一片空白 | 确认 `-D ARDUINO_USB_CDC_ON_BOOT=1` 在(本工程已带);换数据线;复位后端口号可能变,重选 |
| `upload` 连不上 | 按住 BOOT → 点 RESET → 松 BOOT 进下载模式,再传 |
| 配对成功但**不防锁屏 / 收不到按键**(尤其重启/断电再上电后) | T-vK 库在 C3 已知的重连鉴权 bug(`GATT_INSUF_AUTHENTICATION`)。**最简单:iPhone 蓝牙里"忽略此设备",重新配对一次。** 每次上电都犯的话,换 C3 专用分支 [`oden-umaru/ESP32C3-BLE-Keyboard@0.3.3`](https://github.com/oden-umaru/ESP32C3-BLE-Keyboard)(内置鉴权修复) |
| 编译报 `UnknownPackageError ... t-vk/ESP32 BLE Keyboard` | registry 没收这个 beta;本工程用 git URL 拉取,别改回 registry 写法 |
| 编译报 `NimBLEAdvertising does not name a type` 之类 | NimBLE 被升到 2.x 了,确认锁在 `@1.4.3`,清 `.pio` 重编 |
| 蓝牙距离很近就断 | C3 SuperMini 板载陶瓷天线偏弱,让天线那头远离金属/手指/电池 |

## 可调参数(都在 `src/main.cpp` 顶部)

- `SEND_INTERVAL_MS` —— 发送间隔,默认 `15000`(15 秒)。
- `WAKE_KEY` —— 默认 `KEY_LEFT_SHIFT`;失效就换 `KEY_F15`(或 F13/F14)。
- `BleKeyboard("KeepAwake", ...)` —— iPhone 蓝牙列表里显示的名字。
- `setCpuFrequencyMhz(80)` —— 别低于 80,否则 BLE 断连。

## 验证状态

- ✅ PlatformIO 编译通过(`espressif32@6.9.0`→core 2.0.17、`NimBLE-Arduino@1.4.3`、git tag `0.3.2-beta`、`USE_NIMBLE`),生成 `firmware.bin`,占用 RAM ~7% / Flash ~40%。
- ✅ 实机烧录成功,真机 iPhone 配对成功、防锁屏生效(Shift 实测有效)。
- ⚠️ 发热结论见上;`temperatureRead` 实测稳态 ~70°C,降频无效已验证。
