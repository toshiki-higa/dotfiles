# Raspberry Pi
## Prerequirements
- raspberry-pi-imager

## How to setup 
1. Install OS to SD card using `raspberry-pi-imager` with the following setting:
```yaml
general:
  hostname: {{ hostname }}
  user:
    username: {{ username }}
    password: {{ password }}
  wifi:
    ssid: {{ ssid }}
    password: {{ ssid-password }}
  locale:
    timezone: asia/tokyo
    layout: us
service:
  ssh: PasswordAuthentication
```

2. Run Raspberry Pi after setting microSD

3. Connect to raspberrypi using SSH
```bash
ssh {{ username }}@{{ hostname }}.local
```

4. Follow `README.md` for setup

## Reference
- [gist - How to Use Raspberry Pi's rpi-imager --cli Command on macOS](https://gist.github.com/bashtheshell/010d70f7643f171096ad9462ea86324b)
