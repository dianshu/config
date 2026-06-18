# LESSONS — ESP32-C3 BLE 防锁屏键盘踩坑与可复用经验

这份笔记记录用 ESP32-C3 SuperMini 做 BLE HID 键盘(防 iPhone 锁屏)过程中,那些**文档里不写、靠踩坑才知道**的点。多数对任何 "ESP32-C3 + BLE + PlatformIO/Arduino" 项目通用。

---

## 1. PlatformIO 装不到 T-vK 库的 pre-release —— 用 git URL

`lib_deps = t-vk/ESP32 BLE Keyboard@0.3.2-beta` 会报
`UnknownPackageError: Could not find the package`。PlatformIO registry **不收录这个 pre-release 版本**。

✅ 改用 git tag 直拉(`0.3.2-beta` 是有效 git ref):
```ini
lib_deps =
    https://github.com/T-vK/ESP32-BLE-Keyboard.git#0.3.2-beta
```
通用教训:registry 里找不到某个 beta/rc 版时,先确认它是不是 git tag,用 `<repo>.git#<tag>` 拉。

## 2. C3 + T-vK BLE Keyboard 的版本是锁死的,升级必崩

T-vK 库(最后更新 2024)只在**旧工具链**上编译。两个会编译失败的升级:
- **NimBLE-Arduino 2.x** → `'NimBLEAdvertising' does not name a type`(API break)。
- **arduino-esp32 core 3.x** → `BLEDevice::init()` 的 `std::string` vs Arduino `String` 冲突。

✅ 锁死组合(实测可编译可运行于 C3):
```ini
platform = espressif32@6.9.0     ; => arduino-esp32 core 2.0.17
lib_deps =
    https://github.com/T-vK/ESP32-BLE-Keyboard.git#0.3.2-beta
    h2zero/NimBLE-Arduino@1.4.3   ; 最后一个 1.x
build_flags = -D USE_NIMBLE       ; C3 上必须,否则默认 Bluedroid 连广播都不发
```
注:T-vK 库没有 `library.json`,不会自动拉 NimBLE;**务必手动 pin `@1.4.3`**,否则 unpinned 会解析到最新的 2.x 而编译失败。

## 3. iOS 防锁屏:Shift 理论不可靠,但本案实测有效(反直觉)

- **理论**:HID 修饰键(Shift/Ctrl/Alt)走独立的 1 字节 bitmask,和普通键码数组分开。多份资料(iPadOS 18.x、iOS 13 报告)显示 iOS 常**不把单独修饰键当有效输入**。业界(QMK jiggler 等)标准做法是发**真实非修饰键**,首选 **F15**(无字符、无可见效果、iOS 无默认绑定)。
- **实测反转**:本项目在真机 iPhone 上,**单发 `KEY_LEFT_SHIFT` 确实防住了锁屏**。
- **教训**:`temperatureRead` 之类的"理论结论"要用实测校准;同时代码里保留 F15 作为一行可切换的 fallback,两头都不赌死。

## 4. C3 没有 USB-UART 桥,串口走原生 USB-CDC

C3 SuperMini 只有一个 USB-C,是芯片**原生 USB Serial/JTAG**,没有 CP2102/CH340。
- 要在 USB-C 上看 `Serial` 输出,必须 `-D ARDUINO_USB_CDC_ON_BOOT=1`,否则 `Serial` 绑到静默的硬件 UART0,监视器一片空白(但烧录仍可能成功 → 容易误判"没跑起来")。
- **不要用 `while(!Serial){}`**——USB-CDC 下可能挂死。用 `delay(200)` 代替。
- 上传失败时手动进下载模式:**按住 BOOT(GPIO9)→ 点 RESET → 松 BOOT**。

## 5. 发热根因:是板载 LDO,不是芯片(关键认知)

C3 SuperMini 工作时芯片区偏烫(`temperatureRead` ~70°C)。排查结论:
- C3 在 BLE 连接态只耗 ~6–20 mA ≈ 20–66 mW,本身只比环境高 1–3°C,**不该烫手**。
- 真热源是**板载 LDO 把 5V 降到 3.3V 的压降发热**(P=(5−3.3)×I);2×2cm 小板上 LDO 紧挨芯片,热传导过去,所以"摸芯片区烫"其实是 LDO 的热。
- 判据:换不同的干净 5V 电源(电脑口/显示器口)都烫 → 排除外部电源;摸热点区分芯片区 vs USB 口 LDO 区。**最准的是用 USB 电流表测电流**(正常 BLE 连接应 <30 mA),而不是信 `temperatureRead`。
- **两块同款板实测对比**:第二块全新 SuperMini 烧同样固件,结温 66–67°C,与第一块 69–70°C 几乎一样,手感都烫 → 确认是 SuperMini 的**设计通病**(LDO + 小板散热),**不是个别板子缺陷**;**换板不解决发热**。

