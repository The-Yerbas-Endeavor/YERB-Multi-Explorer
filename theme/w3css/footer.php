    </div>
  </main>

  <footer class="site-footer">
    <div class="container footer-inner">
      <div>
        <strong>Yerbas Asset Explorer</strong>
        <p>Blockchain data is provided directly by a Yerbas node.</p>
      </div>
      <div class="footer-links">
        <a href="https://yerbas.org/" target="_blank" rel="noopener">Website</a>
        <a href="https://explorer.yerbas.org/" target="_blank" rel="noopener">Block Explorer</a>
        <a href="https://github.com/The-Yerbas-Endeavor/Yerbas-Assets-Viewer" target="_blank" rel="noopener">Source</a>
      </div>
    </div>
  </footer>

  <script>
    (function () {
      var root = document.documentElement;
      var button = document.getElementById('themeToggle');
      var savedTheme = localStorage.getItem('yerbas-theme');

      if (savedTheme === 'dark' || (!savedTheme && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        root.setAttribute('data-theme', 'dark');
      }

      if (button) {
        button.addEventListener('click', function () {
          var isDark = root.getAttribute('data-theme') === 'dark';
          if (isDark) {
            root.removeAttribute('data-theme');
            localStorage.setItem('yerbas-theme', 'light');
          } else {
            root.setAttribute('data-theme', 'dark');
            localStorage.setItem('yerbas-theme', 'dark');
          }
        });
      }

      var search = document.getElementById('assetSearch');
      if (search) {
        search.addEventListener('input', function () {
          var query = search.value.toLowerCase().trim();
          document.querySelectorAll('[data-asset-row]').forEach(function (row) {
            var name = row.getAttribute('data-asset-name') || '';
            row.hidden = query !== '' && name.indexOf(query) === -1;
          });
        });
      }
    }());
  </script>
</body>
</html>
