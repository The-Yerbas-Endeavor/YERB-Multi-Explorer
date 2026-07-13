<section class="hero">
  <div>
    <p class="eyebrow">Yerbas blockchain</p>
    <h1>Asset Explorer</h1>
    <p>Search assets and addresses, inspect issuance details, and explore holder balances across the Yerbas network.</p>
  </div>
  <div class="status-stack">
    <div class="status-pill"><span class="status-dot"></span><?php echo !empty($data['cacheEnabled']) ? 'SQLite index online' : 'Live RPC mode'; ?></div>
    <?php if (!empty($data['cacheUpdatedAt'])): ?>
      <small class="freshness">Updated <?php echo htmlspecialchars(date('M j, Y H:i:s', (int) $data['cacheUpdatedAt']), ENT_QUOTES, 'UTF-8'); ?> UTC</small>
    <?php endif; ?>
  </div>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo htmlspecialchars($data['error'], ENT_QUOTES, 'UTF-8'); ?></div>
<?php endif; ?>

<section class="panel search-hero" aria-label="Explorer search">
  <form action="./?cmd=search" method="post" class="global-search">
    <span class="search-icon" aria-hidden="true">⌕</span>
    <input class="search-input" id="assetSearch" name="q" type="search" value="<?php echo htmlspecialchars(isset($data['searchQuery']) ? $data['searchQuery'] : '', ENT_QUOTES, 'UTF-8'); ?>" placeholder="Search exact asset name or Yerbas address" autocomplete="off" aria-label="Search exact asset name or address">
    <button class="search-button" type="submit">Open</button>
  </form>
  <?php if (!empty($data['cacheEnabled'])): ?>
    <form action="./" method="get" class="browse-search">
      <input class="search-input" name="q" type="search" value="<?php echo htmlspecialchars(isset($data['searchQuery']) ? $data['searchQuery'] : '', ENT_QUOTES, 'UTF-8'); ?>" placeholder="Filter indexed assets by partial name" aria-label="Filter indexed assets">
      <select name="type" class="filter-select" aria-label="Asset type">
        <option value="">All types</option>
        <?php foreach (array('Main','Sub-asset','Unique','Owner','Restricted','Qualifier') as $assetType): ?>
          <option value="<?php echo htmlspecialchars($assetType, ENT_QUOTES, 'UTF-8'); ?>"<?php echo isset($data['selectedType']) && $data['selectedType'] === $assetType ? ' selected' : ''; ?>><?php echo htmlspecialchars($assetType, ENT_QUOTES, 'UTF-8'); ?></option>
        <?php endforeach; ?>
      </select>
      <button class="secondary-button" type="submit">Filter</button>
    </form>
  <?php endif; ?>
</section>

