# Various ansible playbooks for different tasks

## Prerequisites
- Server installed with Debian 12.
- Ansible and sshpass installed on your local machine

## Initial setup
```sh
apt update && apt install curl -y

curl -o initial_setup.sh https://raw.githubusercontent.com/ameistad/devops/refs/heads/main/initial_setup.sh
chmod +x initial_setup.sh
./initial_setup.sh

```


## Run playbooks first time
```sh
ansible-playbook <playbook>.yml --limit <server-name> --ask-pass --ask-become-pass
```

## Ghostty support
```bash
infocmp -x | ssh YOUR-SERVER -- tic -x -
```
