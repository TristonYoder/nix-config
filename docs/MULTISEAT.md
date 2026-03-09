# Multiseat Configuration Guide

This guide covers setting up multiseat on `david` to run as both a KVM virtualization host and a gaming/media center simultaneously.

## Overview

Multiseat allows a single machine to operate multiple independent user sessions, each with dedicated hardware:

- **Seat 0** (Integrated GPU): KVM host administration and system management
- **Seat 1** (Discrete NVIDIA GPU): Gaming and media playback

## Architecture

### Hardware Requirements

- **Two GPUs**: Integrated + discrete (NVIDIA in this case)
- **IOMMU Support**: Required for GPU isolation and potential passthrough
- **Multiple Monitors**: One per seat (or share with KVM switch)
- **Input Devices**: Separate keyboard/mouse per seat, or USB switch
- **Audio Outputs**: Separate audio devices per seat

### Software Stack

- **systemd-logind**: Handles seat management
- **udev**: Assigns devices to seats
- **SDDM**: Display manager with multiseat support
- **KDE Plasma 6**: Desktop environment (supports both seats)
- **libvirt/QEMU**: Virtualization stack

## Initial Setup

### Step 1: Hardware Detection

Run the detection script on `david` to identify device paths:

```bash
cd /path/to/nix-config
sudo ./scripts/detect-multiseat-hardware.sh > hardware-info.txt
```

Review the output to identify:
- GPU PCI paths (e.g., `0000:00:02.0` for integrated, `0000:01:00.0` for NVIDIA)
- DRM device names (e.g., `card0`, `card1`)
- Input device paths (e.g., `/dev/input/by-id/...`)
- Audio device names (e.g., `card0`, `card1`)

### Step 2: Configure Device Assignments

Edit `hosts/david/configuration.nix` and update the multiseat configuration:

1. **Set GPU PCI paths**:
   ```nix
   modules.system.multiseat.seat0.gpu = "pci-0000:00:02.0";  # Integrated
   modules.system.multiseat.seat1.gpu = "pci-0000:01:00.0";  # NVIDIA
   ```

2. **Assign devices to seats**:
   ```nix
   modules.system.multiseat.seat0.devices = [
     { subsystem = "drm"; kernel = "card0"; }
     { subsystem = "input"; kernel = "event3"; }  # Admin keyboard
     { subsystem = "input"; kernel = "event4"; }  # Admin mouse
     { subsystem = "sound"; kernel = "card0"; }   # Integrated audio
   ];

   modules.system.multiseat.seat1.devices = [
     { subsystem = "drm"; kernel = "card1"; }
     { subsystem = "input"; kernel = "event5"; }  # Gaming keyboard
     { subsystem = "input"; kernel = "event6"; }  # Gaming mouse
     { subsystem = "sound"; kernel = "card1"; }   # NVIDIA HDMI audio
   ];
   ```

3. **Enable multiseat**:
   ```nix
   modules.system.multiseat.enable = true;
   ```

### Step 3: Rebuild System

```bash
sudo nixos-rebuild switch --flake .#david
```

### Step 4: Verify Seats

After reboot, check seat status:

```bash
# List all seats
loginctl list-seats

# Show devices assigned to each seat
loginctl seat-status seat0
loginctl seat-status seat1

# Check active sessions
loginctl list-sessions
```

## Usage

### Logging In

After reboot, SDDM will start a greeter on each seat's monitor:
- **Seat 0**: Greeter on integrated GPU output
- **Seat 1**: Greeter on NVIDIA GPU output

Log in independently on each seat.

### Running Virtual Machines (Seat 0)

On the admin seat (seat0), launch virt-manager:

```bash
virt-manager
```

Create and manage VMs as usual. The discrete GPU can be passed through to VMs if needed.

### Gaming/Media (Seat 1)

On the gaming seat (seat1), the NVIDIA GPU provides full hardware acceleration for:
- Steam games
- Jellyfin playback
- Sunshine streaming
- Any GPU-accelerated applications

### Audio Routing

PipeWire automatically handles per-seat audio:
- Seat 0 uses integrated audio output
- Seat 1 uses NVIDIA HDMI audio (or USB audio if assigned)

Check audio devices:
```bash
pw-cli list-objects | grep node.name
```

## Configuration Options

### Autologin

Enable autologin for a specific seat:

