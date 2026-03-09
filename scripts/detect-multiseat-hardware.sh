#!/usr/bin/env bash
# Hardware detection script for multiseat configuration
# Run this on the target host to identify GPUs, IOMMU groups, and devices

set -e

echo "==================================="
echo "Multiseat Hardware Detection"
echo "==================================="
echo

echo "--- GPU Information ---"
echo "Listing all GPUs with PCI paths:"
lspci -nn | grep -E "VGA|3D controller" | while read line; do
    pci_slot=$(echo "$line" | cut -d' ' -f1)
    echo "  PCI: $pci_slot - $line"

    # Check for DRM devices
    for card in /sys/class/drm/card*/device; do
        if [ -e "$card" ]; then
            card_pci=$(basename $(readlink -f "$card") | cut -d':' -f2-)
            if [ "$card_pci" = "$pci_slot" ]; then
                drm_dev=$(basename $(dirname "$card"))
                echo "    DRM device: $drm_dev"
                echo "    Udev path: /sys/class/drm/$drm_dev"
            fi
        fi
    done
    echo
done

echo "--- IOMMU Groups ---"
echo "Checking IOMMU grouping (for GPU passthrough):"
for iommu_group in /sys/kernel/iommu_groups/*/devices/*; do
    if [ -e "$iommu_group" ]; then
        group=$(echo "$iommu_group" | cut -d'/' -f5)
        device=$(basename "$iommu_group")
        device_info=$(lspci -nns "$device" 2>/dev/null || echo "")
        if echo "$device_info" | grep -qE "VGA|Audio|3D"; then
            echo "  Group $group: $device - $device_info"
        fi
    fi
done
echo

echo "--- Audio Devices ---"
echo "Listing audio devices:"
aplay -l 2>/dev/null | grep -E "^card" || echo "No audio devices found"
echo

echo "--- USB Controllers ---"
echo "Listing USB controllers (for input device assignment):"
lspci -nn | grep -i usb
echo

echo "--- Input Devices ---"
echo "Listing input devices:"
ls -la /dev/input/by-id/ 2>/dev/null || echo "No input devices found"
echo

echo "--- Current DRM/Graphics Setup ---"
echo "Active graphics cards:"
ls -l /dev/dri/
echo

echo "==================================="
echo "Configuration Recommendations"
echo "==================================="
echo
echo "Based on the output above, you'll need to:"
echo "1. Identify your integrated GPU PCI path (usually 00:xx.x)"
echo "2. Identify your discrete NVIDIA GPU PCI path"
echo "3. Note the corresponding /dev/dri/cardX devices"
echo "4. List input devices to assign to each seat"
echo "5. Identify audio devices for each seat"
echo
echo "Example configuration will be in hosts/david/configuration.nix"
