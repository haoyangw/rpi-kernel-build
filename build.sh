#!/bin/bash

LOCAL_PATH=$(pwd)
#export PATH="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin:$PATH"
#export LD_LIBRARY_PATH="$LOCAL_PATH/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH"

# Start the stopwatch
start=$(date +%s)

echo "Setting up linux kernel source code"
if [ ! -d "$LOCAL_PATH/rpi-linux" ]; then
	git clone https://github.com/raspberrypi/linux.git rpi-linux --single-branch --branch rpi-4.19.y --depth 1
    git checkout -f origin/rpi-4.19.y
else
    cd rpi-linux
    make clean && make mrproper
    git reset --hard origin/rpi-4.19.y
    cd $LOCAL_PATH
fi

# Make copy of source code
echo "Making a copy of the kernel source code as 'rpi-source'"
if [ -d "$LOCAL_PATH/rpi-source" ]; then
  #mkdir -p "$LOCAL_PATH/rpi-source"
  rm -Rf $LOCAL_PATH/rpi-source
fi
cp -rf "$LOCAL_PATH/rpi-linux" "$LOCAL_PATH/rpi-source"
rm -Rf "$LOCAL_PATH/rpi-source/.git" "$LOCAL_PATH/rpi-source/.github"


# Download Raspberry Pi GCC
if [ ! -f "$LOCAL_PATH/native-gcc-9.3.0-pi_64.tar.gz" ]; then
    echo "Downloading GCC for Raspberry Pi 64bit"
	wget https://sourceforge.net/projects/raspberry-pi-cross-compilers/files/Bonus%20Raspberry%20Pi%20GCC%2064-Bit%20Toolchains/Raspberry%20Pi%20GCC%2064-Bit%20Native-Compiler%20Toolchains/GCC%209.3.0/native-gcc-9.3.0-pi_64.tar.gz/download -O native-gcc-9.3.0-pi_64.tar.gz
fi
if [ ! -d "$LOCAL_PATH/native-pi-gcc-9.3.0-64" ]; then
    echo "Extracting the downloaded GCC archive"
	tar -xzf $LOCAL_PATH/native-gcc-9.3.0-pi_64.tar.gz
    if [ ! -d "$LOCAL_PATH/native-pi-gcc-9.3.0-64" ]; then
        echo "Check the downloaded tar.gz file! Unexpected error"
        exit -1
    fi
fi

# CONFIGURE / MAKE
echo "Configuring make"
cd "$LOCAL_PATH/rpi-linux"
LD_LIBRARY_PATH="$LOCAL_PATH/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH" make -j$(nproc) CC="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-gcc-9.3.0" CXX="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-g++-9.3.0" bcm2711_defconfig
cp -f /boot/config "$LOCAL_PATH/rpi-linux/.config"

# % Run conform_config scripts which fix kernel flags to work correctly in arm64
echo "Running conform scripts"
wget https://raw.githubusercontent.com/sakaki-/bcm2711-kernel-bis/master/conform_config.sh
chmod +x conform_config.sh
./conform_config.sh
rm -rf conform_config.sh*
wget https://raw.githubusercontent.com/TheRemote/Ubuntu-Server-raspi4-unofficial/master/conform_config_jamesachambers.sh
chmod +x conform_config_jamesachambers.sh
./conform_config_jamesachambers.sh
rm -rf conform_config_jamesachambers.sh*

# % Run prepare to register all our .config changes
echo "Setting up new kernel config additions(if any)"
cd "$LOCAL_PATH/rpi-linux"
LD_LIBRARY_PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH make -j$(nproc) CC="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-gcc-9.3.0" CXX="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-g++-9.3.0" prepare dtbs  

export KERNEL_VERSION=`cat "$LOCAL_PATH/rpi-linux/include/config/kernel.release"`

# % Prepare modules
echo "Preparing kernel modules"
LD_LIBRARY_PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH make -j$(nproc) CC="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-gcc-9.3.0" CXX="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-g++-9.3.0" modules_prepare

# % Prepare and build the rpi-linux source - create debian packages to make it easy to update the image
echo "Compiling kernel now"
#LD_LIBRARY_PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH sudo make -j$(nproc) CC="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-gcc-9.3.0" CXX="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-g++-9.3.0" DTC_FLAGS="-@ -H epapr" KDEB_PKGVERSION="${KERNEL_VERSION}" deb-pkg
LD_LIBRARY_PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH make -j$(nproc) CC="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-gcc-9.3.0" CXX="$LOCAL_PATH/native-pi-gcc-9.3.0-64/bin/aarch64-linux-gnu-g++-9.3.0" DTC_FLAGS="-@ -H epapr"

#cd $LOCAL_PATH
#if [ -d "$LOCAL_PATH/output" ]; then
#  rm -R "$LOCAL_PATH/output"
#fi
#mkdir -p output
#mv linux-* output/
#echo "Compilation complete. Install the following debs:"
echo ""
echo "Compilation complete"
echo ""
#ls -d output/linux-image*.deb output/linux-headers*.deb
#sudo chown exp2.exp2 ouput/*.deb

# Timecheck?
timecheck=$(echo "$(date +%s) - $start" | bc)
echo "***************************************************"
echo -n "Compilation took "
printf '%dhour(s) %dmin(s) %dsec(s)\n' $(($timecheck/3600)) $(($timecheck%3600/60)) $(($timecheck%60))
echo "***************************************************"

echo "Would you like to install the kernel? "
select yn in "Yes" "No"; do
    case $yn in
        Yes )
            echo "Installing the kernel now"
            if [ -x "$LOCAL_PATH"/install-kernel.sh ]; then
                cd "$LOCAL_PATH"
                sudo "$LOCAL_PATH"/install-kernel.sh
            fi
            break;;
        No ) exit;;
    esac
done

exit 0

# % Make DTBOs
# % Build kernel modules
#PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/bin:$PATH LD_LIBRARY_PATH="$LOCAL_PATH"/native-pi-gcc-9.3.0-64/lib:$LD_LIBRARY_PATH sudo make -j$(nproc) CC=aarch64-linux-gnu-gcc-9.3.0 CXX=aarch64-linux-gnu-g++-9.3.0 DEPMOD=echo MODLIB=./lib/modules/"${KERNEL_VERSION}" INSTALL_FW_PATH=./lib/firmware modules_install
#sudo depmod --basedir . "${KERNEL_VERSION}"
#sudo chown -R "$USER" .
