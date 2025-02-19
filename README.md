# TEMPLATES 
Most of the files are for bash/debian base

## neovim
- Install [vim-plug](https://github.com/junegunn/vim-plug)
```
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
```
- Require: git, curl, exuberant-ctags
- After copy to '~/.config/nvim/', open the init.vim file and run ":PlugInstall"
- To remove some plugin, delete or comment the line and run ":PlugClean"
