{% if page.comments && theme.gitalk.enable %}
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.css">
  <script src="https://cdn.jsdelivr.net/npm/gitalk@1/dist/gitalk.min.js"></script>
   <script type="text/javascript">
        var gitalk = new Gitalk({
          clientID: '{{ theme.gitalk.ClientID }}',
          clientSecret: '{{ theme.gitalk.ClientSecret }}',
          repo: '{{ theme.gitalk.repo }}',
          owner: '{{ theme.gitalk.owner}}',
          admin: ['{{ theme.gitalk.admin}}'],
          id: location.pathname,
          distractionFreeMode: '{{ theme.gitalk.distractionFreeMode }}'
        })
        gitalk.render('gitalk-container')
       </script>
{% endif %}
