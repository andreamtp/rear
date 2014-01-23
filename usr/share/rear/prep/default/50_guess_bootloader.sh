# purpose is to guess the bootloader in use ans save this into a file
# /var/lib/rear/recovery/bootloader
for disk in /sys/block/* ; do
    if [[ ${disk#/sys/block/} = @(hd*|sd*|cciss*|vd*|xvd*) ]] ; then
        devname=$(get_device_name $disk)
        dd if=$devname bs=512 count=4 | strings > $TMP_DIR/bootloader
        grep -q "EFI" $TMP_DIR/bootloader && {
        echo "EFI" >$VAR_DIR/recovery/bootloader
        return
        }
        grep -q "GRUB" $TMP_DIR/bootloader && {
        echo "GRUB" >$VAR_DIR/recovery/bootloader
        return
        }
        grep -q "LILO" $TMP_DIR/bootloader && {
        echo "LILO" >$VAR_DIR/recovery/bootloader
        return
        }
        echo "Displaying the raw bootloader info:" >&7
        cat $TMP_DIR/bootloader >&7
   fi
done

