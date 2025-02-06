# Various ansible playbooks for different tasks


## Initial setup
```sh
curl -o initial_setup.sh https://raw.githubusercontent.com/ameistad/devops/refs/heads/main/initial_setup.sh
chmod +x initial_setup.sh
./initial_setup.sh

```


## Run playbooks first time
```sh
ansible-playbook <playbook>.yml --limit <server-name> --ask-pass --ask-become-pass
```
