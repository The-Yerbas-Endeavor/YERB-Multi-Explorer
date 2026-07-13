<section class="hero">
  <div>
    <p class="eyebrow">Asset details</p>
    <h1><?php echo htmlspecialchars($data['name'], ENT_QUOTES, 'UTF-8'); ?></h1>
    <p>Supply, metadata, issuer information, and current holder balances for this Yerbas asset.</p>
  </div>
  <a class="status-pill" href="./">← Back to assets</a>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo $data['error']; ?></div>
<?php else: ?>
<section class="detail-grid">
  <article class="stat-card detail-card">
    <span>Total supply</span>
    <strong><?php echo htmlspecialchars((string)$data['amount'], ENT_QUOTES, 'UTF-8'); ?></strong>
  </article>
  <article class="stat-card detail-card">
    <span>Decimal units</span>
    <strong><?php echo htmlspecialchars((string)$data['units'], ENT_QUOTES, 'UTF-8'); ?></strong>
  </article>
  <article class="stat-card detail-card">
    <span>Holders</span>
    <strong><?php echo number_format((int)$data['nrAssetHolders']); ?></strong>
  </article>
</section>

<section class="panel" style="margin-bottom:22px">
  <div class="panel-head"><h2>Asset information</h2></div>
  <dl class="info-list">
    <div class="info-row">
      <dt>Asset name</dt>
      <dd><?php echo htmlspecialchars($data['name'], ENT_QUOTES, 'UTF-8'); ?></dd>
    </div>
    <div class="info-row">
      <dt>Reissuable</dt>
      <dd><span class="badge <?php echo !empty($data['reissuable']) ? 'green' : ''; ?>"><?php echo !empty($data['reissuable']) ? 'Yes' : 'No'; ?></span></dd>
    </div>
    <div class="info-row">
      <dt>Issuer</dt>
      <dd><?php echo $data['issuer']; ?></dd>
    </div>
    <div class="info-row">
      <dt>IPFS metadata</dt>
      <dd>
        <?php if (!empty($data['ipfs_hash'])): ?>
          <a href="https://ipfs.io/ipfs/<?php echo rawurlencode($data['ipfs_hash']); ?>" target="_blank" rel="noopener"><?php echo htmlspecialchars($data['ipfs_hash'], ENT_QUOTES, 'UTF-8'); ?></a>
        <?php else: ?>
          <span class="badge">No IPFS metadata</span>
        <?php endif; ?>
      </dd>
    </div>
  </dl>
</section>

<section class="panel">
  <div class="panel-head">
    <h2>Asset holders</h2>
    <span><?php echo number_format((int)$data['nrAssetHolders']); ?> addresses</span>
  </div>
  <div class="table-wrap">
    <table class="asset-table">
      <thead><tr><th>Holder address</th><th>Balance</th></tr></thead>
      <tbody>
      <?php if (!empty($data['addresses'])): ?>
        <?php foreach ($data['addresses'] as $address => $balance): ?>
          <tr>
            <td><a class="asset-name" href="./?cmd=viewholder&amp;id=<?php echo urlencode($address); ?>"><?php echo htmlspecialchars($address, ENT_QUOTES, 'UTF-8'); ?></a></td>
            <td><?php echo htmlspecialchars((string)$balance, ENT_QUOTES, 'UTF-8'); ?></td>
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
