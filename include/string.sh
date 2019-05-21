#!/bin/bash

source "$INCLUDE_DIR/stderr.sh"

export UNITES="\nappend G,g for gigabytes, M,m for megabytes, K,k for kilobytes"
export DO_YOU_WANT_TO_DECRYPT="do you want to encrypt"
export LUKS_ENCRYPTION_DETECTED="luks encrypted detected"
export DECRYPT_FOLLOWING="select weither to decrypt the following partitions"
export FAILURE_READING_KEY_FILE="failed reading key file"
export WHERE_PART_KEY="where is stored key in bytes?"
export WHAT_KEY_SIZE="what is the key size?"
export WHERE_FILESYSTEM_KEY="where is filesystem locates?"
export WHAT_FILESYSTEM_SIZE="what is the filesystem size?"
export SELECT_KEY_PART="select key partition for"
export RESCUE_MODE='rescue mode!'
export WHICH_DEVICE_TO_SELECT="which device to select?"
export ENETER_KEY_LOCATION="enter key location"
export ENTER_PASSWORD="enter password"
export WHETHER_TO_DECRYPT="whether to decrypt"
export MOUNTED_AT="mounted at"
export WITH_UUID="with uuid"
export STR_YES="YES"
export STR_NO="NO"
export WHAT_MOUNT_POINT="what is the mount point?"
export WHAT_IS_KEY_PARTITION="what is key partition"
export WHAT_IS_THE_INSTALLATION_DISK="what is the installation medium?"
export DENIABLE_INSTALLATION="weither to install another deniable system?y/n"
export SELECT_INSTALLING_DONGLE="select installing dongle"

function append {
    str=""
    for segment in "$@"; do
        str+=" $segment"
    done
    echo $str
}

function translate {
    INF "configured language $LANGUAGE"
    if [ "$LANGUAGE" == "ku" ]; then
        #TODO do translation to Kurdish
        :
    else
        WRN "configured language $LANGUAGE isn't supported"
    fi
}
