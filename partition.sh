#!/bin/bash


# xweser ecosystem prerequisites uefi support

# monoboot partitioning
function os-parts
{
    #TODO increase config to >2gb
    #TODO no fallback
    dev=$1
    # TODO write FALLBACK_PART to initramfs.cfg.
    ## part (3) ##
    disk_size=$(get-disk-size $dev)
    os_part_end=$((($disk_size)-(1024+($FALLBACK_PART_SIZE*1024))))
    parted -s -a opt $dev 1GB "$os_part_end"MB

    ## part (4) ##
    parted -s -a opt $dev mkpart -"$FALLBACK_PART_SIZE"GB -1MB
    #TODO after finishing it's design complete installl-bootloader root mounting
}


: << 'COMMENT'
   ## topology of gpt disk table ##
DISK_BIOS_BOOTLOADER_PART=1
DISK_BOOTLOADER_CONFIG_PART=2
DISK_OS_PART=3
DISK_FALLBACK_OS_PART=4
   - part (1) bios bootloader skip 1MB, end 2MB, no filesystem.
   - part (2) bootloader partition with kernel, initramfs, configuration scripts /boot - skip 2MB, end 1GB
   - part (3) os partition.
   - part (4) fallback-os partition SKIP -SIZE_PART_SIZE -1MB.
COMMENT

# TODO add prompting selection of bootloader, root, and fallback partitions.
function partition
{
    # partition xweser ecosystem
    dev=$1
    # TODO verify dev existance, size
    parted -s $dev mktable gpt &&
        # bootloader specific implementation
        bootloader-parts $dev &&
        os-parts $dev
}
