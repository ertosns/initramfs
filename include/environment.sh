#!/bin/bash

# note! paths reside in the initramfs archive.
export ORIGIN_DIR=$(realpath ${BASH_SOURCE%\include/*})
export INCLUDE_DIR=$ORIGIN_DIR/include
export CONFIG_SRC=$INCLUDE_DIR/config

source $INCLUDE_DIR/utils.sh
source $INCLUDE_DIR/string.sh
source $INCLUDE_DIR/stderr.sh
if [ $GRUB_BOOTLOADER=true ]; then
    source $ORIGIN_DIR/include/bootloader/grub.sh
fi
