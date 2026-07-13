<section class="hero compact-hero">
  <div>
    <p class="eyebrow">Holder address</p>
    <h1 class="address-title"><?php echo !empty($data['id']) ? htmlspecialchars($data['id'], ENT_QUOTES, 'UTF-8') : 'Address'; ?></h1>
    <p>Current Yerbas asset balances held by this address.</p>
  </div>
  <a class="status-pill" href="./">← Back to assets</a>
</section>

<?php if (!empty($data['error'])): ?>
  <div class="error-box"><?php echo htmlspecialchars($data['error'], ENT_QUOTES, 'UTF-8'); ?></div>
<?php else: ?>
<section class="stats-grid two">
  <article class="stat-card">
    <span class="stat-label">Distinct assets</span>
    <strong class="stat-value"><?php echo number_format((int) $data['assetCount']); ?></strong>
  </article>
  <article class="stat-card">
    <span class="stat-label">Network</span>
    <strong class="stat-value network-value">YERB</strong>
  </article>
</section>

<section class="panel">
  <div class="panel-head">
    <div><p class="panel-kicker">Portfolio</p><h2>Asset balances</h2></div>
    <span><?php echo number_format((int) $data['assetCount']); ?> assets</span>
  </div>
  <div class="table-wrap">
    <table class="asset-table">
      <thead><tr><th>Asset</th><th>Balance</th></tr></thead>
      <tbody>
      <?php if (!empty($data['assets'])): ?>
        <?php foreach ($data['assets'] as $asset => $value): ?>
          <tr>
            <td>
              <a class="asset-name" href="./?cmd=viewasset&amp;id=<?php echo rawurlencode(base64_encode($asset)); ?>">
                <span class="asset-token-icon"><?php echo htmlspecialchars(substr($asset, 0, 1), ENT_QUOTES, 'UTF-8'); ?></span>
                <span><?php echo htmlspecialchars($asset, ENT_QUOTES, 'UTF-8'); ?></span>
              </a>
            </td>
            <td class="numeric"><?php echo htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8'); ?></td>
          </tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td colspan="2" class="empty-state">No asset balances were returned for this address.</td></tr>
      <?php endif; ?>
      </tbody>
    </table>
  </div>
</section>
<?php endif; ?>