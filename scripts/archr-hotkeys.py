#!/usr/bin/python3
"""
Arch R - Hotkey Daemon (replaces dArkOS ogage)
Listens for input events and handles:
  - KEY_VOLUMEUP/KEY_VOLUMEDOWN → ALSA volume adjust (from gpio-keys-vol)
  - MODE + VOL_UP/VOL_DOWN → brightness adjust
  - Headphone jack insertion → audio path toggle (from rk817 codec)

Volume device (gpio-keys-vol) is grabbed exclusively.
Gamepad device (gpio-keys) is monitored passively (ES keeps receiving events).
"""

import os
import sys
import time
import subprocess
import select

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print("ERROR: python-evdev not installed. Install with: pacman -S python-evdev")
    sys.exit(1)

# Volume step (percentage per key press)
VOL_STEP = 2
# Brightness step (percentage per key press)
BRIGHT_STEP = 3
# Minimum brightness percentage (prevent black screen)
BRIGHT_MIN = 5
# Brightness persistence file
BRIGHT_SAVE = os.path.expanduser("~/.config/archr/brightness")

# ALSA control name for rk817 BSP codec
# "Playback Path" is an enum (SPK/HP/OFF), NOT a volume control
# "DAC Playback Volume" is the actual stereo level (0-255, inverted)
ALSA_VOL_CTRL = "DAC Playback Volume"


def run_cmd(cmd):
    """Run a shell command silently."""
    try:
        subprocess.run(cmd, shell=True, capture_output=True, timeout=5)
    except Exception:
        pass


def volume_up():
    run_cmd(f"amixer -q sset '{ALSA_VOL_CTRL}' {VOL_STEP}%+")


def volume_down():
    run_cmd(f"amixer -q sset '{ALSA_VOL_CTRL}' {VOL_STEP}%-")


def get_brightness_pct():
    """Read current brightness as percentage from sysfs."""
    try:
        with open("/sys/class/backlight/backlight/brightness") as f:
            cur = int(f.read().strip())
        with open("/sys/class/backlight/backlight/max_brightness") as f:
            mx = int(f.read().strip())
        return (cur * 100) // mx if mx > 0 else 50
    except Exception:
        return 50


def save_brightness():
    """Save current brightness value for persistence across reboots."""
    try:
        with open("/sys/class/backlight/backlight/brightness") as f:
            val = f.read().strip()
        os.makedirs(os.path.dirname(BRIGHT_SAVE), exist_ok=True)
        with open(BRIGHT_SAVE, "w") as f:
            f.write(val)
    except Exception:
        pass


def brightness_up():
    run_cmd(f"brightnessctl -q s +{BRIGHT_STEP}%")
    save_brightness()


def brightness_down():
    if get_brightness_pct() <= BRIGHT_MIN:
        return
    run_cmd(f"brightnessctl -q s {BRIGHT_STEP}%-")
    # Clamp: if we went below minimum, set to minimum
    if get_brightness_pct() < BRIGHT_MIN:
        run_cmd(f"brightnessctl -q s {BRIGHT_MIN}%")
    save_brightness()


def speaker_toggle(headphone_in):
    if headphone_in:
        run_cmd("amixer -q sset 'Playback Path' HP")
    else:
        run_cmd("amixer -q sset 'Playback Path' SPK")


def find_devices():
    """Find and categorize input devices."""
    vol_dev = None    # gpio-keys-vol (grab: exclusive volume control)
    pad_dev = None    # gpio-keys (no grab: monitor MODE button passively)
    sw_dev = None     # headphone jack (switch events)

    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
            name = dev.name.lower()
            caps = dev.capabilities()

            if 'gpio-keys' in name:
                # Distinguish vol device from gamepad by checking for KEY_VOLUMEUP
                key_caps = caps.get(ecodes.EV_KEY, [])
                if ecodes.KEY_VOLUMEUP in key_caps:
                    vol_dev = dev
                elif ecodes.BTN_SOUTH in key_caps or ecodes.BTN_DPAD_UP in key_caps:
                    pad_dev = dev

            # Headphone jack switch events (from rk817 or similar codec)
            if ecodes.EV_SW in caps:
                sw_dev = dev

        except Exception:
            continue

    return vol_dev, pad_dev, sw_dev


def main():
    print("Arch R Hotkey Daemon starting...")

    # Wait for input devices to appear
    vol_dev, pad_dev, sw_dev = None, None, None
    for attempt in range(30):
        vol_dev, pad_dev, sw_dev = find_devices()
        if vol_dev:
            break
        time.sleep(1)

    if not vol_dev:
        print("ERROR: Volume input device (gpio-keys-vol) not found!")
        sys.exit(1)

    # Grab volume device exclusively (we handle volume events)
    vol_dev.grab()
    print(f"  Volume: {vol_dev.name} ({vol_dev.path}) [grabbed]")

    # Monitor gamepad passively for MODE button (brightness hotkey)
    devices = [vol_dev]
    if pad_dev:
        # DO NOT grab — ES needs this device for gamepad input
        print(f"  Gamepad: {pad_dev.name} ({pad_dev.path}) [passive]")
        devices.append(pad_dev)

    if sw_dev and sw_dev not in devices:
        print(f"  Switch: {sw_dev.name} ({sw_dev.path}) [passive]")
        devices.append(sw_dev)

    # Track MODE button state for brightness hotkey combo
    mode_held = False

    print("Hotkey daemon ready.")

    try:
        while True:
            r, _, _ = select.select(devices, [], [], 2.0)

            for dev in r:
                try:
                    for event in dev.read():
                        if event.type == ecodes.EV_KEY:
                            key = event.code
                            val = event.value  # 1=press, 0=release, 2=repeat

                            # Track MODE button from gamepad (passive)
                            # val: 1=press, 0=release, 2=repeat
                            # Don't clear on repeat (2==1 is False!)
                            if key == ecodes.BTN_MODE:
                                if val == 1:
                                    mode_held = True
                                elif val == 0:
                                    mode_held = False

                            # Volume keys from gpio-keys-vol (grabbed)
                            elif key == ecodes.KEY_VOLUMEUP and val in (1, 2):
                                if mode_held:
                                    brightness_up()
                                else:
                                    volume_up()

                            elif key == ecodes.KEY_VOLUMEDOWN and val in (1, 2):
                                if mode_held:
                                    brightness_down()
                                else:
                                    volume_down()

                        # Headphone jack switch
                        elif event.type == ecodes.EV_SW:
                            if event.code == ecodes.SW_HEADPHONE_INSERT:
                                speaker_toggle(event.value == 1)

                except OSError:
                    # Device disconnected
                    pass

    except KeyboardInterrupt:
        pass
    finally:
        try:
            vol_dev.ungrab()
        except Exception:
            pass
        print("Hotkey daemon stopped.")


if __name__ == "__main__":
    main()
