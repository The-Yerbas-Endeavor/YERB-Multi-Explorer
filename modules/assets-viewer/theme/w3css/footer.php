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
      var initialTheme = savedTheme || 'dark';

      root.setAttribute('data-theme', initialTheme);

      if (button) {
        button.textContent = initialTheme === 'dark' ? '☀' : '☾';
        button.addEventListener('click', function () {
          var currentTheme = root.getAttribute('data-theme') || 'dark';
          var nextTheme = currentTheme === 'dark' ? 'light' : 'dark';
          root.setAttribute('data-theme', nextTheme);
          localStorage.setItem('yerbas-theme', nextTheme);
          button.textContent = nextTheme === 'dark' ? '☀' : '☾';
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
  <script src="./theme/w3css/js/realtime.js?v=3" defer></script>
</body>
</html>
