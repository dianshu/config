配置步骤：
1. 安装 zsh
2. 拉取插件
```
# 命令缩写自动扩展
# 这个插件会在 /tmp 目录下创建目录来存储命令别名，因此可能会存在权限问题
git clone --depth 1 https://github.com/olets/zsh-abbr ~/.zsh/plugins/zsh-abbr

# 自动补全
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/plugins/zsh-autosuggestions

# 语法高亮
git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting ~/.zsh/plugins/zsh-syntax-highlighting

# 基于命令匹配搜索相关的历史命令
git clone --depth 1 https://github.com/zsh-users/zsh-history-substring-search ~/.zsh/plugins/zsh-history-substring-search
```
3. 替换 ~/.zshrc
