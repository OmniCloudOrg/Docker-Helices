mkdir C:\SharedFolder
.\packer.exe build -var "vm_name=ubuntu-jammy-%date:~10,4%%date:~4,2%%date:~7,2%" -var "headless=true" ubuntu/jammy/template-win.pkr.hcl