# Remove the excluded components from the disklayout file.
# Excluded components are marked as DONE in the disktodo file.

# Component in position 2
remove_component() {
    sed -i "\,^$1 $2,d" $LAYOUT_FILE
}

# Component in position 3
remove_second_component() {
    sed -i -r "\,^$1 [^ ]+ $2,d" $LAYOUT_FILE
}

# Remove lines in the LAYOUT_FILE
while read done name type junk ; do
    case $type in 
        lvmdev)
            name=${name#pv:}
            remove_second_component $type $name
            ;;
        lvmvol)
            name=${name#/dev/mapper/*-}
            remove_second_component $type $name
            ;;
        fs)
            name=${name#fs:}
            remove_second_component $type $name
            ;;
        swap)
            name=${name#swap:}
            remove_component $type $name
            ;;
        *)
            remove_component $type $name
            ;;
    esac
done < <(grep "^done" $LAYOUT_TODO)

# Remove all LVM PVs of excluded VGs
while read status name junk ; do
    remove_component "lvmdev" "$name"
done < <(grep -E "^done [^ ]+ lvmgrp"  $LAYOUT_TODO)