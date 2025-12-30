#!/bin/bash

# 自动Git提交脚本
# 用法: ./git-commit.sh [提交信息]

set -e

cd "$(dirname "$0")"

# 检查是否有未提交的更改
if git diff --quiet && git diff --cached --quiet; then
    echo "没有需要提交的更改"
    exit 0
fi

# 显示当前状态
echo "=== Git 状态 ==="
git status --short

# 获取提交信息
if [ -n "$1" ]; then
    COMMIT_MSG="$*"
else
    # 生成默认提交信息：日期 + 简短描述
    DATE=$(date "+%Y-%m-%d %H:%M")
    COMMIT_MSG="Update: $DATE"
    echo ""
    echo "使用默认提交信息: $COMMIT_MSG"
    echo "或输入自定义信息 (直接回车使用默认):"
    read -r USER_MSG
    if [ -n "$USER_MSG" ]; then
        COMMIT_MSG="$USER_MSG"
    fi
fi

# 添加所有更改
echo ""
echo "=== 添加所有更改 ==="
git add -A
git status --short

# 提交
echo ""
echo "=== 提交 ==="
git commit -m "$COMMIT_MSG"

# 询问是否推送
echo ""
echo "是否推送到远程仓库? (y/N)"
read -r PUSH_CONFIRM
if [ "$PUSH_CONFIRM" = "y" ] || [ "$PUSH_CONFIRM" = "Y" ]; then
    echo "=== 推送 ==="
    git push
    echo "推送完成!"
fi

echo ""
echo "=== 完成 ==="
git log --oneline -1
