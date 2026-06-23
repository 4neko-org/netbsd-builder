#!/bin/sh

set -exu

#https://it-notes.dragas.net/2024/09/10/make-your-own-readonly-device-with-netbsd/

setup_path() {
  PATH="/sbin:/usr/sbin:$PATH"
  export PATH
}

install_extra_packages() {
  pkgin -y install bash curl rsync sudo openssl git
  pkgin -y clean
}

setup_ld(){
  touch /etc/ld.so.conf
  echo "/usr/pkg/lib" >> /etc/ld.so.conf
}

setup_sudo() {
# ?todo don't allow $SECONDARY_USER user to perform priv ops.

  mkdir -p /usr/pkg/etc/sudoers.d
  cat <<EOF > "/usr/pkg/etc/sudoers.d/$SECONDARY_USER"
Defaults:$SECONDARY_USER !requiretty
$SECONDARY_USER ALL=(ALL:ALL) ALL
EOF

  chmod 440 "/usr/pkg/etc/sudoers.d/$SECONDARY_USER"
}

configure_boot_flags() {
  if [ -f /boot.cfg ]; then
    sed -i -E 's/timeout=.+/timeout=0/' /boot.cfg
  else
    echo 'timeout=0' >> /boot.cfg
  fi
  echo 'consdev=com0,115200' >> /boot.cfg
}

configure_pre_login_message(){
  sed '/(%h) (%t)/s/\\r\\n\\r\\n/ FREYABOOTREADY\\r\\n\\r\\n/' /etc/gettytab > /tmp/gettytab
  rm /etc/gettytab
  mv /tmp/gettytab /etc/gettytab
}

configure_ssh() {
  cp /etc/ssh/sshd_config /tmp/sshd_config
  sed '/^PermitRootLogin/s/ yes$/ no/' /tmp/sshd_config > /etc/ssh/sshd_config
  rm /tmp/sshd_config
  tee -a /etc/ssh/sshd_config <<EOF
AcceptEnv *
UseDNS no
EOF
}

configure_boot_scripts() {
  cat <<EOF >> /etc/rc.local
RESOURCES_MOUNT_PATH='/mnt/resources'

mount_resources_disk() {
  # get the last disk
  disk="/dev/\$(sysctl -n hw.disknames | grep -o 'ld1')"

  if [ -n "\$disk" ]; then
    mkdir -p "\$RESOURCES_MOUNT_PATH"
    mount_msdos "\$disk" "\$RESOURCES_MOUNT_PATH"
  fi
}

install_authorized_keys() {
  echo "install_authorized_keys"
  if [ -s "\$RESOURCES_MOUNT_PATH/KEYS" ]; then
    echo "disk exists install_authorized_keys"
    mkdir -p "/home/$SECONDARY_USER/.ssh"
    cp "\$RESOURCES_MOUNT_PATH/KEYS" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chown "$SECONDARY_USER" "/home/$SECONDARY_USER/.ssh/authorized_keys"
    chmod 600 "/home/$SECONDARY_USER/.ssh/authorized_keys"
  fi
}

mount_freya_disk() {
  disk="/dev/\$(sysctl -n hw.disknames | grep -o 'ld2')"

  if [ -n "\$disk" ]; then
    fdisk -f -i "\$disk"
    fdisk -f -a -0 "\$disk"
    newfs "\${disk}a"
    mount "\${disk}a" "/home/$SECONDARY_USER/storage"
    chown "freya:users" "/home/$SECONDARY_USER/storage"
  fi
}

mount_resources_disk
install_authorized_keys
mount_freya_disk
EOF
}

set_hostname() {
  echo 'hostname=runnervmg1sw1.local' >> /etc/rc.conf
}

setup_rust_rustup(){
  su $SECONDARY_USER -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" -
  
  su $SECONDARY_USER -c "PATH=\"\$HOME/.cargo/bin:\$PATH\" rustup toolchain install nightly"
  su $SECONDARY_USER -c "PATH=\"\$HOME/.cargo/bin:\$PATH\" rustup toolchain install beta"
}

