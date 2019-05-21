#!/bin/bash


# copy clone of boot enviornment
function clone-boot-environment
{
    local p_disk=$1
    # mount installing medium boot-config part, and clone it's boot environment
    local _install_medium_layout=$CONFIG_SRC/install_medium_layout.cfg
    parse-config $_install_medium_layout PART UUID
    local _installing_boot_conf_uuid=
    for ((row=0; i<$ROWS; i++)); do
        if [ MAT[$row,PART] == "BOOT-CONFIG" ]; then
            _installing_boot_conf_uuid=MAT[$row,UUID]
        fi
    done
    if [ -z $_installing_boot_conf_uuid ]; then
        ERR "couldn't figure out the installing boot-config part, check installing layout"
    fi
    local _installing_boot_conf_sys=$(get-subsystem $_installing_boot_conf_uuid)

    mount $_installing_boot_conf_sys /mnt &&
        {
            # clone-initramfs-origin
            {
                # copy initramfs layout form the current rootfs to the target root filesystem
                cp -rf $INITRAMFS_PACKAGED_SRC $ROOT_BOOT
                # note for a loop device you can't bind it,
                # and initiramfs clone need to be part of boot-conf part,
                # and it's configs binded from it's uuid to /etc/initramfs.
                local _boot_config_uuid=$(get-uuid $(get-disk-part $UEFI_BOOT_PART_IDX))
                bind-fstab $_boot_config_uuid $INITRAMFS_DES/include/confi g/etc/initramfs
                bind-fstab $_boot_config_uuid $INITRAMFS_DES /opt/initramfs
            }
            # clone-boot-config
            {
                cp $KERNEL_PATH $ROOT_BOOT
                if [ $CLONE_INSTALLING_MEDIUM ]; then
                    source ./mkinitramfs.sh
                    cp -rf $INITRAMFS_PACKAGE $ROOT_BOOT
                else
                    cp /mnt/$INITRAMFS_PATH $ROOT_BOOT
                fi
            }
            true;
        } && umount $_installing_boot_conf_sys
}

function mkinitramfs-openwindow
{
    local p_disk=$1
    # clone-initramfs-origin
    {
        # copy initramfs layout from the current rootfs to the target root filesystem
        [[ -n "$INITRAMFS_PACKAGED_SRC" ]] && cp -rf $INITRAMFS_PACKAGED_SRC $ROOT_BOOT
        # note for a loop device you can't bind it,
        # and initiramfs clone need to be part of boot-conf part,
        # and it's configs binded from it's uuid to /etc/initramfs.
        # fstab isn't effective in this process, such that systemd won't be executed,
        # and binding need to be simulated, or the concerning directories need to be copied.
        [[ -n "$INITRAMFS_DES" ]] && {
            mkdir -p $WDIR/opt/initramfs
            cp -rf $INITRAMFS_DES/ $WDIR/opt/initramfs
        }
        #TODO this redudnant location is universal, but noone got to visulaize, or memorized the layout of the installing dongle, and need to be illuminated.
        [[ -n "$INITRAMFS_DES" ]] && {
            mkdir -p $WDIR/etc/initramfs
            cp -rf $INITRAMFS_DES/include/config $WDIR/etc/initramfs
        }
        #TODO origin(initramfs project dir) exist both in the initramfs in mkinitramfs.sh package-cpio, and also present her on the boot-config-part, and those scripts are essential for self-propagate, and initrd stage, or self-propagate the location need to be in accord with mkinitrmfs.sh
    }
    # clone-boot-config
    {
        cp $KERNEL_PATH $ROOT_BOOT
        clone-initrd
    }

}
function mkinitramfs-closewindow
{
    package-cpio
    cp -rf $INITRAMFS_PACKAGE $ROOT_BOOT
}

function clone-os
{
    local p_clone=$1
    #TODO package clone
    #TODO download, compile, build necessary software if not present.
    local _basic_os=(bin sbin lib lib64 usr etc)
    #sys,proc,dev,run,etc,opt,tmp,mnt}
    for dir in ${_basic_os[@]}; do
        mkdir -p $p_clone/$dir
        cp -ax /$dir $p_clone
    done
    local _runtime_os=(sys proc dev run)
    for dir in ${_runtime_os[@]}; do
        mkdir -p $p_clone/$dir
    done
}

# copy the cloned os on the archive /clone at the boot-config-part to the $ROOT
function self-propagate
{
    cp -rf /clone/* $ROOT
}
