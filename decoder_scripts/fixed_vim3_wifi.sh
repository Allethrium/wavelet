#this is a set of commands to apply a kernel patch that will fix the VIM3's broken wifi adapter.
cd /tmp
wget https://dl.khadas.com/.test/vim3/linux-dtb-amlogic-mainline_1.4.2_arm64.deb
wget https://dl.khadas.com/.test/vim3/linux-image-amlogic-mainline_1.4.2_arm64.deb
sudo dpkg -i  linux-dtb-amlogic-mainline_1.4.2_arm64.deb linux-image-amlogic-mainline_1.4.2_arm64.deb
sync
sudo reboot
