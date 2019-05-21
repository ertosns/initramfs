#!/bin/

INITRAMFS_PACKAGED_SRC=
INITRAMFS_DES=/opt/initramfs
DEC_CONF_KEYS=(PART MOUNT KEY_PART KEY_PATH KEY_SKIP KEY_SIZE NAME)
DEC_CONF_PATH=$CONFIG_DES/mapper.cfg
GRUB_CONF_KEYS=(INITRAMFS KERNEL NAME UUID)
GRUB_CONF_PATH=$CONFIG_DES/bootloader.cfg
MAPPER_DEFAULT=private
TMP_MNT=/mnt
ROOT=/.root
ROOT_BOOT=/.root/boot
#TODO trace root_boot origin, and remove mkdir below
mkdir -p $ROOT_BOOT
INSTALL_LAYOUT=install_layout.cfg
KERNEL_PATH=/boot/vmlinuz-$(uname -r)
INITRAMFS_PATH=/boot/initramfs.cpio
#default mount point
NULL='\0'
INSTALL_MODE=INSTALL
EXECUTE_MODE=EXECUTE
BOOTLOADER_END=1G
CLONE_PATH=/.clone

SH () {
	ERR $RESCUE_MODE
    ERR $1
    /bin/bash
}

## matrix, array, and configuration processing ##
# global 1d array of arbitrary size used to simulate non-numerical return values
declare -g -A RET
# global 2d matrix of arbitary size used to communicated 2d data.
declare -g -A MAT
# rows in MAT, or size in RET
ROWS=0
# columns in MAT
COLS=0

## disk topology ##
DISK_BIOS_BOOTLOADER_PART=0
DISK_BOOTLOADER_CONFIG_PART=1
DISK_OS_PART=2
# this is removed from the topology, it's simpiler design to leave fallback instllation as part of deniable OS.
#DISK_FALLBACK_OS_PART=4

function is-uuid
{
    local _uuid=$1
    #TODO (res) some uuid's have 4-4 hex format like with vfat, while some partuuid's are variant as well as 8-2!, is there a standard form?
    #if [[ "$_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4]-[[:xdigit:]]{12}$ ]]; then
    if [[ "$_uuid" =~ ^([[:xdigit:]]{1,}-)*[[:xdigit:]]{1,}$ ]]; then
        return $TRUE
    else
        return $FALSE
    fi
}

function is-part-uuid
{
    local _uuid=$1
    if [[ "$_uuid" =~ ^([[:xdigit:]]{1,}-)*[[:xdigit:]]{1,}$ ]]; then
        return $TRUE
    else
        return $FALSE
    fi

}

function is-subsystem {
    local des=$1
    return [ -e "$des" ]
}

function get-subsystem {
    local des=$1
    if $(is-uuid $des); then
        echo $(readlink -e /dev/disk/by-uuid/$des)
    else
        echo $(readlink -e $des)
    fi
}

function get-partuuid
{
    local p_path=$1
    local _blkid=($(blkid | grep $p_path))
    local _keyval=
    for item in ${_blkid[@]}; do
        _keyval=$(echo $item | cut -s -d "=" --output-delimiter=" " -f 1,2)
       [[ ${_keyval[0]} == "PARTUUID" ]] && echo $(unquote ${_keyval[1]}) && break
    done
}
function get-uuid
{
    local p_path=$1
    local _blkid=($(blkid | grep $p_path))
    local _keyval=
    for item in ${_blkid[@]}; do
        _keyval=($(echo $item | cut -s -d "=" --output-delimiter=" " -f 1,2))
        [[ ${_keyval[0]} == "UUID" ]] && echo $(unquote ${_keyval[1]}) && break
    done
}

# echo returns
function hidden-prompt {
    local passwd=
    if [ $# -gt 0 ]; then
        read -s -p "$@" passwd
    else
        read -s passwd
    fi
    echo $passwd
}

function refresh-ret {
    unset RET
    declare -g -A RET
}

function refresh-mat {
    unset MAT
    declare -g -A MAT
}

function delimit {
    local DELIMITER=','
    local str=$1
    for param in ${@:1:$#}; do
        str+=$KEY_DELIMITER
        str+=$param
    done
    echo $str
}

# read unit size, and expand it in bytes
function parse-unites {
    # note the internal size unite is generalized to bytes.
    local size=$1
    local scalar=$(echo $size | grep -o -E '[0-9]+(.[0-9]+)?')
    local unite=$(echo $size | grep -o -E '[KMG]')
    case $unite in
        'G')
            scalar=$(bc <<< $scalar*1024*1024*1024)
            ;;
        'M')
            scalar=$(bc <<< $scalar*1024*1024)
            ;;
        'K')
            scalar=$(bc <<< $scalar*1024)
            ;;
        *)
            ;;
    esac
    echo $scalar
}

