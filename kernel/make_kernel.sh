#!/bin/sh

# Copyright (C) 2023, John Clark <inindev@gmail.com>

set -e

# script exit codes:
#   1: missing utility
#   5: invalid file hash
#   7: use screen session
#   8: superuser disallowed

config_fixups() {
    local lpath=$1

    # enable realtek pci wireless
    echo 'CONFIG_RTW88=m' >> "$lpath/arch/arm64/configs/defconfig"
    echo 'CONFIG_RTW88_8822CE=m' >> "$lpath/arch/arm64/configs/defconfig"
    echo 'CONFIG_RTW88_8723DE=m' >> "$lpath/arch/arm64/configs/defconfig"
    echo 'CONFIG_RTW88_8821CE=m' >> "$lpath/arch/arm64/configs/defconfig"

    # enable rockchip usb3
    echo 'CONFIG_CROS_EC_TYPEC=m' >> "$lpath/arch/arm64/configs/defconfig"
    echo 'CONFIG_CROS_TYPEC_SWITCH=m' >> "$lpath/arch/arm64/configs/defconfig"
    echo 'CONFIG_PHY_ROCKCHIP_USBDP=y' >> "$lpath/arch/arm64/configs/defconfig"

    #echo 6 > "$lpath/.version"
}

main() {
    local linux='https://git.kernel.org/torvalds/t/linux-6.7-rc7.tar.gz'
    local lxsha='d0c92280db03d6f776d6f67faf035eba904bc5f2a04a807dfab77d1ebce39b02'

    local lf="$(basename "$linux")"
    local lv="$(echo "$lf" | sed -nE 's/linux-(.*)\.tar\..z/\1/p')"

    if [ '_clean' = "_$1" ]; then
        echo "\n${h1}cleaning...${rst}"
        rm -fv *.deb
        rm -rfv kernel-$lv/*.deb
        rm -rfv kernel-$lv/*.buildinfo
        rm -rfv kernel-$lv/*.changes
        rm -rf "kernel-$lv/linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    check_installed 'screen' 'build-essential' 'python3' 'flex' 'bison' 'pahole' 'debhelper'  'bc' 'rsync' 'libncurses-dev' 'libelf-dev' 'libssl-dev' 'lz4' 'zstd'


    mkdir -p "kernel-$lv"
    if ! [ -e "kernel-$lv/$lf" ]; then
        if [ -e "./$lf" ]; then
            echo "linking local copy of linux $lv"
            ln -sv "../$lf" "kernel-$lv/$lf"
        elif [ -e "../dtb/$lf" ]; then
            echo "using local copy of linux $lv"
            cp -v "../dtb/$lf" "kernel-$lv"
        else
            echo "downloading linux $lv from $linux"
            echo curl -x socks5://192.168.199.1:1080 --create-dirs -O --output-dir "kernel-$lv" -L "$linux"
            curl -x socks5://192.168.199.1:1080 --create-dirs -O --output-dir "kernel-$lv" -L "$linux"
        fi
    fi

    if [ "_$lxsha" != "_$(sha256sum "kernel-$lv/$lf" | cut -c1-64)" ]; then
        echo "invalid hash for linux source file: $lf"
        exit 5
    fi

    if [ ! -d "kernel-$lv/linux-$lv" ]; then
        tar -C "kernel-$lv" -xavf "kernel-$lv/$lf"

        local patch
        for patch in patches/*.patch; do
            patch -p1 -d "kernel-$lv/linux-$lv" -i "../../$patch"
        done
    fi

    # build
    if [ '_inc' != "_$1" ]; then
        echo "\n${h1}configuring source tree...${rst}"
        make -C "kernel-$lv/linux-$lv" mrproper
        [ -z "$1" ] || echo "$1" > "kernel-$lv/linux-$lv/.version"
        config_fixups "kernel-$lv/linux-$lv"
        make -C "kernel-$lv/linux-$lv" ARCH=arm64 inindev_defconfig
    fi

    echo "\n${h1}beginning compile...${rst}"
    rm -f linux-*.deb
    local kv="$(make --no-print-directory -C "kernel-$lv/linux-$lv" kernelversion)"
    local bv="$(expr "$(cat "kernel-$lv/linux-$lv/.version" 2>/dev/null || echo 0)" + 1 2>/dev/null)"
    export SOURCE_DATE_EPOCH="$(stat -c %Y "kernel-$lv/linux-$lv/README")"
    export KDEB_CHANGELOG_DIST='stable'
    export KBUILD_BUILD_TIMESTAMP="Debian $kv-$bv $(date -d @$SOURCE_DATE_EPOCH +'(%Y-%m-%d)')"
    export KBUILD_BUILD_HOST='github.com/inindev'
    export KBUILD_BUILD_USER='linux-kernel'
    export KBUILD_BUILD_VERSION="$bv"

    local t1=$(date +%s)
    nice make -C "kernel-$lv/linux-$lv" -j"$(nproc)" CC="$(readlink /usr/bin/gcc)" bindeb-pkg KBUILD_IMAGE='arch/arm64/boot/Image' LOCALVERSION="-$bv-arm64"
    local t2=$(date +%s)
    echo "\n${cya}kernel package ready (elapsed: $(date -d@$((t2-t1)) '+%H:%M:%S'))${mag}"
    ln -sfv "kernel-$lv/linux-image-$kv-$bv-arm64_$kv-${bv}_arm64.deb"
    ln -sfv "kernel-$lv/linux-headers-$kv-$bv-arm64_$kv-${bv}_arm64.deb"
    echo "${rst}"
}

check_installed() {
    local todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo "   run: ${bld}${grn}sudo apt update && sudo apt -y install$todo${rst}\n"
        exit 1
    fi
}

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="${blu}==>${rst} ${bld}"

if [ 0 -eq $(id -u) ]; then
    echo 'do not compile as root'
    exit 8
fi

cd "$(dirname "$(realpath "$0")")"
main "$@"

