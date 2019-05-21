#!/bin/bash

: << INSTALLING-LAYOUT
/root.$target_arch is the os root.
INSTALLING-LAYOUT


#function _download-basic-debian {:}

function _download-basic-arch
{
    p_clone=$1
    # download (recent stable) basic iso
    # TODO discover the worldwide url
    _release_date=2019.03.01
    _url=http://mirror.rackspace.com/archlinux/iso/$_release_date/archlinux-$_release_date-x86_64.iso
    _sha1=http://mirror.rackspace.com/archlinux/iso/$_release_date/sha1sums.txt
    wget -o $p_clone $_url
    #TODO verify signature
}

function copy-os-clone
{
    local p_disk=$1
    local _storage_part=$(get-disk-part $p_disk $STORAGE_PART_IDX)
    mount $_storage_part /mnt && {
        cp -rf /mnt/$CLONE_PATH/* $ROOT
    } && umount $_storage_part
}

# no params, and installation with to $ROOT (/.root defined in init.in)
function install-os ()
{
    local p_disk=$1
    if ! $PROPAGATE; then
        # installation of xweser as initramfs
        if $XWESER_DEBIAN || $XWESER_ARCH; then
            #TODO verify, and setup local connectivity.
            if $INSTALL_DEBIAN; then _download-basic-debian $CLONE_PATH; fi
            if $INSTALL_ARCH; then _download-basic-arch $CLONE_PATH; fi
            #TODO complete installation.
        else
            # for installing copy the /.clone from storage part to the targed machine.
            copy-os-clone $p_disk
        fi
    else
        self-propagate
    fi
    # installation of xweser
    cp -rf $_clone $ROOT
}
