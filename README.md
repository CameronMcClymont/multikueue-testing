# MultiKueue/Kind Setup with Remote Worker Cluster

This repository provides a complete, out-of-the-box setup for deploying
MultiKueue with a local manager cluster on macOS and a remote worker cluster
on Ubuntu. The clusters both use Kind (via Colima for the manager).

# Setup Steps

## 1. Remote Worker Cluster

- Set up your remote Linux worker
- Clone this repository to your remote worker
- Make sure it has Docker and Homebrew installed
- Run `export WORKER_IP=<public IP of your worker>`
- Run `cd remote && ./configure-worker.sh`

## 2. Local Manager Cluster

- Clone this repository where your manager will be
- Make sure it has Homebrew installed
- Run `cd manager && ./1a-setup-manager.sh`
- Paste the content of `remote-kubeconfig.yaml` from your clipboard to the `remote-kubeconfig.yaml` in the `manager` directory
- Run `export REMOTE_KUBECONFIG=remote-kubeconfig.yaml` or whatever kubeconfig you want to use for the remote cluster.
- Run `./1b-configure-manager.sh`
- Run `./2-configure-remote-multikueue.sh`
- Test your setup with `./3a-test-manager.sh` and `./3b-test-remote.sh`