```nix
modules.system.multiseat.seat0.autologin = "tristonyoder";
modules.system.multiseat.seat1.autologin = null;  # Manual login
```

### Desktop Session

Choose desktop session per seat (default: plasma):

```nix
modules.system.multiseat.seat0.session = "plasma";
modules.system.multiseat.seat1.session = "plasmax11";  # X11 for game compatibility
```

### Virtualization Options

Configure KVM/libvirt settings:

```nix
modules.system.virtualization = {
  enable = true;
  enableGUI = true;              # virt-manager
  enableLookingGlass = true;     # For GPU passthrough VMs
  users = [ "tristonyoder" ];    # Users in libvirtd group
};
```

## Troubleshooting

### Seat Not Starting

**Symptom**: One seat doesn't show login greeter

**Check**:
```bash
# Verify GPU is recognized
lspci -nn | grep VGA

# Check udev rules applied
udevadm info --query=all --name=/dev/dri/card0 | grep ID_SEAT

# Check SDDM logs
journalctl -u display-manager -f
```

**Fix**: Ensure GPU PCI path and DRM device are correct in configuration.

### Input Devices Not Working on Seat

**Symptom**: Keyboard/mouse doesn't work on one seat

**Check**:
```bash
# List input devices and their seat assignments
loginctl seat-status seat0
loginctl seat-status seat1

# Check udev assignment
udevadm info /dev/input/event3 | grep ID_SEAT
```

**Fix**: Verify input device kernel names in configuration match actual devices.

### Audio on Wrong Seat

**Symptom**: Audio plays on wrong seat's output

**Check**:
```bash
# List PipeWire nodes and their seat assignment
pw-cli list-objects | grep -A5 "node.name.*alsa"

# Check sound card seat assignment
udevadm info /dev/snd/pcmC0D0p | grep ID_SEAT
```

**Fix**: Ensure sound card device assignment matches the correct seat.

### VM Can't Start (Seat 0)

**Symptom**: libvirt fails to start VMs

**Check**:
```bash
# Verify virtualization is enabled
systemctl status libvirtd

# Check IOMMU
dmesg | grep -i iommu

# Verify user is in libvirtd group
groups tristonyoder
```

**Fix**: Ensure `modules.system.virtualization.users` includes your username.

### Rollback Procedure

If multiseat causes issues, disable it quickly:

```nix
modules.system.multiseat.enable = false;
```

Then rebuild:
```bash
sudo nixos-rebuild switch --flake .#david
```

Or boot into a previous generation from the boot menu.

## Advanced Topics

### GPU Passthrough to VM

To pass the discrete GPU to a VM while keeping integrated GPU for host:

1. Identify IOMMU group:
   ```bash
   ./scripts/detect-multiseat-hardware.sh | grep -A5 "IOMMU Groups"
   ```

2. Bind GPU to VFIO driver (before starting VM):
   ```bash
   # This is handled automatically by libvirt
   ```

3. Configure VM in virt-manager to use PCI passthrough

### Device Hotplug

Dynamically assign USB devices to seats:

```bash
# Assign device to seat1
udevadm trigger --action=add --subsystem=input --sysname=event7
```

### Performance Tuning

For gaming seat (seat1), consider:
- CPU pinning for VMs to avoid gaming seat CPU cores
- GPU scheduler priority
- PipeWire latency tuning

## Operational Notes

### Boot Process

1. System boots with both GPUs initialized
2. IOMMU groups established
3. udev rules assign devices to seats
4. SDDM starts greeters on both seats
5. Users log in independently
6. Each seat runs isolated desktop session

### Service Health

All existing `david` services (media, storage, infrastructure) remain unaffected:
- Tailscale router
- Caddy reverse proxy
- Docker services
- ZFS storage
- Jellyfin, Plex, etc.

### Recovery Methods

1. **TTY Access**: Ctrl+Alt+F1-F6 still available
2. **SSH Access**: Always available via Tailscale/LAN
3. **Boot Menu**: Previous generations available at boot
4. **Single User Mode**: Boot parameter `systemd.unit=rescue.target`

## References

- [NixOS Wiki: Multiseat](https://wiki.nixos.org/wiki/Multiseat)
- [systemd-logind multiseat documentation](https://www.freedesktop.org/wiki/Software/systemd/multiseat/)
- [IOMMU/GPU Passthrough Guide](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
