# Various ansible playbooks for different tasks


## Initial setup
```sh
wget https://raw.githubusercontent.com/ameistad/devops/refs/heads/main/initial_setup.sh -O initial_setup.sh
chmod +x initial_setup.sh
./initial_setup.sh
```


## Run playbooks
```sh
ansible-playbook -i hosts playbook.yml
```
