/*
 * ESP32-C3 SuperMini — BLE keyboard that stops an iPhone/iPad from auto-locking.
 *
 * Pairs as a Bluetooth keyboard and, while connected, taps one key every
 * SEND_INTERVAL_MS. iOS treats it as user input and resets the Auto-Lock timer,
 * so the screen never sleeps while the board is connected and powered.
 *
 * KEY CHOICE — Shift vs F15:
 *   Research warns that a bare modifier (Shift) is unreliable on iOS, because
 *   modifiers ride a separate HID bitmask that iOS sometimes ignores; the
 *   "safe" choice is a real non-modifier no-op key such as F15.
 *   HOWEVER, this was tested on a real iPhone and KEY_LEFT_SHIFT DID keep the
 *   screen awake, so Shift is the default here. If it ever fails to hold the
 *   screen on your device, switch WAKE_KEY to KEY_F15.
 *
 * Library: T-vK/ESP32-BLE-Keyboard @ 0.3.2-beta in NimBLE mode.
 * Build pins live in platformio.ini and are load-bearing (see README).
 */

#include <BleKeyboard.h>

// ---- Tunables --------------------------------------------------------------
BleKeyboard bleKeyboard("KeepAwake", "Espressif", 100);   // name shown in the iOS Bluetooth list

static const uint32_t SEND_INTERVAL_MS = 15000;          // tap a key every 15 s
static const uint8_t  WAKE_KEY         = KEY_LEFT_SHIFT;  // see "KEY CHOICE" above; KEY_F15 is the fallback
// ---------------------------------------------------------------------------

// The C3 SuperMini's onboard LED is GPIO8 and is ACTIVE-LOW (LOW = lit).
static const uint8_t LED_PIN = 8;

static uint32_t lastSend     = 0;
static uint32_t lastBlink    = 0;
static bool     blinkOn      = false;
static bool     wasConnected = false;

static inline void led(bool on) { digitalWrite(LED_PIN, on ? LOW : HIGH); }  // active-low

void setup() {
  pinMode(LED_PIN, OUTPUT);
  led(false);

  Serial.begin(115200);  // over native USB-C; the baud value is ignored by USB-CDC
  delay(200);            // do NOT use `while (!Serial)` on the C3 — it can hang

  // Run at 80 MHz instead of the default 160 MHz. NOTE: this barely changes
  // temperature (the heat is the on-board LDO, not the CPU — see README), but it
  // is harmless and trims a little power. Do NOT go below 80 MHz: the BLE radio
  // needs APB = 80 MHz, and dropping lower silently drops the connection.
  setCpuFrequencyMhz(80);
  Serial.printf("[KeepAwake] booting @ %u MHz, chip temp %.1f C, advertising...\n",
                getCpuFrequencyMhz(), temperatureRead());

  bleKeyboard.begin();   // start BLE advertising
}

void loop() {
  const uint32_t now = millis();

  if (bleKeyboard.isConnected()) {
    led(true);                            // solid LED = connected/paired
    if (!wasConnected) {
      wasConnected = true;
      Serial.println("[KeepAwake] connected.");
      lastSend = now - SEND_INTERVAL_MS;  // fire one keypress immediately on connect
    }
    if (now - lastSend >= SEND_INTERVAL_MS) {
      bleKeyboard.write(WAKE_KEY);        // single press + release
      lastSend = now;
      Serial.printf("[KeepAwake] sent key, chip temp %.1f C\n", temperatureRead());
    }
  } else {
    if (wasConnected) {
      wasConnected = false;
      Serial.println("[KeepAwake] disconnected, advertising again...");
    }
    // Slow blink = powered and waiting for the phone to connect.
    if (now - lastBlink >= 500) {
      blinkOn = !blinkOn;
      led(blinkOn);
      lastBlink = now;
    }
  }

  delay(10);
}
