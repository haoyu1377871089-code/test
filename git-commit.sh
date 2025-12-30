#!/bin/bash

# 自动Git提交脚本 (支持嵌套仓库)
# 用法: ./git-commit.sh [提交信息]

set -e

WORKSPACE="$(dirname "$0")"
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

# 处理嵌套仓库
for repo in "${NESTED_REPOS[@]}"; do
    if [ -d "$WORKSPACE/$repo/.git" ]; then
        echo ""
        echo "=== 处理嵌套仓库: $repo ==="
        cd "$WORKSPACE/$repo"
        
        if git diff --quiet && git diff --cached --quiet; then
            echo "$repo: 没有需要提交的更改"
        else
            git status --short
            git add -A
            git commit -m "$COMMIT_MSG"
            echo "$repo: 已提交"
        fi
        cd "$WORKSPACE"
    fi
done

# 处理主仓库
echo ""
echo "=== 处理主仓库 ==="
cd "$WORKSPACE"

if git diff --quiet && git diff --cached --quiet; then
    echo "主仓库: 没有需要提交的更改"
else
    git status --short
    git add -A
    git commit -m "$COMMIT_MSG"
    echo "主仓库: 已提交"
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
    git push
    echo "推送完成!"
fi

echo ""
echo "=== 完成 ==="
git log --oneline -1
