# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANT_BOX      = ENV.fetch("REDMINE_BOX", "mw-ubuntu-24.04")
VAGRANT_SSH_USER = ENV.fetch("REDMINE_SSH_USER", "ubuntu")
VM_NAME          = "redmine-ansible"
VM_MEMORY        = Integer(ENV.fetch("REDMINE_MEMORY", "4096"))
VM_CPUS          = Integer(ENV.fetch("REDMINE_CPUS", "4"))
HOST_SSH_PORT    = Integer(ENV.fetch("REDMINE_SSH_PORT", "2222"))
HOST_HTTP_PORT   = Integer(ENV.fetch("REDMINE_HTTP_PORT", "8080"))

Vagrant.configure("2") do |config|
  config.vm.box = VAGRANT_BOX
  config.vm.hostname = "redmine"
  config.ssh.username = VAGRANT_SSH_USER
  config.ssh.insert_key = false

  config.vm.network "forwarded_port",
    guest: 22,
    host: HOST_SSH_PORT,
    host_ip: "127.0.0.1",
    id: "ssh"

  config.vm.network "forwarded_port",
    guest: 80,
    host: HOST_HTTP_PORT,
    host_ip: "127.0.0.1",
    id: "http"

  config.vm.provider "virtualbox" do |vb|
    vb.name = VM_NAME
    vb.memory = VM_MEMORY
    vb.cpus = VM_CPUS
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
  end

  config.vm.provision "ansible_local" do |ansible|
    ansible.playbook = "playbooks/site.yml"
    ansible.inventory_path = "inventory/hosts.yml"
    ansible.limit = "all"
    ansible.become = true
    ansible.become_user = "root"
    ansible.galaxy_role_file = "requirements.yml"
    ansible.galaxy_command = "ansible-galaxy collection install --requirements-file=%{role_file}"
  end
end
