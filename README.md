# K8s miscellaneous
Notes from miscellaneous Kubernetes learning experiences.

> NOTE: This is strictly WIP documentation from my personal experience, if you are following this, creating resources on public cloud, please be mindful of resource utilization and please clean up after testing to avoid unnecessary bills.

#### Useful shortcuts & tools

- [Kubernetes Cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
```bash
# setup autocomplete in bash into the current shell, bash-completion package should be installed first.
source <(kubectl completion bash)
# add autocomplete permanently to your bash shell.
echo "source <(kubectl completion bash)" >> ~/.bashrc
alias k=kubectl
complete -F __start_kubectl k
```

- K9s [installation guide](https://k9scli.io/topics/install/)

Mac
```bash
brew install derailed/k9s/k9s
```

Ubuntu/other Linux distributions
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" && \
brew install derailed/k9s/k9s
```

Windows (using `chocolatey`)
```
choco install k9s
```

### Navigation links

- [Gloo Edge on Azure Kubernetes Services](https://github.com/find-arka/k8s-misc/blob/main/API-Gateway/README.md)
