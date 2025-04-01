mkdir -Force shared
.\packer.exe build -var "vm_name=ubuntu-jammy-$(Get-Date -Format 'yyyyMMdd')" -var "headless=true" ubuntu/jammy/template.pkr.hcl