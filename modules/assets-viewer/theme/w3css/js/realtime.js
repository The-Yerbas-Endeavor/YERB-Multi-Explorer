(function () {
  'use strict';

  var rows = document.getElementById('activityRows');
  if (!rows) return;

  var cursor = 0;
  var initialized = false;
  var timer = null;
  var interval = 10000;

  function esc(value) {
    return String(value == null ? '' : value).replace(/[&<>'"]/g, function (char) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char];
    });
  }

  function relativeTime(timestamp) {
    var seconds = Math.max(0, Math.floor(Date.now() / 1000 - Number(timestamp || 0)));
    if (seconds < 10) return 'just now';
    if (seconds < 60) return seconds + 's ago';
    if (seconds < 3600) return Math.floor(seconds / 60) + 'm ago';
    if (seconds < 86400) return Math.floor(seconds / 3600) + 'h ago';
    return Math.floor(seconds / 86400) + 'd ago';
  }

  function assetUrl(name) {
    return './?cmd=viewasset&id=' + encodeURIComponent(btoa(unescape(encodeURIComponent(name))));
  }

  function renderRow(item, isNew) {
    var txUrl = 'https://explorer.yerbas.org/tx/' + encodeURIComponent(item.txid);
    var rowClass = isNew ? ' class="activity-new"' : '';
    return '<tr data-event-id="' + Number(item.id || 0) + '"' + rowClass + '>' +
      '<td data-time="' + Number(item.block_time || 0) + '">' + esc(relativeTime(item.block_time)) + '</td>' +
      '<td><span class="badge event-' + esc(String(item.event_type || '').toLowerCase()) + '">' + esc(item.event_type) + '</span></td>' +
      '<td><a class="asset-name" href="' + assetUrl(item.asset_name) + '">' + esc(item.asset_name) + '</a></td>' +
      '<td class="numeric">' + esc(item.amount == null ? '—' : Number(item.amount).toLocaleString()) + '</td>' +
      '<td class="numeric">' + esc(Number(item.block_height || 0).toLocaleString()) + '</td>' +
      '<td><a class="mono-link" target="_blank" rel="noopener" href="' + txUrl + '">' + esc(String(item.txid || '').slice(0, 12)) + '…</a></td>' +
      '</tr>';
  }

  function setText(id, value) {
    var element = document.getElementById(id);
    if (element) element.textContent = value;
  }

  function updateTimes() {
    document.querySelectorAll('[data-time]').forEach(function (cell) {
      cell.textContent = relativeTime(cell.getAttribute('data-time'));
    });
  }

  function updateDashboard(data) {
    var assets = data.assets || {};
    var activity = data.activity || {};
    var sync = data.sync || {};
    var block = data.latest_block || {};

    setText('liveBlock', Number(block.height || sync.activity_height || sync.block_height || 0).toLocaleString());
    setText('liveUnique', Number(assets.unique_assets || 0).toLocaleString());
    setText('liveTransfers', Number(activity.transfers_today || 0).toLocaleString());
    setText('liveIssues', Number(activity.issues_today || 0).toLocaleString());
    setText('liveActiveAssets', Number(activity.active_assets_today || 0).toLocaleString());
    setText('liveSync', sync.activity_sync_at ? relativeTime(sync.activity_sync_at) : '—');
  }

  function applyEvents(events) {
    if (!events.length) return;

    if (!initialized) {
      rows.innerHTML = events.map(function (item) { return renderRow(item, false); }).join('');
      initialized = true;
      return;
    }

    events.slice().reverse().forEach(function (item) {
      if (rows.querySelector('[data-event-id="' + Number(item.id || 0) + '"]')) return;
      rows.insertAdjacentHTML('afterbegin', renderRow(item, true));
    });

    while (rows.children.length > 20) rows.removeChild(rows.lastElementChild);
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(poll, document.hidden ? 30000 : interval);
  }

  function poll() {
    var url = './api/?resource=pulse&limit=20&after_id=' + (initialized ? cursor : 0) + '&_=' + Date.now();
    fetch(url, {headers: {'Accept': 'application/json'}, cache: 'no-store'})
      .then(function (response) {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return response.json();
      })
      .then(function (payload) {
        var data = payload.data || {};
        updateDashboard(data);
        applyEvents(data.events || []);
        cursor = Math.max(cursor, Number(data.cursor || 0));
        setText('activityStatus', 'Live · ' + new Date().toLocaleTimeString());
        schedule();
      })
      .catch(function () {
        setText('activityStatus', 'Reconnecting…');
        timer = setTimeout(poll, 20000);
      });
  }

  document.addEventListener('visibilitychange', function () {
    if (!document.hidden) poll();
  });

  window.setInterval(updateTimes, 15000);
  poll();
}());
