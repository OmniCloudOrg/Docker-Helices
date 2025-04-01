mkdir -p /SharedFolder
./packer build -var "vm_name=ubuntu-jammy-$(date +%Y%m%d)" -var "headless=true" ubuntu/jammy/template.pkr.hcl