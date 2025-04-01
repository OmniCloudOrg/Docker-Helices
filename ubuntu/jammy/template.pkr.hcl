packer {
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "~> 1"
    }
  }
}

variable "vm_name" {
  type    = string
  default = "ubuntu-base-live-iso"
}

variable "cpus" {
  type    = string
  default = "2"
}

variable "memory" {
  type    = string
  default = "4096"
}

variable "disk_size" {
  type    = string
  default = "40960"
}

variable "headless" {
  type    = bool
  default = true
}

variable "output_directory" {
  type    = string
  default = "output-virtualbox"
}

variable "shared_folder_host_path" {
  type    = string
  default = "./shared"
}

locals {
  iso_url      = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
  iso_checksum = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
  
  # Base autoinstall configuration embedded as heredoc
  user_data = <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: en_US
  keyboard:
    layout: us
  network:
    network:
      version: 2
      ethernets:
        enp0s3:
          dhcp4: true
  identity:
    hostname: ubuntu-server
    username: ubuntu
    # Password is 'ubuntu'
    password: "$6$rounds=4096$NFl9k7AwRX6UhF62$GV9a05.ytTkapUGvMwGsKFkxdbk3vO3nEd4cWsyPxNjjYFdTGHORdYYLmEYIJLPB7zI0rldfC4IiKvI/TLnDX."
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: direct
  packages:
    - openssh-server
    - sudo
    - curl
    - wget
    - vim
    - net-tools
    - docker.io
    - docker-compose
    - openssh-server
    # Tools needed for live ISO creation
    - squashfs-tools
    - xorriso
    - isolinux
    - syslinux-common
    - debootstrap
    - genisoimage
    - p7zip-full
  user-data:
    disable_root: false
  late-commands:
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
    - chmod 440 /target/etc/sudoers.d/ubuntu
    - "sed -i 's/^#*\\(PermitRootLogin\\).*/\\1 yes/' /target/etc/ssh/sshd_config"
    - "sed -i 's/^#*\\(PasswordAuthentication\\).*/\\1 yes/' /target/etc/ssh/sshd_config"
    # Enable Docker service
    - "systemctl enable docker.service"
    - "systemctl enable containerd.service"
    # Enable SSH server
    - "systemctl enable ssh.service"
    # Add ubuntu user to docker group
    - "usermod -aG docker ubuntu"
EOF
}

source "virtualbox-iso" "ubuntu" {
  guest_os_type    = "Ubuntu_64"
  vm_name          = var.vm_name
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  headless         = var.headless
  output_directory = var.output_directory
  
  iso_url          = local.iso_url
  iso_checksum     = local.iso_checksum
  
  ssh_username     = "ubuntu"
  ssh_password     = "ubuntu"
  ssh_timeout      = "30m"
  ssh_host_port_min = 2222
  ssh_host_port_max = 2222
  host_port_min    = 2222
  host_port_max    = 2222
  
  shutdown_command = "echo 'ubuntu' | sudo -S shutdown -P now"
  
  boot_command = [
    "<esc><wait>",
    "f2<wait>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud-net;seedfrom=http://{{.HTTPIP}}:{{.HTTPPort}}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter><wait>"
  ]
  
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--rtcuseutc", "on"],
    ["modifyvm", "{{.Name}}", "--graphicscontroller", "vmsvga"],
    ["modifyvm", "{{.Name}}", "--boot1", "dvd"],
    ["modifyvm", "{{.Name}}", "--boot2", "disk"],
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],
    ["modifyvm", "{{.Name}}", "--natpf1", "guestssh,tcp,,2222,,22"],
    ["sharedfolder", "add", "{{.Name}}", "--name=shared", "--hostpath=${var.shared_folder_host_path}", "--automount"]
  ]
  
  http_content = {
    "/user-data" = local.user_data
    "/meta-data" = ""
  }
}

build {
  sources = ["source.virtualbox-iso.ubuntu"]
  
  provisioner "shell" {
    inline = [
      "echo 'ubuntu' | sudo -S apt-get update",
      "echo 'ubuntu' | sudo -S apt-get upgrade -y",
      
      # Ensure Docker is installed and running
      "echo 'ubuntu' | sudo -S apt-get install -y docker.io docker-compose",
      "echo 'ubuntu' | sudo -S systemctl enable docker",
      "echo 'ubuntu' | sudo -S systemctl start docker",
      "echo 'ubuntu' | sudo -S usermod -aG docker ubuntu",
      
      # Ensure SSH server is installed and running
      "echo 'ubuntu' | sudo -S apt-get install -y openssh-server",
      "echo 'ubuntu' | sudo -S systemctl enable ssh",
      "echo 'ubuntu' | sudo -S systemctl start ssh",
      
      # Install tools for live ISO creation
      "echo 'ubuntu' | sudo -S apt-get install -y squashfs-tools xorriso isolinux syslinux-common debootstrap genisoimage p7zip-full",
      
      # Mount the shared folder for ISO creation
      "sudo mkdir -p /mnt/shared",
      "sudo mount -t vboxsf shared /mnt/shared",
      
      # Create a basic script for live ISO creation
      "cat << 'EOT' | sudo tee /home/ubuntu/create-live-iso.sh",
      "#!/bin/bash",
      "set -e",
      "",
      "# Destination for the live ISO",
      "LIVE_ISO_DIR='/mnt/shared/ubuntu-live-iso'",
      "ISO_NAME='ubuntu-custom-live.iso'",
      "",
      "# Create working directories",
      "mkdir -p $LIVE_ISO_DIR/extract",
      "mkdir -p $LIVE_ISO_DIR/custom",
      "mkdir -p $LIVE_ISO_DIR/new-iso",
      "",
      "# Mount the original ISO",
      "sudo mount -o loop /path/to/original/ubuntu-22.04.5-live-server-amd64.iso $LIVE_ISO_DIR/extract",
      "",
      "# Copy ISO contents",
      "rsync -av $LIVE_ISO_DIR/extract/ $LIVE_ISO_DIR/custom/",
      "",
      "# Optional: Customize the live ISO here",
      "# For example, add custom packages, scripts, etc.",
      "",
      "# Rebuild the ISO",
      "cd $LIVE_ISO_DIR/custom",
      "xorriso -as mkisofs -r -o $LIVE_ISO_DIR/$ISO_NAME -b isolinux/isolinux.bin -c isolinux/boot.cat \\",
      "  -no-emul-boot -boot-load-size 4 -boot-info-table \\",
      "  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \\",
      "  -eltorito-boot isolinux/isolinux.bin \\",
      "  -eltorito-catalog isolinux/boot.cat \\",
      "  -no-emul-boot -boot-load-size 4 -boot-info-table \\",
      "  -joliet -z -l .",
      "",
      "echo 'Live ISO created at $LIVE_ISO_DIR/$ISO_NAME'",
      "EOT",
      
      # Make the script executable
      "sudo chmod +x /home/ubuntu/create-live-iso.sh",
      
      "echo 'ubuntu' | sudo -S apt-get clean",
      "echo 'ubuntu' | sudo -S apt-get autoremove -y",
      
      # Clear logs and temporary files
      "sudo rm -f /var/log/audit/audit.log",
      "sudo truncate -s 0 /var/log/wtmp",
      "sudo truncate -s 0 /var/log/lastlog",
      
      # Remove SSH host keys (they will be regenerated on first boot)
      "sudo rm -f /etc/ssh/ssh_host_*",
      
      # Clear machine ID
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      
      # Clear shell history
      "sudo rm -f /root/.bash_history",
      "rm -f ~/.bash_history",
      
      # Clean temporary files
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*"
    ]
  }
}