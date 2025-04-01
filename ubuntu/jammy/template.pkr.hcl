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
  default = "ubuntu-jammy-live"
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

variable "iso_output_directory" {
  type    = string
  default = "C:\\SharedFolder"
}

locals {
  iso_url      = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
  iso_checksum = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
  
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
    password: "$6$rounds=4096$NFl9k7AwRX6UhF62$GV9a05.ytTkapUGvMwGsKFkxdbk3vO3nEd4cWsyPxNjjYFdTGHORdYYLmEYIJLPB7zI0rldfC4IiKvI/TLnDX."
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: direct
  packages:
    - squashfs-tools
    - xorriso
    - live-boot
    - live-config
  user-data:
    disable_root: false
  late-commands:
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
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
    ["sharedfolder", "add", "{{.Name}}", "--name", "shared", "--hostpath", "${var.iso_output_directory}", "--automount"],
    ["modifyvm", "{{.Name}}", "--natpf1", "guestssh,tcp,,2222,,22"]
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
      
      # Install live ISO creation tools
      "echo 'ubuntu' | sudo -S apt-get install -y squashfs-tools xorriso live-boot live-config",
      
      # Mount shared folder
      "sudo mkdir -p /mnt/shared",
      "sudo mount -t vboxsf shared /mnt/shared",
      
      # Create live ISO creation script
      "cat << 'EOT' | sudo tee /home/ubuntu/create-live-iso.sh",
      "#!/bin/bash",
      "set -e",
      "",
      "# Live ISO creation directories",
      "LIVE_DIR='/home/ubuntu/live-iso'",
      "MOUNT_DIR=\"$LIVE_DIR/mnt\"",
      "SQUASHFS_DIR=\"$LIVE_DIR/squashfs\"",
      "ISO_DIR=\"$LIVE_DIR/iso\"",
      "OUTPUT_DIR='/mnt/shared'",
      "",
      "# Create necessary directories",
      "mkdir -p \"$MOUNT_DIR\" \"$SQUASHFS_DIR\" \"$ISO_DIR\"",
      "",
      "# Create live filesystem",
      "sudo mksquashfs / \"$SQUASHFS_DIR/filesystem.squashfs\" -e boot -e proc -e sys -e dev -e mnt -e tmp",
      "",
      "# Prepare ISO structure",
      "cp /boot/vmlinuz* \"$ISO_DIR/vmlinuz\"",
      "cp /boot/initrd.img* \"$ISO_DIR/initrd\"",
      "",
      "# Create ISO configuration",
      "cat << 'ISOLINUX' > \"$ISO_DIR/isolinux.cfg\"",
      "UI vesamenu.c32",
      "PROMPT 0",
      "TIMEOUT 50",
      "ONTIMEOUT live",
      "",
      "LABEL live",
      "  MENU LABEL ^Live System",
      "  KERNEL /vmlinuz",
      "  APPEND initrd=/initrd boot=live quiet splash",
      "",
      "LABEL live-failsafe",
      "  MENU LABEL ^Live System (Failsafe)",
      "  KERNEL /vmlinuz",
      "  APPEND initrd=/initrd boot=live quiet splash acpi=off noapic noreplace-paravirt",
      "ISOLINUX",
      "",
      "# Create ISO",
      "cd \"$LIVE_DIR\"",
      "xorriso -as mkisofs -r -J -joliet-long -l -cache-inodes \\",
      "  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \\",
      "  -partition_offset 16 \\",
      "  -A 'Ubuntu Live' \\",
      "  -p 'Packer Generated Live ISO' \\",
      "  -publisher 'Your Organization' \\",
      "  -V 'Ubuntu Live' \\",
      "  -b isolinux/isolinux.bin \\",
      "  -c isolinux/boot.cat \\",
      "  -no-emul-boot \\",
      "  -boot-load-size 4 \\",
      "  -boot-info-table \\",
      "  -o \"$OUTPUT_DIR/ubuntu-live.iso\" \\",
      "  \"$ISO_DIR\"",
      "",
      "echo 'Live ISO created at $OUTPUT_DIR/ubuntu-live.iso'",
      "EOT",
      
      # Make script executable and run
      "chmod +x /home/ubuntu/create-live-iso.sh",
      "sudo /home/ubuntu/create-live-iso.sh",
      
      # Cleanup
      "echo 'ubuntu' | sudo -S apt-get clean",
      "echo 'ubuntu' | sudo -S apt-get autoremove -y"
    ]
  }
}