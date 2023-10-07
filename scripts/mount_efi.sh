#!/bin/bash
# mountefi.sh
# Script to mount EFI partition on macOS

# NOTE: Based on CloverPackage MountESP script.

if [[ "$1" == "" ]]; then
    dest_volume=/
else
    dest_volume="$1"
fi

# find whole disk for the destination volume
disk_device=$(LC_ALL=C diskutil info "$dest_volume" 2>/dev/null | sed -n 's/.*Part [oO]f Whole: *//p')
if [[ -z "$disk_device" ]]; then
    echo "Error: Not able to find volume with the name \"$dest_volume\""
    exit 1
fi

# check if target volume is a logical Volume instead of physical
if [[ "$(echo $(LC_ALL=C diskutil list | grep -i 'Logical Volume' | awk '{print tolower($0)}'))" == *"logical volume"* ]]; then
    # ok, we have a logical volume somewhere.. so that can assume that we can use "diskutil cs"
    LC_ALL=C diskutil cs info $disk_device >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        # logical volumes does not have an EFI partition (or not suitable for us?)
        # find the partition uuid
        uuid=$(LC_ALL=C diskutil info "${disk_device}" 2>/dev/null | sed -n 's/.*artition uuid: *//p')
        # with the partition uuid we can find the real disk in in diskutil list output
        if [[ -n "$uuid" ]]; then
            realDisk=$(LC_ALL=C diskutil list | grep -B 1 "$uuid" | grep -i 'logical volume' | awk '{print $4}' | sed -e 's/,//g' | sed -e 's/ //g')
            if [[ -n "$realDisk" ]]; then
                disk_device=$(LC_ALL=C diskutil info "${realDisk}" 2>/dev/null | sed -n 's/.*Part [oO]f Whole: *//p')
            fi
        fi
    fi
fi

# check if target volume is APFS, and therefore part of an APFS container
if [[ "$(echo $(LC_ALL=C diskutil list "$disk_device" | grep -i 'APFS Container Scheme' | awk '{print tolower($0)}'))" == *"apfs container scheme"* ]]; then
    # ok, this disk is an APFS partition, extract physical store device
    realDisk=$(LC_ALL=C diskutil list "$disk_device" 2>/dev/null | sed -n 's/.*Physical Store *//p')
    disk_device=$(LC_ALL=C diskutil info "$realDisk" 2>/dev/null | sed -n 's/.*Part [oO]f Whole: *//p')
fi

partition_scheme=$(LC_ALL=C diskutil info "$disk_device" 2>/dev/null | sed -nE 's/.*(Partition Type|Content \(IOContent\)): *//p')
# Check if the disk is an MBR disk
if [[ "$partition_scheme" == "FDisk_partition_scheme" ]]; then
    echo "Error: Volume \"$dest_volume\" is part of an MBR disk"
    exit 1
fi
# Check if not GPT
if [[ "$partition_scheme" != "GUID_partition_scheme" ]]; then
    echo "Error: Volume \"$dest_volume\" is not on GPT disk or APFS container"
    exit 1
fi

# Find the associated EFI partition on disk_device
diskutil list -plist "/dev/$disk_device" 2>/dev/null >/tmp/org_rehabman_diskutil.plist
for ((part = 0; 1; part++)); do
    content=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:0:Partitions:$part:Content" /tmp/org_rehabman_diskutil.plist 2>&1)
    if [[ "$content" == *"Does Not Exist"* ]]; then
        echo "Error: cannot locate EFI partition for $dest_volume"
        exit 1
    fi
    if [[ "$content" == "EFI" ]]; then
        efi_device=$(/usr/libexec/PlistBuddy -c "Print :AllDisksAndPartitions:0:Partitions:$part:DeviceIdentifier" /tmp/org_rehabman_diskutil.plist 2>&1)
        break
    fi
done

# should not happen
if [[ -z "$efi_device" ]]; then
    echo "Error: unable to determine efi_device from $disk_device"
    exit 1
fi

# Get the EFI mount point if the partition is currently mounted
code=0
efi_mount_point=$(LC_ALL=C diskutil info "$efi_device" 2>/dev/null | sed -n 's/.*Mount Point: *//p')
if [[ -z "$efi_mount_point" ]]; then
    # try to mount the EFI partition
    sudo diskutil mount /dev/$efi_device >/dev/null 2>&1
    efi_mount_point=$(LC_ALL=C diskutil info "$efi_device" 2>/dev/null | sed -n 's/.*Mount Point: *//p')
    code=$?
fi

# echo "($efi_device)" $efi_mount_point 
echo $efi_mount_point
exit $code