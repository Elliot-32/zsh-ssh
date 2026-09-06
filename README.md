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

Native grouped completion (including fzf-tab) always includes plain hostnames from `~/.ssh/known_hosts` in a separate `Known Hosts` group. No opt-in setting is needed.

The standalone fzf interface uses a combined list and excludes known hosts by default. To include them in that interface, enable:

```shell
export ZSH_SSH_INCLUDE_KNOWN_HOSTS=1
```

By default, the plugin reads `$HOME/.ssh/known_hosts`. To use another file:

```shell
export ZSH_SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
```

Hashed `known_hosts` entries cannot be converted back to hostnames and are skipped.

### fzf-tab integration

zsh-ssh registers an SSH completion function with Zsh's completion system (`compdef`). [fzf-tab](https://github.com/Aloxaf/fzf-tab) can capture its host sources as native completion groups and display them in its own interface.

The groups are:

- `SSH Config` for aliases parsed from the SSH config and its `Include` files.
- `Known Hosts` for plain hostnames parsed from `known_hosts`.

fzf-tab needs a non-empty description format to recognize and display groups. If you already have an equivalent format configured, keep it. `menu no` is recommended so Zsh's own completion menu does not interfere with fzf-tab. Changing the group-switching keys is optional; fzf-tab defaults to `F1` and `F2`.

```shell
# Required for fzf-tab group support; an existing equivalent format also works.
zstyle ':completion:*:descriptions' format '[%d]'
# Recommended for fzf-tab completion handling.
zstyle ':completion:*' menu no
# Optional: use < and > instead of the default F1 and F2.
zstyle ':fzf-tab:*' switch-group '<' '>'
```

zsh-ssh does not set these global styles itself. Without a description format, known hosts are still offered, but fzf-tab cannot distinguish the two groups.

The destination can include a login name or follow SSH options, for example:

```shell
ssh root@prod<Tab>
ssh -p 2222 prod<Tab>
ssh -vp2222 root@prod<Tab>
ssh -l deploy tag:work<Tab>
```

The login prefix and preceding options are preserved. `-F` selects an alternate SSH config, and `-F none` skips config aliases. Option values and remote command arguments use Zsh's standard SSH completion. Config entries show the hostname, configured user, tag and description; only the alias is inserted. Both groups use the same case-insensitive hostname matcher (for example, `p.w` matches `prod.web`). `tag:` filters only config entries and is replaced by the selected alias.

Initialize Zsh's completion system (`compinit`) and load both plugins before the first prompt. Either plugin order works: zsh-ssh defers its Tab binding until the first `precmd` hook and leaves the binding alone when fzf-tab is loaded. It does not disable or re-enable fzf-tab. If you later run `disable-fzf-tab`, SSH keeps ordinary grouped completion; `enable-fzf-tab` restores the fzf-tab interface.

Without fzf-tab loaded, zsh-ssh binds its standalone fzf interface at the first prompt. The examples above describe native completion through fzf-tab; the standalone interface retains its existing behavior.

To run the completion regression tests, use `zsh -f tests/completion.zsh`. Set `FZF_TAB_DIR` to a local fzf-tab checkout to also test both plugin orders and disabling/re-enabling fzf-tab. The tests use a pseudo-terminal and a deterministic selector, so no SSH connections are made.

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
