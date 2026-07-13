<section class="hero">
  <div>
    <p class="eyebrow">Yerbas blockchain</p>
    <h1>Explore Yerbas assets</h1>
    <p>Search issued assets, inspect metadata, and view holder balances directly from the Yerbas network.</p>
  </div>
  <div class="status-pill"><span class="status-dot"></span> Connected to Yerbas RPC</div>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo $data['error']; ?></div>
<?php endif; ?>

<section class="stats-grid" aria-label="Asset statistics">
  <article class="stat-card">
    <span class="stat-label">Total assets</span>
    <strong class="stat-value"><?php echo number_format((int)$data['nrAssets']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">IPFS enabled</span>
    <strong class="stat-value"><?php echo number_format((int)$data['ipfsEnabled']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Network</span>
    <strong class="stat-value">YERB</strong>
  </article>
</section>

<section class="panel toolbar" aria-label="Asset search and filters">
  <div class="search-wrap">
    <input class="search-input" id="assetSearch" type="search" placeholder="Search loaded assets…" autocomplete="off" aria-label="Search assets">
  </div>
  <div class="alphabet" aria-label="Filter assets by first character">
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
    <h2>Assets</h2>
    <span><?php echo number_format((int)$data['nrAssets']); ?> found</span>
  </div>
  <div class="table-wrap">
    <table class="asset-table">
      <thead>
        <tr>
          <th>Asset name</th>
          <th>Metadata</th>
          <th>Network</th>
        </tr>
      </thead>
      <tbody>
      <?php if (!empty($data['assetsList'])): ?>
        <?php foreach ($data['assetsList'] as $asset): ?>
          <tr data-asset-row data-asset-name="<?php echo htmlspecialchars(strtolower($asset['name']), ENT_QUOTES, 'UTF-8'); ?>">
            <td><a class="asset-name" href="./?cmd=viewasset&amp;id=<?php echo urlencode($asset['id']); ?>"><?php echo htmlspecialchars($asset['name'], ENT_QUOTES, 'UTF-8'); ?></a></td>
            <td><?php if ($asset['ipfs']): ?><span class="badge green">IPFS</span><?php else: ?><span class="badge">On-chain</span><?php endif; ?></td>
            <td><span class="badge">Yerbas</span></td>
          </tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td colspan="3" class="empty-state">No assets were returned by the Yerbas node.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
</section>
