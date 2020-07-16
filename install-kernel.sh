#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   me=`basename "$0"`
   echo "Installation of kernel requires superuser access"
   echo "Run me with './$me' instead next time" 
   exit -1
fi

LOCAL_PATH=$(pwd)
# Start the stopwatch
start=$(date +%s)

if [ ! -d "$LOCAL_PATH"/rpi-linux ]; then
    echo "Kernel source cannot be found! Fatal error"
    exit -1
fi
if [ -f "$LOCAL_PATH"/rpi-linux/include/generated/utsrelease.h ]; then
    #KERNEL_VERSION=`cat "$LOCAL_PATH/rpi-linux/include/config/kernel.release"`
    KERNEL_VERSION=`cat "$LOCAL_PATH"/rpi-linux/include/generated/utsrelease.h | sed -e 's/.*"\(.*\)".*/\1/'`
else
    echo "Fatal error: kernel release file not found"
    exit -1
fi

# % Copy the new kernel modules
echo "Installing kernel modules"
#cp -rf "$LOCAL_PATH/rpi-linux/debian/tmp/lib/modules/${KERNEL_VERSION}*/*" "/lib/modules/${KERNEL_VERSION}"
cd "$LOCAL_PATH"/rpi-linux
make -j$(nproc) DEPMOD=echo MODLIB="$LOCAL_PATH"/rpi-linux/lib/modules/"${KERNEL_VERSION}" INSTALL_FW_PATH="$LOCAL_PATH"/rpi-linux/lib/firmware modules_install > /dev/null
depmod --basedir "$LOCAL_PATH"/rpi-linux "${KERNEL_VERSION}"
chown -R "$USER" "$LOCAL_PATH"/rpi-linux
mkdir -p /lib/modules/"${KERNEL_VERSION}"
cp --recursive --update --archive --no-preserve=ownership "$LOCAL_PATH"/rpi-linux/lib/modules/"${KERNEL_VERSION}" /lib/modules
cp -rf "$LOCAL_PATH"/rpi-linux/arch/arm64/boot/dts/broadcom/*.dtb /boot/firmware
cp -rf "$LOCAL_PATH"/rpi-linux/arch/arm64/boot/dts/overlays/*.dtb* /boot/firmware/overlays
cd "$LOCAL_PATH"

# % Remove initramfs actions for invalid existing kernels, then create a new link to our new custom kernel
sha1sum=$(sha1sum /boot/vmlinux-"${KERNEL_VERSION}")
mkdir -p /var/lib/initramfs-tools
echo "$sha1sum  /boot/vmlinux-${KERNEL_VERSION}" | tee -a /var/lib/initramfs-tools/"${KERNEL_VERSION}" >/dev/null;

echo "Installing kernel"
cp -rf "$LOCAL_PATH"/rpi-linux/arch/arm64/boot/Image /boot/kernel8.img
if [ -f /boot/firmware/kernel8.img ]; then
    cp -rf "$LOCAL_PATH"/rpi-linux/arch/arm64/boot/Image /boot/firmware/kernel8.img
fi
cp -rf "$LOCAL_PATH"/rpi-linux/vmlinux /boot/vmlinux-"${KERNEL_VERSION}"
cp -rf "$LOCAL_PATH"/rpi-linux/System.map /boot/System.map-"${KERNEL_VERSION}"
cp -rf "$LOCAL_PATH"/rpi-linux/Module.symvers /boot/Module.symvers-"${KERNEL_VERSION}"
cp -rf "$LOCAL_PATH"/rpi-linux/.config /boot/config-"${KERNEL_VERSION}"
update-initramfs -c -k "${KERNEL_VERSION}"

echo "Switching to newly installed kernel"
cd /boot
rm -rf initrd.img.old
mv initrd.img initrd.img.old
rm -rf vmlinux
rm -rf System.map
rm -rf Module.symvers
rm -rf config
ln -s initrd.img-"${KERNEL_VERSION}" initrd.img
ln -s vmlinux-"${KERNEL_VERSION}" vmlinux
ln -s System.map-"${KERNEL_VERSION}" System.map
ln -s Module.symvers-"${KERNEL_VERSION}" Module.symvers
ln -s config-"${KERNEL_VERSION}" config
sync; sync
cd "$LOCAL_PATH"/rpi-linux

# Prepare source code to be able to build modules
echo "Installing kernel source code to /usr/src"
if [ -d /usr/src/"${KERNEL_VERSION}" ]; then
    rm -Rf /usr/src/"${KERNEL_VERSION}"
fi
mkdir -p /usr/src/"${KERNEL_VERSION}"
cp -rf "$LOCAL_PATH"/rpi-source/* /usr/src/"${KERNEL_VERSION}"
cp -rf "$LOCAL_PATH"/rpi-linux/Module.symvers /usr/src/"${KERNEL_VERSION}"/Module.symvers
cd /usr/src/"${KERNEL_VERSION}"

echo "Preparing installed kernel source"
make -j4 bcm2711_defconfig
cp -f /boot/config .config
make -j4 prepare
make -j4 modules_prepare

# Create kernel header/source symlink
echo "Creating symlinks of kernel source for future compilation"
rm -rf /lib/modules/"${KERNEL_VERSION}"/build 
rm -rf /lib/modules/"${KERNEL_VERSION}"/source
ln -s /usr/src/"${KERNEL_VERSION}"/ /lib/modules/"${KERNEL_VERSION}"/build
ln -s /usr/src/"${KERNEL_VERSION}"/ /lib/modules/"${KERNEL_VERSION}"/source

echo ""
echo "Installation complete! Reboot system now to activate the new kernel"
echo ""

# Timecheck?
timecheck=$(echo "$(date +%s) - $start" | bc)
echo "***************************************************"
echo -n "Installation took "
printf '%dhour(s) %dmin(s) %dsec(s)\n' $(($timecheck/3600)) $(($timecheck%3600/60)) $(($timecheck%60))
echo "***************************************************"
echo ""

exit 0