# echo returns
function unquote
{
    local str=$1
    str=${str#\"}
    str=${str%\"}
    echo $str
}

function read-dev-link
{
    local p_path=$1
    local _lsl=$(ls -ld $p_path)
    local _part=${_lsl##*/}
    INF "$p_path:$_lsl:$_part"
    echo /dev/$_part
}

# params disk part_num
function get-disk-part
{
    #note! sleep is essential for the partitining to take place, otherwise the result is uncertain, and with high propablities kernel doesn't return accurate readings, and cmds as ls -ld, readlink realpath fails
    sleep 1
    local p_disk=$1
    local p_part_idx=$2
    local _disk_ss=$(get-subsystem $p_disk)
    # strip last char if it ends with /
    if [[ $_disk_ss == /[a-zA-Z0-9/]*/ ]]; then
        _disk_ss=${_disk_ss:0:-1}
    fi
    local _strip_disk=${_disk_ss##*/}
    local partline=($(lsblk | grep $_strip_disk | grep disk))
    local part=${partline[1]}
    IFS=$':'; maj_min=($part); unset IFS
    local major=${maj_min[0]}
    local minor=${maj_min[1]}
    ((minor+=$p_part_idx))
    INF "$BASH_SOURCE:get-disk-part:$p_disk:$minor:$major:$part:$partline:$_strip_disk:$_disk_ss:$(readlink -n -e /dev/block/$major:$minor)"
    echo $(readlink -n -e  /dev/block/$major:$minor)
}

# return bytes
function get-disk-size
{
    local path=$(get-subsystem $1)
    local name=${path##\/*\/}
    local line=($(lsblk | grep $name | grep disk))
    local size=${line[3]}
    echo $(parse-unites $size)
}

# return bytes
function get-part-size {
    local path=$(get-subsystem $1)
    local name=${path##\/*\/}
    local line=($(lsblk | grep $name | grep part))
    local size=${line[3]}
    echo $(parse-unites $size)
}

# parse keyvalue configuration file
# lines starting with hash sign are ignored
# execution_syntax: $(parse_config config_file key1[key2[ ... [keyn]]])
function parse-config {
    function count-rows {
        r_count=0
        # matrix has no order!, it's hashed i guess?
        for row in ${!MAT[@]}; do
            tmp_count=$(echo $row | cut -s -d ',' -f 1)
            if [ $tmp_count -ge $r_count ]; then
                r_count=$(bc <<< $tmp_count+1)
            fi
        done
        ROWS=$r_count
    }
    local config=$1
    refresh-mat
    #bash string processing
    #TODO how to delimit in bash
    local match_keys=${@:2:$#}
    IFS=$'\n'; lines=($(cat $config)); unset IFS
    #valid row
    local vrow=0
    for ((row=0; row<${#lines[@]}; row++)); do
        local matched=false
        local parcels=(${lines[$row]})
        # comment lines
        [ ${parcels[0]} == "#" ] && continue
        for parcel in ${parcels[@]}; do
            keyval=($(cut -s --output-delimiter=' ' -d '=' -f 1,2 <<< $parcel))
            [ ${#keyval[@]} -eq 0 ] && continue
            for match_key in ${match_keys[@]}; do
                [ -z ${MAT[$vrow,$match_key]} ] && MAT[$vrow,$match_key]=$NULL
                [ $match_key == ${keyval[0]} ] && {
                    matched=true
                    MAT[$vrow,$match_key]=$(unquote ${keyval[1]})
                    break
                }
            done
        done
        $matched && ((vrow++))
    done
    count-rows
}

function yes-no-prompt {
    local qst=$@
    local invalid=true
    local yes=false
    while $invalid; do
        read -p "${qst[@]}($STR_YES/$STR_NO)?" answer
        case $answer in
            $STR_YES)
                yes=true
                invalid=false
                break
                ;;
            $STR_NO)
                invalid=false
                break
                ;;
        esac
    done
    [[ $yes ]] && return 0 || return 1
}

# echo returns
# execution $(cmdline key)
function cmdline {
    local key=$1
    local cmdline_str=$(cat /proc/cmdline)
    for param in ${cmdline_str[@]}; do
        keyval=($(cut -s --output-delimiter=" " -d "=" -f 1,2,3,4 <<< $param))
        if [ x${keyval[0]} == x$key ]; then
            echo ${keyval[-1]}
            return
        fi
    done
    echo $NULL
}

function bind-fstab
{
    local target=$1
    local src=$2
    local des=$3
    mkdir -p $des
    _fstab_line=$src\t$des\tnone\trw,bind\t0\t0\n
    echo -e $_fstab_line >> $target/etc/fstab
}
