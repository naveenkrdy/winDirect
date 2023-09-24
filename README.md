# winDirect

An alternative to Apple's Boot Camp utility for installing Windows with the UEFI/GPT scheme from within macOS.

## Features
- No USB stick required.
- Supports UEFI/GPT installation.
- Supports OpenCore/Clover bootloader.
- Easy Dual-boot setup.

## Usage

```bash
./winDirect.sh <target_volume_id> <iso_file_path>
```

## Instructions

1. Clone the Repository:

```bash
git clone https://github.com/naveenkrdy/winDirect.git
cd winDirect
```

2. Open Disk Utility and Format the Target Volume:
   
   - Open the Disk Utility app on your Mac.
   - In Disk Utility, locate the volume on which you want to install macOS.
   - Select the volume, and then click on the "Erase" button.
   - Choose a suitable format for the volume, such as exFAT, FAT32, or JHFS+. **Note:** Do not format it as APFS.
   - Click the "Erase" button to format the volume.
   - Close Disk Utility after formatting is complete. 

4. Identify the Target Volume:
   
Run the following command to identify the target volume identifier for your Windows installation (e.g., disk2s2):
```bash
diskutil list
```
4. Run the winDirect Script:
   
Execute the winDirect script, passing the target volume identifier and the path to your Windows ISO image:
```bash
./winDirect.sh disk2s2 ~/Downloads/Windows11_Installer.iso
```

5. Reboot to Windows:
   
After the installation process is complete, reboot to access the Windows operating system.

**Note:** If you are using opencore or clover select the windows volume from bootloader menu.

7.  Done!
