#!/bin/bash
# shellcheck disable=SC2086

# winDirect.sh
# Usage: ./winDirect.sh <target_volume_id> <iso_file_path>
# Author : @naveenkrdy
# Discription: Script to install Windows OS from within macOS without using a USB stick or bootcamp.
VERSION=1.0

# set -e

error_exit() {
	echo "[Error]: $1"
	echo "[Error]: Exiting.."
	exit 1
}

print_seperator() {
	local length=65
	local symbol="="

	for ((i = 1; i <= length; i++)); do
		echo -n "$symbol"
	done
	echo
}

check_iso() {
	echo "[Info]: ISO Path: $iso_file_path"
	if ! [[ -e "${iso_volume_name}/sources/install.wim" || -e "${iso_volume_name}/sources/install.esd" ]]; then
		error_exit "Provided Windows installer ISO is not valid"
	fi
	echo "[Info]: Provided Windows installer ISO is valid"
	echo "[Info]: Installer volume name is $iso_volume_name"
	echo "[Info]: Installer disk Id is $iso_disk_id"
}

check_target() {
	if ! diskutil list | grep -q "$target_disk_id"; then
		error_exit "Target disk $target_disk_id not found"
	fi

	if diskutil info "$target_disk_id" | grep -q "GUID_partition_scheme"; then
		echo "[Info]: Target disk $target_disk_id is GUID/GPT scheme"
	else
		error_exit "Target disk $target_disk_id is not GUID/GPT scheme"
	fi

	if ! diskutil list "$target_disk_id" | grep -q "$target_volume_id"; then
		error_exit "Target volume $target_volume_id not found"
	fi

	if diskutil info "$target_volume_id" | grep -q "EFI"; then
		error_exit "Target volume $target_volume_id should not be EFI"
	fi
	if diskutil info "$target_volume_id" | grep -q "APFS"; then
		error_exit "Target volume $target_volume_id should not be of type APFS. Please format it as ExFAT or FAT32 or JHFS+"
	fi

	local disk_size
	disk_size=$(diskutil info "$target_volume_id" | grep "Disk Size:" | awk '{print $5}' | tr -d '()')

	if [[ $disk_size -le 21474836480 ]]; then
		error_exit "Target volume $target_volume_id doesn't have enough space (Min: 20Gb)"
	fi
}

mount_efi_partition() {
	local target_volume_id="$1"
	local efi_mount_point

	if ! efi_mount_point=$(./scripts/mount_efi.sh "$target_volume_id"); then
		error_exit "Unable to mount EFI volume on target volume $target_volume_id"
	fi

	echo "$efi_mount_point"
}

mount_target_volume() {
	local target_volume_id="$1"
	local target_volume_mount_point

	if ! diskutil info "$target_volume_id" >/dev/null | grep -q "*Mounted: *No*"; then
		diskutil mount "$target_volume_id" >/dev/null || error_exit "Unable to mount target volume $target_volume_id"
	else 
		error_exit "Target volume info is missing"
	fi

	target_volume_mount_point=$(diskutil info "$target_volume_id" | sed -n 's/.*Mount Point: *//p')
	echo "$target_volume_mount_point"
}

unmount_target_volume() {
	local target_volume_id="$1"

	if diskutil unmount $target_volume_id 2>&1 | grep -q "failed"; then
		error_exit "Failed to unmount target volume $target_volume_id"
	fi
	echo "[Info]: Successfully unmounted target volume $target_volume_id"
}

install_windows() {

	echo "[Info]: Provided Windows installer ISO has the following editions: "
	print_seperator
	./bin/wiminfo ${iso_volume_name}/sources/install.* | grep 'Display Name:' | grep -v 'Boot' | sed -e 's/Display Name: //' | awk '{$1=$1};1' | nl -s '. ' | sed 's/^[[:space:]]*//' || error_exit "Failed to get windows editions list"
	print_seperator
	read -p "[Input] Enter the edition number: " edition_index
	echo
	sudo -v
	echo
	echo "[Install]: Preparing target volume $target_volume_id:"
	print_seperator
	diskutil eraseVolume exFAT WIN_TEMP "$target_volume_id" || error_exit "Failed to erase volume to exFAT"
	print_seperator

	part_start=$(sudo gpt show "$target_disk_id" 2>&1 | grep "$y  GPT part" | awk '{ print $1 }') || error_exit "Failed to get volume start value"
	echo "[Info]: Target volume starts at $part_start"

	echo "[Install]: Unmounting target volume $target_volume_id"
	unmount_target_volume $target_volume_id

	echo "[Install]: Formatting target volume $target_volume_id to NTFS"
	print_seperator
	sudo ./bin/mkntfs -p "$part_start" -S 63 -H 255 -f -L Windows /dev/${target_volume_id} || error_exit "Unable to format target volume $target_volume_id to NTFS"
	print_seperator

	echo "[Install]: Installing Windows on target volume $target_volume_id"
	print_seperator
	sudo ./bin/wimapply ${iso_volume_name}/sources/install.* "$edition_index" /dev/${target_volume_id} || error_exit "Unable to install Windows on target volume $target_volume_id"
	print_seperator

	mount_target_volume "$target_volume_id" >/dev/null

	echo "[Info]: Windows successfully installed on target volume $target_volume_id"
}

