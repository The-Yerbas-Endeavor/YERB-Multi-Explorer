<section class="hero">
  <div>
    <p class="eyebrow">Yerbas blockchain</p>
    <h1>Asset Explorer</h1>
    <p>Search assets and addresses, inspect issuance details, and explore holder balances directly from the Yerbas network.</p>
  </div>
  <div class="status-pill"><span class="status-dot"></span> Yerbas RPC online</div>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo htmlspecialchars($data['error'], ENT_QUOTES, 'UTF-8'); ?></div>
<?php endif; ?>
<?php if (isset($_GET['search']) && $_GET['search'] === 'not-found'): ?>
  <div class="error-box">No exact asset or address match was found.</div>
<?php endif; ?>

<section class="panel search-hero" aria-label="Explorer search">
  <form action="./?cmd=search" method="post" class="global-search">
    <span class="search-icon" aria-hidden="true">⌕</span>
    <input class="search-input" id="assetSearch" name="q" type="search" placeholder="Search asset name or Yerbas address" autocomplete="off" aria-label="Search asset name or address">
    <button class="search-button" type="submit">Search</button>
  </form>
</section>

<section class="stats-grid four" aria-label="Asset statistics">
  <article class="stat-card">
    <span class="stat-label">Assets loaded</span>
    <strong class="stat-value"><?php echo number_format((int) $data['nrAssets']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">IPFS enabled</span>
    <strong class="stat-value"><?php echo number_format((int) $data['ipfsEnabled']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Reissuable</span>
    <strong class="stat-value"><?php echo number_format((int) $data['reissuableAssets']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Network</span>
    <strong class="stat-value network-value">YERB</strong>
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
    <div><p class="panel-kicker">On-chain registry</p><h2>Assets</h2></div>
    <span><?php echo number_format((int) $data['nrAssets']); ?> results</span>
  </div>
  <div class="table-wrap">
    <table class="asset-table rich-table">
      <thead>
        <tr>
          <th>Asset</th>
          <th>Type</th>
          <th>Supply</th>
          <th>Units</th>
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
            <td><?php if ($asset['reissuable']): ?><span class="badge green">Yes</span><?php else: ?><span class="badge">No</span><?php endif; ?></td>
            <td><?php if ($asset['ipfs']): ?><span class="badge green">IPFS</span><?php else: ?><span class="badge">On-chain</span><?php endif; ?></td>
          </tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td colspan="6" class="empty-state">No assets were returned by the Yerbas node.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
</section>