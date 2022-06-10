# k8s-misc
Notes from miscellaneous K8s learning experiences

> NOTE: This is strictly WIP documentation from my personal experience, if you are following this, and creating resources on public cloud, please be mindful and clean up to avoid unnecessary bills.

#### Setup shortcuts

Thanks to [Kubernetes Cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
```bash
# setup autocomplete in bash into the current shell, bash-completion package should be installed first.
source <(kubectl completion bash)
# add autocomplete permanently to your bash shell.
echo "source <(kubectl completion bash)" >> ~/.bashrc
alias k=kubectl
complete -F __start_kubectl k
```

K9s installation (Purely Optional)
```bash
# for Mac -
brew install derailed/k9s/k9s

# For Ubuntu, other Linux distros - 
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew doctor
brew install derailed/k9s/k9s
```
