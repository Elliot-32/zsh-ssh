# zsh-ssh

Better host completion for ssh in Zsh.

[![asciicast](https://asciinema.org/a/381405.svg)](https://asciinema.org/a/381405)

- [zsh-ssh](#zsh-ssh)
    - [Installation](#installation)
        - [Zinit](#zinit)
        - [Antigen](#antigen)
        - [Oh My Zsh](#oh-my-zsh)
        - [Sheldon](#sheldon)
        - [Manual (Git Clone)](#manual-git-clone)
    - [Usage](#usage)
        - [Configuration](#configuration)
        - [fzf-tab integration](#fzf-tab-integration)
        - [SSH Config Example](#ssh-config-example)

## Installation

Make sure you have [fzf](https://github.com/junegunn/fzf) installed.
The `column` command is optional and only improves table/preview alignment; the plugin falls back to plain formatting when it is unavailable.

### Zinit

```shell
zinit light sunlei/zsh-ssh
```

### Antigen

```shell
antigen bundle sunlei/zsh-ssh
```

### Oh My Zsh

1. Clone this repository into `$ZSH_CUSTOM/plugins` (by default `~/.oh-my-zsh/custom/plugins`)

    ```shell
    git clone https://github.com/sunlei/zsh-ssh ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-ssh
    ```

2. Add the plugin to the list of plugins for Oh My Zsh to load (inside `~/.zshrc`):

    ```shell
    plugins=(zsh-ssh $plugins)
    ```

3. Start a new terminal session.

### Sheldon

1. Add this config to `~/.config/sheldon/plugins.toml`

    ```toml
    [plugins.zsh-ssh]
    github = 'sunlei/zsh-ssh'
    ```

2. Run `sheldon lock` to install the plugin.

3. Start a new terminal session.

### Manual (Git Clone)

1. Clone this repository somewhere on your machine. For example: `~/.zsh/zsh-ssh`.

    ```shell
    git clone https://github.com/sunlei/zsh-ssh ~/.zsh/zsh-ssh
    ```

2. Add the following to your `.zshrc`:

    ```shell
    source ~/.zsh/zsh-ssh/zsh-ssh.zsh
    ```

3. Start a new terminal session.

## Usage

Just press <kbd>Tab</kbd> after `ssh` command as usual.

### Configuration

Known hosts are not included by default. To include plain hostnames from `~/.ssh/known_hosts`, enable it explicitly:

```shell
export ZSH_SSH_INCLUDE_KNOWN_HOSTS=1
```

By default, the plugin reads `$HOME/.ssh/known_hosts`. To use another file:

```shell
export ZSH_SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
```

Hashed `known_hosts` entries cannot be converted back to hostnames and are skipped.

### fzf-tab integration

When [fzf-tab](https://github.com/Aloxaf/fzf-tab) is active, zsh-ssh detects fzf-tab's completion-capture context and exposes its host sources as native Zsh completion groups instead of opening a second standalone fzf instance.

With known hosts enabled, the groups are:

- `SSH Config` for aliases parsed from the SSH config and its `Include` files.
- `Known Hosts` for plain hostnames parsed from `known_hosts`.

For example, the standard fzf-tab group-switching configuration can use `<` and `>` to move between them:

```shell
export ZSH_SSH_INCLUDE_KNOWN_HOSTS=1

zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' menu no
zstyle ':fzf-tab:*' switch-group '<' '>'
```

Both plugin load orders are supported. If fzf-tab loads after zsh-ssh, it wraps zsh-ssh normally. If fzf-tab is already active when zsh-ssh loads, zsh-ssh temporarily unwraps it, installs its own Tab widget, and then re-enables fzf-tab so the resulting widget chain is the same. fzf-tab still needs Zsh's completion system (`compinit`) to be initialized first.

Without fzf-tab, zsh-ssh keeps its existing standalone fzf interface and behavior.

### SSH Config Example

You can use `#_Desc` to set description.

~/.ssh/config

```text
Host Bastion-Host
    Hostname 1.1.1.1
    User sunlei

Host Development-Host
    Hostname 2.2.2.2
    IdentityFile ~/.ssh/development-host
    #_Desc For Development
```

You can use OpenSSH `Tag` to group hosts in the list:

```text
Host Work-Bastion
    Hostname bastion.example.com
    User deploy
    Tag work
    #_Desc Bastion host

Host Home-NAS
    Hostname 192.168.1.20
    User root
    Tag personal
    #_Desc NAS
```

When any host has a `Tag`, zsh-ssh shows a `Tag` column. You can type `work`
in fzf to search for tagged hosts, or use `ssh tag:work<Tab>` to filter the
completion list by tag before fzf opens.

Include files are also supported. For example, your main config can include separate files:

~/.ssh/config

```text
Include ~/.ssh/config.d/company.ssh_config
Include ~/.ssh/config.d/home.ssh_config
Include ~/.ssh/config.d/work.ssh_config

# OR

Include ~/.ssh/config.d/*.ssh_config
```
