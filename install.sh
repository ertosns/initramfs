#!/bin/bash

: << MODE
this script is expected to be ONLY installed to, executed from the INSTALLATION_MEDIUM to the TARGET_MEDIUM, INSTALLATION_MEDIUM can be storage medium, TARGET_MEDIUM is the target machine
instllation need to support SELF-PROPAGATION, such that all necessary packages, scripts, binaries, and configurations need to be propagated to the instllation target after os-installation.
MODE

source $ORIGIN_DIR/partition.sh
source $ORIGIN_DIR/install_os.sh
source $ORIGIN_DIR/self_propagate.sh
: << AUTOMATION
# utomoate denialbe filesystem installation.
# create keyholder API, and standarization first
# loop through the installation process or end, iff at least one filesystem is installed.

#reality
at least you must have 3 filesystems
1) default: basic usage
2) cover(rubberhose): user hold claim of the default as main filesystem against this un-used fs.
3) main: it's key shouldn't be written locally unless in secure enviornments.
?) more partitions can belong to the cover type.COMMENT
## -- ##
AUTOMATION

function install-medium
{
    p_disk=$1
    partition $p_disk
    # install gpg
    {
        mkdir $GPG_HOME_DIR
        gpg --homedir $GPG_HOME_DIR --batch --yes --passphrase $(prompt-password) --quick-generate-key $GENERIC_KEY
    }
    _os_part=$(get-disk-part $DISK_OS_PART)
    _boot_config_part=$(get-disk-part $DISK_BOOT_CONFIG_PART)
    mount $_boot_config_part $ROOT_BOOT &&
        {
            install-bootloader $p_disk
            mkinitramfs-openwindow
            mkconfig $p_disk
            # install-layout
            {
                _boot_config_uuid=$(get-uuid $(get-disk-part $p_disk $DISK_BOOTLOADER_CONFIG_PART))
                _os_uuid=$(get-uuid $(get-disk-part $p_disk $DISK_OS_PART))
                echo -e "MODE=EXECUTE\nPART=BOOT-CONFIG\tUUID=$_boot_config_uuid\nPART=OS\tUUID=$_os_uuid\n" > $WDIR/$INSTALL_LAYOUT
                mkinitramfs-closewindow
            }
        } && umount $ROOT_BOOT


    DENAIBLE_INSTALLATION=true
    while $DENAIBLE_INSTALLATION; do
        _key_file=$(generate-key-file)
        _mapper=deniable_mapper
        encrypt-partition $p_dev $_key_file $_mapper
        # filesystem installation
        _skip=$(prompt-filesystem-skip)
        _size=$(prompt-filesystem-size)
        _loopdev=$(losetup -f)
        losetup -d $_loopdev
        losetup -f -o $_skip --sizelimit $_size /dev/mapper/$_mapper
        #TODO install btrfs
        mkfs.ext4 $_loopdev
        _keylayout_file=$(enc-keylayout $_key_file $_skip $_size)
        save-dongle $_keylayout_file
        mount $_looospdev $ROOT && mount $_boot_config_part $ROOT_BOOT &&
            {
                install-os $p_disk
                true
            } && umount $ROOT_BOOT && umount $ROOT
        DENIABLE_INSTALLATION=$(yes-no-prompt $INSTALL_ANOTHER_SYSTEM)
    done
}


: << INSTALLING-LAYOUT
# guidelines
  - the installing layout isn't expected to encrypted, otherwise new dongle will be required.
  - installation process will take just the partitioning, which is also different, and cloning of files,
  - dongle is spread on the strorage part.
  - os is archived on the boot-conf part, and can have path /root.tar.gz
INSTALLING-LAYOUT

BIOS_BOOT_PART_IDX=0
UEFI_BOOT_PART_IDX=1
STORAGE_PART_IDX=2
#size up to the end of installing os_part.
INSTALLING_DISK_MIN=$(parse-unites $BOOTLOADER_END)

# TODO change this terrible {intall,installing}-medium convention, and mark it by stages of the bootstrapping, from the presepective of the client, first the installing medium is initialized, then the target machine is handled, maybe the first is called medium, and the second is called object, target, machine, box, or you can be brute, and call it male, and female respectively.

function installing-medium
{
    p_disk=$1
    # the os part isn't essential, the initramfs will suffice, only archive of os to be clone need to be present on the boot-config part, and be propagated on the target machine.
    # part
    {
        _os_part_end=
        _disk_size=$(get-disk-size $p_disk)
        if [ $(bc <<< "$_disk_size <  $INSTALLING_DISK_MIN") -eq 1 ]; then
            ERR "installing disk space isn't sufficient, at least $INSTALLING_DISK_MIN bytes"
        else
            _os_part_end=$(bc <<< $_disk_size-$INSTALLING_DISK_MIN)
        fi
        _dongle_part_end=$(bc <<< $_os_part_end+1024*1024)
        dd if=/dev/zero of=$p_disk ibs=1 count=$((100*1024*1024))
        parted -s $p_disk mktable gpt
        if [ $? != 0 ]; then
            ERR "failed to part $p_disk"
        fi
        partition-bootloader $p_disk
        if [ $? != 0 ]; then
            ERR "partition-bootloader failed for disk $p_disk";
        fi
        # storage-part
        #TODO (fix) i can't read the the disk storage in accurate bytes!!
        _disk_size=$(bc <<< "$_disk_size - 1024*1024*1024")
        INF "$BASH_SOURCE:installing-medium:$_disk_size:$INSTALLING_DISK_MIN"
        parted -s -a opt $p_disk mkpart primary "${INSTALLING_DISK_MIN}B" "${_disk_size}B"
        if [ $? != 0 ]; then
            ERR "parting the storage part failed for $p_disk"
        fi
    }
    # clone
    {
        _os_part=$(get-disk-part $p_disk $BIOS_BOOT_PART_IDX)
        _boot_config_part=$(get-disk-part $p_disk $UEFI_BOOT_PART_IDX)
        _storage_part=$(get-disk-part $p_disk $STORAGE_PART_IDX)
        mount $_boot_config_part $ROOT_BOOT &&
            {
                install-bootloader $p_disk
                mkinitramfs-openwindow
                mkconfig $p_disk
                # install-layout
                {
                    _boot_config_uuid=$(get-uuid $_boot_config_part)
                    _storage_uuid=$(get-uuid $_storage_part)
                    echo -e "MODE=INSTALL\nPART=BOOT-CONFIG\tUUID=$_boot_config_uuid\nPART=OS\tUUID=$_os_uuid\n" > $WDIR/$INSTALL_LAYOUT
                }
                mkinitramfs-closewindow
            } && umount $ROOT_BOOT
        if [ $? -ne 0 ]; then
            ERR "mount partition ($_boot_config_part) of $p_disk has failed"
        fi
        # for debugging
        if [ $(yes-no-prompt "would you create storage?") ]; then
            #TODO install os archive on the uefi part, and generalize it's installation with install.sh
            mount $_storage_part /mnt &&
                {
                    _clone=/mnt/$CLONE_PATH
                    clone-os $_clone
                    true
                } && umount /mnt
            if [ $? -ne 0 ]; then
                ERR "mount of ($_boot_config_part) has failed on /mnt"
            fi
            mkfs.ext4 $_storage_part
            if [ $? -ne 0 ]; then
                ERR "storage partition $_storage_part failed to be ext4ed"
            fi
        fi
    }
}