<section class="stats-grid four" aria-label="Asset statistics">
  <article class="stat-card">
    <span class="stat-label">Registered assets</span>
    <strong class="stat-value"><?php echo number_format((int) $data['nrAssets']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Current block</span>
    <strong class="stat-value"><?php echo $data['blockHeight'] === null ? '—' : number_format((int) $data['blockHeight']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">IPFS assets</span>
    <strong class="stat-value"><?php echo number_format((int) $data['ipfsEnabled']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Reissuable assets</span>
    <strong class="stat-value"><?php echo number_format((int) $data['reissuableAssets']); ?></strong>
  </article>
</section>

<section class="filter-row" aria-label="Filter assets by first character">
  <div class="alphabet">
    <a href="./"<?php echo !isset($_GET['f']) ? ' class="active"' : ''; ?>>All</a>
    <?php
      $alphabet = array('0..9','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z');
      foreach ($alphabet as $letter):
        $active = isset($_GET['f']) && $_GET['f'] === $letter;
    ?>
      <a href="./?f=<?php echo urlencode($letter); ?>"<?php echo $active ? ' class="active"' : ''; ?>><?php echo htmlspecialchars($letter, ENT_QUOTES, 'UTF-8'); ?></a>
    <?php endforeach; ?>
  </div>
</section>

<section class="panel">
  <div class="panel-head">
    <div><p class="panel-kicker"><?php echo !empty($data['cacheEnabled']) ? 'Indexed registry' : 'Live on-chain registry'; ?></p><h2>Assets</h2></div>
    <span>Showing <?php echo number_format((int) $data['resultStart']); ?>–<?php echo number_format((int) $data['resultEnd']); ?> of <?php echo number_format((int) (isset($data['filteredAssets']) ? $data['filteredAssets'] : $data['nrAssets'])); ?></span>
  </div>
  <div class="table-wrap">
    <table class="asset-table rich-table">
      <thead>
        <tr>
          <th>Asset</th>
          <th>Type</th>
          <th>Supply</th>
          <th>Units</th>
          <th>Holders</th>
          <th>Reissuable</th>
          <th>Metadata</th>
        </tr>
      </thead>
      <tbody>
      <?php if (!empty($data['assetsList'])): ?>
        <?php foreach ($data['assetsList'] as $asset): ?>
          <tr data-asset-row data-asset-name="<?php echo htmlspecialchars(strtolower($asset['rawName']), ENT_QUOTES, 'UTF-8'); ?>">
            <td>
              <a class="asset-name" href="./?cmd=viewasset&amp;id=<?php echo rawurlencode($asset['id']); ?>">
                <span class="asset-token-icon"><?php echo htmlspecialchars(substr($asset['rawName'], 0, 1), ENT_QUOTES, 'UTF-8'); ?></span>
                <span><?php echo htmlspecialchars($asset['name'], ENT_QUOTES, 'UTF-8'); ?></span>
              </a>
            </td>
            <td><span class="badge type-badge"><?php echo htmlspecialchars($asset['type'], ENT_QUOTES, 'UTF-8'); ?></span></td>
            <td class="numeric"><?php echo $asset['amount'] === null ? '—' : htmlspecialchars(number_format((float) $asset['amount'], (int) ($asset['units'] ?: 0), '.', ','), ENT_QUOTES, 'UTF-8'); ?></td>
            <td class="numeric"><?php echo $asset['units'] === null ? '—' : (int) $asset['units']; ?></td>
            <td class="numeric"><?php echo $asset['holderCount'] === null ? '—' : number_format((int) $asset['holderCount']); ?></td>
            <td><?php if ($asset['reissuable']): ?><span class="badge green">Yes</span><?php else: ?><span class="badge">No</span><?php endif; ?></td>
            <td><?php if ($asset['ipfs']): ?><span class="badge green">IPFS</span><?php else: ?><span class="badge">On-chain</span><?php endif; ?></td>
          </tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td colspan="7" class="empty-state">No assets matched this view.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>

  <?php if ((int) $data['totalPages'] > 1): ?>
    <?php
      $queryParts = array();
      if (isset($_GET['f'])) $queryParts['f'] = $_GET['f'];
      if (isset($_GET['q'])) $queryParts['q'] = $_GET['q'];
      if (isset($_GET['type'])) $queryParts['type'] = $_GET['type'];
      $currentPage = (int) $data['currentPage'];
      $totalPages = (int) $data['totalPages'];
      $windowStart = max(1, $currentPage - 2);
      $windowEnd = min($totalPages, $currentPage + 2);
      $pageUrl = function ($page) use ($queryParts) {
          $parts = $queryParts;
          $parts['page'] = $page;
          return './?' . htmlspecialchars(http_build_query($parts), ENT_QUOTES, 'UTF-8');
      };
    ?>
    <nav class="pagination" aria-label="Asset pages">
      <a class="page-link<?php echo $currentPage <= 1 ? ' disabled' : ''; ?>" href="<?php echo $pageUrl(max(1, $currentPage - 1)); ?>">Previous</a>
      <?php for ($page = $windowStart; $page <= $windowEnd; $page++): ?>
        <a class="page-link<?php echo $page === $currentPage ? ' active' : ''; ?>" href="<?php echo $pageUrl($page); ?>"><?php echo $page; ?></a>
      <?php endfor; ?>
      <a class="page-link<?php echo $currentPage >= $totalPages ? ' disabled' : ''; ?>" href="<?php echo $pageUrl(min($totalPages, $currentPage + 1)); ?>">Next</a>
    </nav>
  <?php endif; ?>
</section>