install_bootloader() {
	echo "[Info]: Installing Windows bootloader on target disk $target_disk_id"
	efi_mount_point=$(mount_efi_partition "$target_volume_id")
	target_volume_mount_point=$(mount_target_volume "$target_volume_id")

	if [[ -d "${efi_mount_point}/EFI/Microsoft" ]]; then
		echo "[Install]: Removing existing Windows bootloader"
		rm -rf "${efi_mount_point}/EFI/Microsoft"
	fi

	echo "[Install]: Creating Windows bootloader files on $efi_mount_point"
	mkdir -p "${efi_mount_point}/EFI/Microsoft/BOOT/"
	mkdir -p "${efi_mount_point}/EFI/Microsoft/Recovery/"
	cp -R "${target_volume_mount_point}/Windows/Boot/EFI/" "${efi_mount_point}/EFI/Microsoft/BOOT"
	cp -R "${target_volume_mount_point}/Windows/Boot/Fonts" "${efi_mount_point}/EFI/Microsoft/BOOT"
	cp ./misc/BCD_rcv "${efi_mount_point}/EFI/Microsoft/Recovery/BCD"
	cp ./misc/BCD ~/BCD

	echo "[Info]: Preparing patch for Windows bootloader"
	target_disk_guid=$(ioreg -l | grep -ow -A40 "$target_disk_id" | grep -w UUID | sed 's/UUID//' | tr -d ' |="-')
	s=$target_disk_guid
	target_disk_guid_patch="${s:6:2}${s:4:2}${s:2:2}${s:0:2}${s:10:2}${s:8:2}${s:14:2}${s:12:2}${s:16:16}"
	echo "[Info]: Target disk $target_disk_id GUID is $target_disk_guid"
	echo "[Info]: Target disk $target_disk_id patched GUID is $target_disk_guid_patch"

	target_volume_uuid=$(diskutil info "$target_volume_id" | grep "Disk / Partition UUID:" | awk '{ print $5 }' | tr -d ' |=\"-')
	s=$target_volume_uuid
	target_volume_uuid_patch="${s:6:2}${s:4:2}${s:2:2}${s:0:2}${s:10:2}${s:8:2}${s:14:2}${s:12:2}${s:16:16}"
	echo "[Info]: Target volume '$target_volume_id' UUID is $target_volume_uuid"
	echo "[Info]: Target volume '$target_volume_id' patched UUID is $target_volume_uuid_patch"

	target_disk_guid_patch=$(echo -n "$target_disk_guid_patch" | sed 's/../\\x&/g')
	target_volume_uuid_patch=$(echo -n "$target_volume_uuid_patch" | sed 's/../\\x&/g')

	echo "[Install]: Applying patch to Windows bootloader"
	sudo perl -pi -e "s|\x17\x18\x19\x20\x21\x22\x23\x24\x25\x26\x27\x28\x29\x30\x31\x32|$target_disk_guid_patch|g" ~/BCD
	sudo perl -pi -e "s|\x01\x02\x03\x04\x05\x06\x07\x08\x09\x10\x11\x12\x13\x14\x15\x16|$target_volume_uuid_patch|g" ~/BCD
	mv ~/BCD "${efi_mount_point}/EFI/Microsoft/BOOT/BCD"

	if ! [[ -e "${efi_mount_point}/EFI/Clover" || -e "${efi_mount_point}/EFI/OC" ]]; then
		echo "[Info]: Opencore installed Windows bootloader on target disk $target_disk_id"
		mkdir -p "${efi_mount_point}/EFI/BOOT/"
		cp -R "${efi_mount_point}/EFI/Microsoft/BOOT/bootmgfw.efi" "${efi_mount_point}/EFI/BOOT/bootx64.efi"
	fi
	# diskutil unmount "$efi_mount_point"
	echo "[Info]: Successfully installed Windows bootloader on target disk $target_disk_id"
}

# START

echo "[Info]: winDirect.sh $VERSION"
echo "[Info]: Script by @naveenkrdy"
print_seperator

if [ $# -ne 2 ]; then
	error_exit "Usage: $0 <target_volume_id> <iso_file_path>"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir" || error_exit "Unable to change the current directory to the script source folder"

target_volume_id=$1
x="${target_volume_id:4:1}"
y="${target_volume_id:6:1}"
target_disk_id="disk${x}"

iso_file_path=$2
iso_mount_output=$(hdiutil mount "$iso_file_path") || error_exit "Failed to mount ISO file"
iso_disk_id=$(echo "$iso_mount_output" | grep -o '/dev/disk[0-9]*')
iso_volume_name=$(echo "$iso_mount_output" | grep -o '/Volumes/.*' | cut -f 1- | sed 's/ /\\ /g')

check_iso
check_target
install_windows
install_bootloader
