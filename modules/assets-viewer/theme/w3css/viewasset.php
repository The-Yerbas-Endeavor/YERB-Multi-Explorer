<section class="hero compact-hero">
  <div>
    <p class="eyebrow">Asset details</p>
    <h1><?php echo !empty($data['name']) ? htmlspecialchars($data['name'], ENT_QUOTES, 'UTF-8') : 'Asset'; ?></h1>
    <p>Supply, metadata, issuer information, and current holder balances for this Yerbas asset.</p>
  </div>
  <a class="status-pill" href="./">← Back to assets</a>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo htmlspecialchars($data['error'], ENT_QUOTES, 'UTF-8'); ?></div>
<?php else: ?>
<section class="detail-grid">
  <article class="stat-card detail-card">
    <span>Total supply</span>
    <strong><?php echo htmlspecialchars(number_format((float) $data['amount'], (int) $data['units'], '.', ','), ENT_QUOTES, 'UTF-8'); ?></strong>
  </article>
  <article class="stat-card detail-card">
    <span>Decimal units</span>
    <strong><?php echo (int) $data['units']; ?></strong>
  </article>
  <article class="stat-card detail-card">
    <span>Holders</span>
    <strong><?php echo number_format((int) $data['nrAssetHolders']); ?></strong>
  </article>
</section>

<section class="panel" style="margin-bottom:14px">
  <div class="panel-head"><div><p class="panel-kicker">Registry record</p><h2>Asset information</h2></div></div>
  <dl class="info-list">
    <div class="info-row">
      <dt>Asset name</dt>
      <dd><?php echo htmlspecialchars($data['name'], ENT_QUOTES, 'UTF-8'); ?></dd>
    </div>
    <div class="info-row">
      <dt>Asset type</dt>
      <dd><span class="badge type-badge"><?php echo htmlspecialchars($data['type'], ENT_QUOTES, 'UTF-8'); ?></span></dd>
    </div>
    <div class="info-row">
      <dt>Reissuable</dt>
      <dd><span class="badge <?php echo !empty($data['reissuable']) ? 'green' : ''; ?>"><?php echo !empty($data['reissuable']) ? 'Yes' : 'No'; ?></span></dd>
    </div>
    <div class="info-row">
      <dt>Issuer</dt>
      <dd>
        <?php if (!empty($data['issuer']) && strpos($data['issuer'], 'Multiple') !== 0): ?>
          <a href="./?cmd=viewholder&amp;id=<?php echo rawurlencode($data['issuer']); ?>"><?php echo htmlspecialchars($data['issuer'], ENT_QUOTES, 'UTF-8'); ?></a>
        <?php elseif (!empty($data['issuer'])): ?>
          <?php echo htmlspecialchars($data['issuer'], ENT_QUOTES, 'UTF-8'); ?>
        <?php else: ?>
          <span class="badge">Unavailable</span>
        <?php endif; ?>
      </dd>
    </div>
    <div class="info-row">
      <dt>IPFS metadata</dt>
      <dd>
        <?php if (!empty($data['ipfs_hash'])): ?>
          <a href="https://ipfs.io/ipfs/<?php echo rawurlencode($data['ipfs_hash']); ?>" target="_blank" rel="noopener"><?php echo htmlspecialchars($data['ipfs_hash'], ENT_QUOTES, 'UTF-8'); ?> ↗</a>
        <?php else: ?>
          <span class="badge">No IPFS metadata</span>
        <?php endif; ?>
      </dd>
    </div>
  </dl>
</section>

<section class="panel">
  <div class="panel-head">
    <div><p class="panel-kicker">Distribution</p><h2>Asset holders</h2></div>
    <span><?php echo number_format((int) $data['nrAssetHolders']); ?> addresses</span>
  </div>
  <div class="table-wrap">
    <table class="asset-table">
      <thead><tr><th>Holder address</th><th>Balance</th></tr></thead>
      <tbody>
      <?php if (!empty($data['addresses'])): ?>
        <?php foreach ($data['addresses'] as $address => $balance): ?>
          <tr>
            <td><a class="asset-name mono-link" href="./?cmd=viewholder&amp;id=<?php echo rawurlencode($address); ?>"><?php echo htmlspecialchars($address, ENT_QUOTES, 'UTF-8'); ?></a></td>
            <td class="numeric"><?php echo htmlspecialchars(number_format((float) $balance, (int) $data['units'], '.', ','), ENT_QUOTES, 'UTF-8'); ?></td>
          </tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td colspan="2" class="empty-state">No holder balances were returned.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
</section>
<?php endif; ?>