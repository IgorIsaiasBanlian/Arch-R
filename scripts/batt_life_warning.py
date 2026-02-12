#!/usr/bin/env python3
"""
Arch R - Battery Life Warning LED Controller
Monitors battery level and controls LED indicators via sysfs.
Based on dArkOS batt_life_warning.py adapted for R36S.
"""

import os
import time

# Battery sysfs paths
BATT_CAPACITY = "/sys/class/power_supply/battery/capacity"
BATT_STATUS = "/sys/class/power_supply/battery/status"

# R36S LED GPIO paths (export and configure on first run)
# These may vary by clone — adjust if LEDs don't respond
LED_GPIOS = {
    "red": ["/sys/class/gpio/gpio12", "/sys/class/gpio/gpio17"],
    "blue": ["/sys/class/gpio/gpio0", "/sys/class/gpio/gpio11"],
}

def setup_gpio(gpio_num):
    """Export and configure a GPIO pin as output."""
    gpio_path = f"/sys/class/gpio/gpio{gpio_num}"
    if not os.path.exists(gpio_path):
        try:
            with open("/sys/class/gpio/export", "w") as f:
                f.write(str(gpio_num))
        except (IOError, PermissionError):
            return False
    direction_path = f"{gpio_path}/direction"
    if os.path.exists(direction_path):
        try:
            with open(direction_path, "w") as f:
                f.write("out")
        except (IOError, PermissionError):
            return False
    return True

def set_led(color, state):
    """Set LED color on/off. color='red'|'blue', state=0|1"""
    for gpio_path in LED_GPIOS.get(color, []):
        value_path = f"{gpio_path}/value"
        if os.path.exists(value_path):
            try:
                with open(value_path, "w") as f:
                    f.write(str(state))
            except (IOError, PermissionError):
                pass

def main():
    # Setup GPIOs
    for gpio_num in ["0", "11", "12", "17"]:
        setup_gpio(gpio_num)

    while True:
        try:
            with open(BATT_CAPACITY, "r") as f:
                capacity = int(f.read().strip())
            with open(BATT_STATUS, "r") as f:
                status = f.read().strip()
        except (IOError, ValueError):
            capacity = 50
            status = "Unknown"
            time.sleep(10)
            continue

        # Reset all LEDs
        set_led("red", 0)
        set_led("blue", 0)

        if status == "Charging":
            # Charging: Pink (red + blue)
            set_led("red", 1)
            set_led("blue", 1)
            time.sleep(5)
        elif capacity > 20:
            # Normal: Blue LED
            set_led("blue", 1)
            time.sleep(30)
        elif capacity > 10:
            # Low: Solid red
            set_led("red", 1)
            time.sleep(10)
        else:
            # Critical: Blinking red
            set_led("red", 1)
            time.sleep(0.5)
            set_led("red", 0)
            time.sleep(0.5)

if __name__ == "__main__":
    main()