## 6. 想靠"降频 / light sleep"降温 —— 此路不通(三重否决)

- **降频无效**:实测 CPU 160→80MHz,温度稳态**零变化**(只省 ~20mW,而 LDO 烧 ~42mW,封装上 <1°C)。
- **不能再降频**:80MHz 是 BLE 的实际下限(射频需 APB=80MHz)。`setCpuFrequencyMhz(40)` **不报错但会真降**,APB 掉到 40MHz → **BLE 断连 + 串口乱码**(arduino-esp32 #6032/#7182)。arduino-esp32 的 `setCpuFrequencyMhz` **没有** WiFi/BT 运行守卫,别指望它拦你。
- **light sleep 做不了也没用**:PlatformIO 预编译 arduino 库 `CONFIG_PM_ENABLE` 是关的(sdkconfig 实锤),`esp_pm_configure()` 能编译但运行时返回 `ESP_ERR_NOT_SUPPORTED`,芯片永不睡。要真开必须切 ESP-IDF 框架 / 用 esp32-arduino-lib-builder 重编 core(arduino-esp32 #6563 自 2022 起 open 未解)。而且即便做成,芯片本就只发几十 mW,对 LDO 热几乎无用。
- **教训**:在 USB 供电的小板上,降功耗 ≠ 降温;先定位主热源(多半是 LDO 压降),否则在芯片侧白折腾。真要降温:换板 / 3.3V 直供绕过 LDO(≤3.6V!)/ 接受(70°C 对 ESP32 安全)。

## 7. `temperatureRead()` 在 C3 上偏高

C3 内部温度传感器贴近发热区、校准差,空载就常读 50–65°C。当**趋势**指标可以,当**绝对值**别全信。要客观就测电流。

## 8. C3 + T-vK 的重连鉴权 bug

首次配对能用,板子重启/断电再上电后能连上但**不发键**,串口现 `GATT_INSUF_AUTHENTICATION` / `BT_SMP`。
- 最简单:在 iPhone 蓝牙里"忽略此设备"重新配对。
- 每次上电都犯:换 C3 专用分支 `oden-umaru/ESP32C3-BLE-Keyboard@0.3.3`(内置 `ESP_LE_AUTH_REQ_SC_MITM_BOND` 修复),或自行改 `BleKeyboard.cpp` 的 `setAuthenticationMode`。

## 9. 调试方法:macOS 上无 TTY 后台读串口

`pio device monitor` 在没有终端的后台会 `termios.error: Operation not supported by device`。改用 pyserial 直读(PlatformIO 自带的 python 有 pyserial):
```python
import sys, time
import serial
s = serial.Serial(sys.argv[1], 115200, timeout=0.5)   # argv[1] = 你的串口,如 /dev/cu.usbmodemXXXX
end = time.time() + float(sys.argv[2])
while time.time() < end:
    line = s.readline()
    if line:
        sys.stdout.write(line.decode("utf-8", "replace")); sys.stdout.flush()
s.close()
```
要抓 boot 日志,读之前脉冲一下 RTS 复位芯片;要保持现有 BLE 连接不断,**不要**动 DTR/RTS(C3 的 USB-CDC 打开端口本身一般不复位芯片)。

## 10. C3 SuperMini 其它硬件注意

- 板载 LED 在 **GPIO8,active-low**(`digitalWrite(8, LOW)` 点亮)。`LED_BUILTIN` 在 DevKitM-1 variant 下没定义到 8,自己 `#define` 或直接用 8。
- **GPIO9 是 BOOT strapping 脚**:任何东西在复位时把它拉低都会让板子进下载模式、看似"不启动"。
- **3V3 引脚直连芯片、绕过 LDO**:绝不可超过 3.6V,锂电(3.7–4.2V)直插会烧 MCU。
- 部分 2024 批次晶振离天线太近,WiFi 连接差(`WiFi.setTxPower(WIFI_POWER_8_5dBm)` 可缓解);对 BLE 影响小。
- 认不到设备的第一嫌疑永远是**纯充电 USB 线**,换数据线。
