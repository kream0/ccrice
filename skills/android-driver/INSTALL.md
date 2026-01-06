# Android Driver Installation

## Prerequisites

- Python 3.10+
- Android device with USB debugging enabled
- ADB installed and in PATH

## Setup

1. Install Python dependencies:
   ```bash
   pip install -r ~/.claude/skills/android-driver/requirements.txt
   ```

2. Connect your Android device via USB and verify ADB connection:
   ```bash
   adb devices
   ```

3. Initialize uiautomator2 on the device (first time only):
   ```bash
   python -m uiautomator2 init
   ```
   This installs the `atx-agent` on your Android device for fast communication.

## Verify Installation

```bash
python ~/.claude/skills/android-driver/scripts/bridge.py status
```

## Troubleshooting

### Device not found
```bash
# Check ADB connection
adb devices

# Reinitialize uiautomator2
python -m uiautomator2 init
```

### Connection timeout
```bash
# Try connecting by IP instead (for wireless debugging)
adb tcpip 5555
adb connect <device-ip>:5555
```
