# Server-local-fisiere-ssd

Turn a Raspberry Pi 5 into a local NAS with USB-attached SSDs/HDDs, shared over
Samba (SMB) so you can browse and edit files from Windows, Linux, macOS, and
Android apps like **CX File Explorer**.

No RAID — each drive is mounted and shared independently.

## Hardware checklist

- Raspberry Pi 5 (2GB+ RAM recommended)
- Good quality USB-C power supply (5V/5A official one recommended — USB drives draw extra power)
- One or more SSDs/HDDs in USB 3.0 enclosures (use a **powered** USB hub or powered enclosures for HDDs — the Pi's USB ports can't power spinning drives reliably)
- Raspberry Pi OS Lite (64-bit, Bookworm) flashed to the boot SD card/SSD

## 1. Flash and boot Raspberry Pi OS

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash **Raspberry Pi OS Lite (64-bit)**. In the imager's advanced options (gear icon):
- Set hostname (e.g. `nas`)
- Enable SSH
- Set username/password
- Configure Wi-Fi (or just use Ethernet, recommended for a NAS)

Boot the Pi, then connect over SSH:

```bash
ssh <user>@nas.local
```

## 2. Clone this repo onto the Pi

```bash
git clone https://github.com/Fcristi1/Server-local-fisiere-ssd.git
cd Server-local-fisiere-ssd
chmod +x scripts/*.sh
```

## 3. Install packages and enable monitoring

```bash
sudo ./scripts/01-system-setup.sh
```

Installs Samba, NFS, disk utilities, `smartmontools` (disk health), and `avahi-daemon`
(so the Pi answers to `nas.local`).

## 4. Connect and prepare each drive

Plug in a drive, then list block devices to find its device name:

```bash
sudo ./scripts/02-prepare-disk.sh --list
```

Look for your drive by size (e.g. `/dev/sda`). Then, **for a brand-new/empty drive**:

```bash
sudo ./scripts/02-prepare-disk.sh --device /dev/sda --label ssd1 --format
```

This wipes the disk, creates one ext4 partition, and mounts it at `/srv/nas/ssd1`
with a persistent `/etc/fstab` entry (by UUID, so it survives reboots/USB port changes).

If the drive already has data/filesystem you want to keep, format-free mount by
pointing at the existing partition instead (e.g. `/dev/sda1`) and omitting `--format`.

Repeat for each additional drive with a different `--label` (e.g. `hdd1`, `backup`).

> ⚠️ `--format` is destructive. The script prints the disk info and asks for confirmation first — double-check the device path before confirming.

## 5. Create NAS users and passwords

Users and passwords are set entirely on the Pi with `03-manage-nas-users.sh` — no
external tools needed. Everyone in the `users` group can access every share.

```bash
# Create a user, prompted for a password interactively (recommended)
sudo ./scripts/03-manage-nas-users.sh add --username nasuser

# Or set the password non-interactively (ends up in shell history, use with care)
sudo ./scripts/03-manage-nas-users.sh add --username nasuser2 --password 'MyStrongPass1'

# Change a password later
sudo ./scripts/03-manage-nas-users.sh passwd --username nasuser

# List existing NAS users
sudo ./scripts/03-manage-nas-users.sh list

# Remove a user
sudo ./scripts/03-manage-nas-users.sh remove --username nasuser2
```

Add one user per person/device if you want separate logins — they all share the same drives.

## 6. Share the drives over Samba

```bash
sudo ./scripts/04-setup-samba.sh
```

Every folder under `/srv/nas` (one per drive from step 4) becomes an SMB share
named after its label, accessible only to the `nasuser` account.

## 7. (Recommended) Lock down the firewall

```bash
sudo ./scripts/05-firewall.sh
```

Allows only SSH + Samba inbound, denies everything else.

## Testing the whole flow with a spare USB stick

You don't need a real SSD/HDD to try this out — any USB flash drive works exactly
the same way, since it just shows up as another block device.

1. Plug in the USB stick and find its device name:
   ```bash
   sudo ./scripts/02-prepare-disk.sh --list
   ```
   Identify it by size (e.g. 16 GB) and note the device, e.g. `/dev/sda`. **Do not
   pick your boot disk** (usually `/dev/mmcblk0` or `/dev/nvme0n1` — those won't show up in the list here anyway since this only lists what's plugged in, but always double check).
2. Format and mount it as a test share:
   ```bash
   sudo ./scripts/02-prepare-disk.sh --device /dev/sda --label test --format
   ```
   This erases the stick and mounts it at `/srv/nas/test`.
3. Create the NAS user (skip if already done) and generate the Samba share:
   ```bash
   sudo ./scripts/03-manage-nas-users.sh add --username nasuser
   sudo ./scripts/04-setup-samba.sh
   ```
4. Connect from CX File Explorer (see below) and confirm you can see the `test`
   share, upload a file, and it appears at `/srv/nas/test` on the Pi (`ls /srv/nas/test`).
5. Once confirmed, unmount and repeat with your real SSD/HDD using a different `--label`. To remove the test share afterwards:
   ```bash
   sudo umount /srv/nas/test
   sudo sed -i '/\/srv\/nas\/test/d' /etc/fstab
   sudo rm -rf /srv/nas/test
   sudo ./scripts/04-setup-samba.sh   # regenerate shares without "test"
   ```

## Connecting from an Android phone with CX File Explorer

1. Make sure the phone is on the **same Wi-Fi network** as the Pi.
2. Open **CX File Explorer** → tap the menu (☰) → **Network** → **New** → **SMB Server** (or the **+** button under "LAN"/"Network Storage").
3. Fill in:
   - **Server address / IP**: the Pi's IP, e.g. `192.168.1.50` (find it with `hostname -I` on the Pi), or try `nas.local`
   - **Port**: `445` (default, usually can be left blank)
   - **Username**: `nasuser`
   - **Password**: the Samba password you set in step 5
   - **Path/Share**: leave blank to see all shares, or set to the share name (e.g. `ssd1`)
4. Save. CX File Explorer will list all shares (`ssd1`, `hdd1`, ...) — tap one to browse, upload, download, or edit files directly.

The same credentials work from Windows (`\\<pi-ip>\ssd1`), macOS/Linux
(`smb://<pi-ip>/ssd1`), and other SMB-capable apps (Solid Explorer, VLC, etc.).

## Adding a drive later

Just repeat steps 4 and 6 (`02-prepare-disk.sh` for the new drive, then re-run
`04-setup-samba.sh` to pick up the new share).

## Checking disk health

```bash
sudo smartctl -a /dev/sda
```

Run periodically, or set up a cron job / `smartd` email alerts for early failure warnings.

## Troubleshooting

- **Drive not showing after reboot**: `lsblk` and `cat /etc/fstab` — check the UUID still matches (`sudo blkid`).
- **Can't connect from phone**: confirm the Pi's Samba service is running (`sudo systemctl status smbd`), the firewall allows it (`sudo ufw status`), and the phone/Pi are on the same subnet.
- **Permission denied writing files**: re-check share permissions with `sudo ./scripts/02-prepare-disk.sh` output, or `sudo chown -R nasuser:users /srv/nas/<label>`.