setup_freya_home_directory() {
  local work_directory="/home/$SECONDARY_USER"
  local permissions="$SECONDARY_USER"

  mkdir "$work_directory/storage"
  chown "$permissions" "$work_directory/storage"

  mkdir "$work_directory/.ssh"
  chown "$SECONDARY_USER" "$work_directory/.ssh"

  cat <<EOF >> $work_directory/env.toml
# if system supports RUSTUP, then a path to the rustup binary dir
# should be set. It uses the same path to access cargo and switch 
# between channels.
[[envs]]
key = "FREYA_RUSTUP_DIR_PATH"
value = "\${HOMEDIR}/.cargo/bin"

[[envs]]
key = "OPENSSL_DIR"
value = "/usr/pkg"

[[envs]]
key = "OPENSSL_LIB_DIR"
value = "/usr/pkg/lib"

[[envs]]
key = "OPENSSL_INCLUDE_DIR"
value = "/usr/pkg/include"

[[envs]]
key = "PATH"
value = "\${HOMEDIR}/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/X11R7/bin:/usr/pkg/bin:/usr/pkg/sbin:/usr/games:/usr/local/bin:/usr/local/sbin"

# a default toolchain name. A value is a full toolchain name
# channel-arch-hw-os-abi
[[envs]]
key = "FREYA_DEFAULT_TOOLCHAIN"
value = "stable-x86_64-unknown-netbsd"
EOF

  chown "$permissions" "$work_directory/env.toml"
}

setup_freyashell() {
  su $SECONDARY_USER -c "

  PATH=\"\$HOME/.cargo/bin:\$PATH\"
  export OPENSSL_DIR=/usr/pkg
  export OPENSSL_LIB_DIR=/usr/pkg/lib
  export OPENSSL_INCLUDE_DIR=/usr/pkg/include
  
  cd /home/$SECONDARY_USER
  git clone --branch v0.1.0 https://codeberg.org/4neko/freyashell.git
  cd ./freyashell
  cargo build --release
  "

  mkdir -p /usr/local/bin
  cp /home/$SECONDARY_USER/freyashell/target/release/freyashell /usr/local/bin/freyashell

  rm -rf /home/$SECONDARY_USER/freyashell

  # set the shell
  echo "/usr/local/bin/freyashell" >> /etc/shells

  # set freya user to work with freyashell
  chsh -s /usr/local/bin/freyashell $SECONDARY_USER
}

disable_some_things(){
  echo -n "makemandb=NO" >> /etc/rc.local
  echo -n "run_makemandb=NO" >> /etc/daily.conf
  rm -f /var/db/man.db
}

prepare_image_of_var_dir(){
  #service postfix stop
  service syslogd stop
  service dhcpcd stop

  cd /
  tar -cvzf var-image.tar.gz var

  service syslogd start
  service dhcpcd start
}

creating_custom_startup(){
  cat <<EOF >> /etc/rc.d/mount_mfs_fs
#!/bin/sh
#
# mount_mfs_fs: mount memory file system for /var
# by roby, 23 jun 2003 - adapted by Stefano - 01 Sep 2024 - adapted for Freya

# PROVIDE: mount_mfs_fs
# REQUIRE: root

\$_rc_subr_loaded . /etc/rc.subr

name="mount_mfs_fs"
start_cmd="mount_mfs_fs_start"
stop_cmd=":"

mount_mfs_fs_start()
{
    # Check if the /var entry is present and uncommented in /etc/fstab
    if grep -q '^tmpfs[[:space:]]\+/var[[:space:]]\+tmpfs[[:space:]]\+rw,-m1777,-sram%25' /etc/fstab; then
        echo "Mounting memory file system: /var"

        # Mount the file system for /var
        mount /var

        # Extract the contents of the tar file into /var
        tar -xvzpf /var-image.tar.gz -C /

        echo "Mounting memory file systems: Done."
    else
        echo "The tmpfs entry for /var is not present or is commented out in /etc/fstab. Skipping mount and extraction."
    fi
    sleep 5
}

load_rc_config \$name
run_rc_command "\$1"
EOF

chmod a+rx /etc/rc.d/mount_mfs_fs

cp /etc/rc.d/mountcritlocal /tmp/mountcritlocal
sed '/#\ REQUIRE:\ /s/fsck/mount_mfs_fs/' /tmp/mountcritlocal > /etc/rc.d/mountcritlocal
rm /tmp/mountcritlocal

}

configure_fstab() {
  cp /etc/fstab /tmp/fstab
  sed '/\t\/\tffs\t/s/rw/ro/' /tmp/fstab > /etc/fstab
  echo "tmpfs /var tmpfs   rw,-m1777,-sram%25" >> /etc/fstab
  echo "tmpfs /home/$SECONDARY_USER/.ssh tmpfs rw,-m1777,-sram%5" >> /etc/fstab

  mkdir -p "/mnt/resources"
}

setup_path
install_extra_packages
setup_ld
setup_sudo
configure_boot_flags
configure_pre_login_message
configure_boot_scripts
configure_ssh
set_hostname
setup_rust_rustup
setup_freya_home_directory
setup_freyashell
disable_some_things
prepare_image_of_var_dir
creating_custom_startup
configure_fstab
