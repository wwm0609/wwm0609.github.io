#!/bin/bash

echo 'updating apt cache'
apt update

# install
npm install hexo --save


# 可以在markdown里使用图片
npm install hexo-asset-image --save

# 安装gittalk作为评论系统
npm i --save gitalk

npm install hexo-deployer-git --save

echo "all set, you can run 'hexo g && hexo s' to preview your pages"
