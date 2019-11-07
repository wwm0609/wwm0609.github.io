开发笔记

dev分支：用于存储和发布markdown，以及保存主题等配置文件 
master分支：用于github pages展示，即 wwm0609.github.io

workflow:
1. do `hexo new 'any-post'` to create a post
2. edit your new post under ./source/_posts/any-post.md
3. do `hexo g && hexo s -p [port]` to preview your new post
4. git commit -a -m 'msg'; git push origin dev to upload your changes to github
5. finally, do `hexo clean & hexo g & hexo d` to publish your new pages to github
6. visit http://wwm0609.github.com to check your posts
