#!/bin/bash

# 自动Git提交脚本 (支持嵌套仓库)
# 用法: ./git-commit.sh [提交信息]

WORKSPACE="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKSPACE"

# 嵌套仓库列表 (这些目录有独立的 .git)
NESTED_REPOS=("ysyxSoC")

# 获取提交信息
if [ -n "$1" ]; then
    COMMIT_MSG="$*"
else
    DATE=$(date "+%Y-%m-%d %H:%M")
    COMMIT_MSG="Update: $DATE"
    echo "使用默认提交信息: $COMMIT_MSG"
    echo "或输入自定义信息 (直接回车使用默认):"
    read -r USER_MSG
    if [ -n "$USER_MSG" ]; then
        COMMIT_MSG="$USER_MSG"
    fi
fi

# 检查是否有更改需要提交 (忽略子模块)
has_changes() {
    local dir="$1"
    cd "$dir"
    # 检查跟踪文件的修改
    if ! git diff --quiet --ignore-submodules 2>/dev/null; then
        return 0
    fi
    # 检查暂存区的修改
    if ! git diff --cached --quiet --ignore-submodules 2>/dev/null; then
        return 0
    fi
    # 检查未跟踪的文件
    if [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
        return 0
    fi
    return 1
}

# 处理嵌套仓库
for repo in "${NESTED_REPOS[@]}"; do
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        echo ""
        echo "=== 处理嵌套仓库: $repo ==="
        
        if has_changes "$WORKSPACE/$repo"; then
            cd "$WORKSPACE/$repo"
            git status --short --ignore-submodules
            git add -A
            if git commit -m "$COMMIT_MSG"; then
                echo "$repo: 已提交"
            else
                echo "$repo: 提交失败"
            fi
        else
            echo "$repo: 没有需要提交的更改"
        fi
        cd "$WORKSPACE"
    fi
done

# 处理主仓库
echo ""
echo "=== 处理主仓库 ==="

if has_changes "$WORKSPACE"; then
    cd "$WORKSPACE"
    git status --short --ignore-submodules
    git add -A
    if git commit -m "$COMMIT_MSG"; then
        echo "主仓库: 已提交"
    else
        echo "主仓库: 提交失败"
    fi
else
    echo "主仓库: 没有需要提交的更改"
fi

# 询问是否推送
echo ""
echo "是否推送所有仓库到远程? (y/N)"
read -r PUSH_CONFIRM
if [ "$PUSH_CONFIRM" = "y" ] || [ "$PUSH_CONFIRM" = "Y" ]; then
    # 推送嵌套仓库
    for repo in "${NESTED_REPOS[@]}"; do
        if [ -d "$WORKSPACE/$repo/.git" ]; then
            echo "推送 $repo..."
            cd "$WORKSPACE/$repo"
            git push 2>/dev/null || echo "$repo: 推送失败或无远程仓库"
            cd "$WORKSPACE"
        fi
    done
    # 推送主仓库
    echo "推送主仓库..."
    cd "$WORKSPACE"
    git push
    echo "推送完成!"
fi

echo ""
echo "=== 完成 ==="
cd "$WORKSPACE"
git log --oneline -1
