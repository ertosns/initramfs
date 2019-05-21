#!/bin/bash

# return partiion selected in spinning loop.
function select-partition {
    local qst=$1
    local selects=()
    local idx=0
    for uuid in /dev/disk/by-uuid/*; do
        path=$(realpath $uuid)
        selects[$((idx++))]="$uuid:$path"
    done
    PS3=$(append $WHICH_DEVICE_TO_SELECT $qst)
    select part in ${selects[@]}; do
        partl=($(echo $part | cut -s --output-delimiter ' ' -d ':' -f 1,2 ))
        echo ${partl[1]}
        break
    done
}

function prompt-select-disk
{
    local _qst=$1
    local disks=()
    local _disk_meta=$(mktemp /tmp/diskXXXXXX)
    lsblk | grep disk > $_disk_meta
    for disk in $(cut -d " " -s -f 1 $_disk_meta); do
        disks+=(/dev/$disk)
    done
    PS3=$_qst
    select disk in ${disks[@]}; do
        echo $disk
        break
    done
}

function prompt-encrypted-partition {
    local uuid=$1
    QST $SELECT_KEY_PART $uuid
    echo $(select-partition)
}

# return key-skip in spinning loop.
function prompt-key-skip {
    local invalid=true
    local skip=
    while $invalid; do
        read -p "$WHERE_PART_KEY"+$UNITES skip
        #TODO validate bytes, in support different numerical systems
        invalid=false
    done
    echo $(parse-unites $skip)
}

# return key-size in spinning loop.
function prompt-key-size {
    local invalid=true
    local size=
    while $invalid; do
        read -p "$WHAT_KEY_SIZE"+$UNITES size
        #TODO validate bytes, in support different numerical systems
        invalid=false
    done
    echo $(parse-unites $size)
}

# return filesystem-skip in spinning loop.
function prompt-filesystem-skip {
    local invalid=true
    local skip=
    while $invalid; do
        read -p "$WHERE_FILESYSTEM_KEY"+$UNITES skip
        #TODO validate bytes, in support different numerical systems
        invalid=false
    done
    echo $(parse-unites $skip)
}

# return filesystem-size in spinning loop.
function prompt-filesystem-size {
    local invalid=true
    local size=
    while $invalid; do
        read -p "$WHAT_FILESYSTEM_SIZE"+$UNITES size
        #TODO validate bytes, in support different numerical systems
        invalid=false
    done
    echo $(parse-unites $size)
}

# return key-location in a spinning loop.
function prompt-key-location {
    local invalid=true
    local location=
    while $invalid; do
        read -p "$ENTER_KEY_LOCATION" location
        realpath -e $location
        [ -$? -eq 0 ] && invalid=false
    done
    echo $location
}

# return prompt password in a spinning loop.
function prompt-password {
    local invalid=true
    local password=
    while $invalid; do
        password=$(hidden-prompt $ENTER_PASSWORD)
        #TODO validate password against shellcode, variable expansion
        # note need to support empty password for the dongle key passphrase.
        invalid=false
    done
    echo $password
}

# return mount point in a spinning loop.
function prompt-mount-point {
    local invalid=true
    local mount_point=
    while $invalid; do
        read -p "$WHAT_MOUNT_POINT" mount_point
        if [ -d  $mount_point ]; then
            invalid=false
        fi
    done
    echo $mount_point
}

# return bootloader-legacy-uri uuid
#function bootloader-legacy-part{:}
# return bootloader-uri uuid
#function bootloader-part {:}
# return os-uri uuid
#function os-part {:}

# return swap-uri uuid
#TODO verify encrypted swap, by linking file, or loop device of a swap.
#function swap-part {:}

: << KEY_HOLDER
# characteristics:
- key layout
  - default key
  - standarized key format start|size|key
  - key layout need to be encrypted, not to reveal any header start, and size. enc(start|size|key)
- enc
  - must support manul passowrd
- automate dongle generation process

KEY_HOLDER
: << DENIABLE_ENC
# characteristics:
- fallback indistinguishible from other filesystems
- number of present fs is confidencial
- boundaries of filesystem are confidential
- disk need to randomized before writing any filesystem, otherwise, boundaries will be obvious.
- installing rubberhose filesystem can be done at any moment, and boundaries shouldn't be tracked, and therefore, the only check over the overlapping boundaries persists only inside the memory of the user, or installer, and the set of keys.

DENIABLE_ENC

function init-enc-mechanism {
    # supported encryption mechanisms
    local ENC_MECHANISMS=(luks)
    if [ -n $ENC_MECHANISM ]; then ENC_MECHANISM=; fi
    if [ -n $ENC_MECHANISM_CLOSE ]; then ENC_MECHANISM_CLOSE=; fi
    local set_default=true
    for mech in ${ENC_MECHANSISMS[@]}; do
        if [ "$mech" == "$ENC_MECHANISM" ]; then
            if [ "$mech" == "luks" ]; then
                ENC_MECHANISM_CLOSE=luksclose;
            fi
            set_default=false
            break
        fi
    done
    [ $set_default = true ] && {
        ENC_MECHANISM=plain
        ENC_MECHANISM_CLOSE=close
    }
}

function generate-key-file
{
    local key_size=$DEFAULT_KEY_SIZE;
    [ $DEFAULT = false ] && [ -z $key_size ] && {
        key_size=$(prompt-key-size)
    }
    local key_file=$(mktemp "/tmp/key.XXXXXXX")
    dd if=/dev/random of=$key_file bs=1 count=$key_size
    echo $key_file
}

function save-dongle
{
    local key_file=$1
    local key_part=$DEFAULT_KEY_PART;
    [ $DEFAULT = false ] && [ -z $key_part ] && {
        key_part=$(select-partition $WHAT_IS_KEY_PARTITION)
    }
    if mount $key_part $TMP_MNT; then
        if [ -f $TMP_MNT/$DEFAULT_KEY_LOCATION ]; then
            cat $key_file >> $TMP_MNT/$DEFAULT_KEY_LOCATION
            umount $TMP_MNT
            return 0
        else
            ls $TMP_MNT
            SH "CAN'T FIND DONGLE FILE!!"
        fi
    fi
    return 1
}

function enc-key
{
    local key=$1
    local out=$(mktemp "/tmp/key.XXXXXXXXX")
    cat $in | gpg --homedir $GPG_HOME_DIR -e -c --output $out --batch --yes --passphrase "$(prompt-password)" -
    echo $out
}

function dec-key
{
    local keyfile=$1
    local out=$(mktemp "/tmp/key.XXXXXXXXX")
    cat $keyfile | gpg --homedir $GPG_HOME_DIR -d --output --batch --yes --passphrase="$(prompt-password)" $out -
    echo $out
}

# param $keyfile skip size
# return keyfile of the encrypted keylayout
function enc-keylayout
{
    local p_key=$1
    local p_skip=$2
    local p_size=$3
    local _msg=$(delimit $p_skip $p_size $p_key)
    echo $(enc-key $_msg)
}
# params key-layout
# return paramfile(seek size keyfile)
function dec-keylayout
{
    #layout: seek,size,key
    local layout=$1
    local keylayout=$(dec-key $layout)
    local out=$(mktemp "/tmp/keylayout.XXXXXX")
    local param_out=$(mktemp "/tmp/keylayout.XXXXXX")
    local boundaries=$(cat $keylaout | cut --output-delimiter ' ' -f 1,2)
    cat $keylaout | cut -f 3 > $out
    echo "$boundaries[0] $boundaries[1] $out" > "$param_out"
    echo $param_out
}
function read-key {
    local layout=$1
    local paramfile=$(dec-keylayout $layout)
    local params=$(cat $paramfile)
    local seek=${params[0]}
    local size=${params[1]}
    local keyfile=${params[2]}
    case $2 in
        'seek')
            echo $seek
            ;;
        'size')
            echo $size
            ;;
        'keyfile')
            echo $keyfile
            ;;
        '*')
            DBG "keylayout options isn't recognized"
            ;;
    esac
}

# resolve key value in global MAT matrix.
# params index key defaultvalue
function keyval
{
    local p_index=$1
    local p_key=$2
    local p_default=$3
    [ $# -eq 2 ] && p_default=$NULL
    local _value=${MAT[$p_index,$p_key]}
    {
        [ -z $_value ] || [ $_value == $NULL ]
    } && _value=$p_default
    echo $_value
}
# params <device, key_file, mapper_device_name>
# read key from standin if not presented
function dec
{
    local p_dev=$1
    local p_key=$2
    local p_mapper=$3
    [ $# -gt 1 ] && [ -f $p_key ] && p_key=$2
    [ $# -gt 2 ] && p_mapper=$3 || p_mapper=dongle

    if [ -n $p_key ]; then
        cryptsetup --key-file $p_key open --type $ENC_MECHANISM  $p_dev $p_mapper
    else
        cryptsetup open --type $ENC_MECHANISM $p_dev $p_mapper
    fi
}
# decrypt partition
# params keylayout mapper_name part mount_point
function dec-part
{
    local p_keylayout=$1
    local p_mapper_name=$2
    local p_root_part=$3
    local p_mnt_point=$4
    local _key_file=$(read-key $1 key)
    dec $p_root_part $_key_file $p_mapper_name
    # mount mapper
    #TODO read, fs type, and mount flags
    local _loopdev=$(losetup -f)
    local _fs_seek=$(read-key $p_keylayout seek)
    local _fs_size=$(read-key $p_keylayout size)
    losetup -f -o $_fs_seek --sizelimit $_fs_size /dev/mapper/$p_mapper_name
    mount /dev/$_loopdev $p_mnt_point
}

#params key_partition_uuid
#return find key-file, and set it value in array RET at index 0, return 0 for success, 1 otherwise.
function key-file {
    #kernel devfs, uuid, label subsystemds are accepted
    local uuid=$1
    local keylayout_file=$(mktemp "/tmp/key.$uuid.XXXXXXX")
    local key_part=$DEFAULT_KEY_PART;
    [ $DEFAULT = false ] && [ -z $key_part ] && {
        key_part=$(select-partition $WHAT_IS_KEY_PARTITION)
    }
    read-fs-key () {
        if mount $key_part $TMP_MNT; then
            if [ -f $TMP_MNT/$DEFAULT_KEY_LOCATION ]; then
                cat $TMP_MNT/$DEFAULT_KEY_LOCATION > $keylayout_file
                umount $TMP_MNT
                $(dec-keylayout $key_file) > $key_file
                return 0
            else
                ls $TMP_MNT
                SH "CAN'T FIND DONGLE FILE!!"
            fi
        fi
        return 1
    }
    read-part-key() {
        key_size=$DEFAULT_KEY_SIZE;
        [ $DEFAULT = false ] && [ -z $key_size ] && {
            key_size=$(prompt-key-size)
        }
        key_skip=$DEFAULT_KEY_SKIP;
        [ $DEFAULT = false ] && [ -z $key_skip ] && {
            key_skip=$(prompt-key-skip)
        }
        dd if=$key_part of=$keylayout_file bs=1 skip=$key_skip count=$key_size &&
            return 0
        return 1
    }
    if [ -n "$DEFAULT_KEY_LOCATION" ]; then
        #TODO return
        echo "key_file: $keylayout_file"
        read-fs-key &&
            RET[0]=$keylayout_file &&
            return
    fi
    #read-part-key &&
    #echo $key_file &&
    #return
    SH $FAILURE_READING_KEY_FILE
}



# note below functions need to be part of api used in installation script.
function init-dongle
{
    # each row is representation of the partition resolution
    # columns are <PART,MOUNT_POINT,KEY_PART,KEY_PATH,KEY_SKIP,KEY_SIZE,NAME>
    # -1 value ie equivalent to null
    #TODO NULL value inside matrix need to be either 0, -1.
    local ROOT=$1
    local keylayout_file=$(mktemp /tmp/dongle.key.XXXXXXX)
    local close_mappers=()
    init-enc-mechanism
    mkdir -p $ROOT
    local ROWS=
    # params row_index mount_point
    # check the default for decrypting default part
    function configured-mount
    {
        r=$1
        mount_point=$2
        if [ ! -d $mount_point ]; then
            DBG "invalid mount point $mount_point"
            return 1
        fi
        # check encrypted root
        key_part_uuid=$(keyval $r KEY_PART)
        [ $key_part_uuid == $NULL ] &&
            key_part_uuid=$(cmdline bootloader) &&
            [ $key_part_uuid == $NULL ] && {
                DBG "missing key part uuid"
                return 1 # TODO add warnings
            }
        key_part=$(realpath  /"dev/disk/by-uuid/$key_part_uuid")
        # key bytes location resolutions
        key_skip=$(keyval $r KEY_SKIP)
        key_found=false
        if [ $key_skip != $NULL ]; then
            key_size=$(keyval $r KEY_SIZE 512) &&
                dd if=$key_part of=$keylayout_file skip=$key_skip count=$key_size &&
                key_found=true
        fi
        if [ $key_found = false ]; then
            mount $key_part $TMP_MNT &&
                {
                    [ $? -ne 0 ] &&
                        {
                            DBG "mount failure of $key_part at $TMP_MNT"
                            return 1
                        }
                    DONGLE_PATH=${TMP_MNT}${DEFAULT_KEY_LOCATION}
                    if [ -f $DONGLE_PATH ]; then
                        cat $DONGLE_PATH > $keylayout_file
                    else
                        DBG "failed to find default key"
                        return 1
                    fi
                    true;
                } &&
                umount $TMP_MNT
        fi
        local root_part_uuid=$(keyval $r PART)
        local root_part=$(realpath "/dev/disk/by-uuid/$root_part_uuid")
        [ $root_part == $NULL ] && {
            DBG "can't find part_uuid"
            return 1 #TODO (w2) add warnings
        }
        mapper_name=$(keyval $r MAPPER_NAME $MAPPER_DEFAULT)
        INF $MOUNTED_AT $mount_point $WITH_UUID $root_part_uuid
        dec-part $keylayout_file $mapper_name $root_part $mount_point
    }
    #params part_mount_point mapper_name
    function prompt-mount
    {
        local p_part_mount=$1
        local p_mapper=$2
        [ -z $mapper ] && mapper=$MAPPER_DEFAULT
        #TODO check partition filesystem, validate it's support, same for prompt_mounts below
        #TODO fix blkid has quotation around uuid
        blkid_tmp=$(mktemp /tmp/blkid.XXXXXXX)
        blkid > $blkid_tmp
        parse-config $blkid_tmp UUID TYPE
        declare -A _luks_enc_partitions
        #DBG "rows: ${MAT[@]}, indeces: ${!MAT[@]}"
        for ((r=0; r<$ROWS; r++)); do
            #TODO support all linux avaiable encryption mechanisms.
            #TODO plain encrypted has no headers!, different detection algorith is required.
            # for crypto-luks, this options depends on the default
            if [ ${MAT[$r,TYPE]} == "crypto_LUKS" ]; then
                _luks_enc_partitions+=${MAT[$r,UUID]}
            fi
        done
        #DBG "luks: ${_luks_enc_partitions[@]}"
        for ((r=0; r<${#_luks_enc_partitions[@]}; r++)); do
            #INF $LUKS_ENCRYPTION_DETECTED ${_luks_enc_partitions[$r]}
            if $(yes-no-prompt $WHETHER_TO_DECRYPT ${_luks_enc_partitions[$r]}); then
                key-file ${_luks_enc_partitions[$r]}
                _keylayout_file=${RET[0]}
                {

                    [ -z $p_part_mount ] && p_part_mount=$(prompt-mount-point)
                    [ -z $p_part_mount ] && p_part_mount=$TMP_MNT
                }
                INF "$(realpath /dev/disk/by-uuid/${_luks_enc_partitions[$r]}) - $_keylayout_file -  $p_part_mount"
                dec-part $_keylayout_file p_mapper $(realpath /dev/disk/by-uuid/${_luks_enc_partitions[$r]}) $p_part_mount
            fi
        done
    }
    function mount-encrypted-root
    {
        DBG $FUNCNAME
        parse-config $DEC_CONF_PATH ${DEC_CONF_KEYS[@]}
        for ((r=0; r<$ROWS; r++))
            {
                mount_point=$(keyval $r MOUNT_POINT)
                if [ $mount_point == '/' ] && configured-mount $r $ROOT; then
                    return 0
                fi
            }
            return 1
    }
    function mount-cmdline-root
    {
        DBG $FUNCNAME
        # assuming it's not encrypted
        #TODO read fs, and mount flags
        #TODO support dev, and label
        device=$(cmdline root)
        if ! mount -n "/dev/disk/by-uuid/$device" $ROOT; then
            DBG "no mount device" $device
            return 1
        fi
        return 0
    }
    function prompt-mount-root
    {
        DBG $FUNCNAME
        prompt-mount $ROOT root
    }
    if ! mount-encrypted-root; then
        WRN 'no encrypted root directory'
        if ! mount-cmdline-root; then
            WRN 'failed to mount root filesystem'
            prompt-mount-root
        fi
    fi
    return 0
}
