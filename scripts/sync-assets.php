#!/usr/bin/env php
<?php

declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/config.php';
require_once $root . '/rpc.php';
require_once $root . '/src/AssetDatabase.php';

if (!extension_loaded('pdo_sqlite')) {
    fwrite(STDERR, "The pdo_sqlite PHP extension is required.\n");
    exit(1);
}

$databasePath = isset($cfg['databasePath']) ? $cfg['databasePath'] : $root . '/storage/assets.sqlite';
$database = new AssetDatabase($databasePath);
$rpc = new Yerbas(
    $cfg['rpcUsername'],
    $cfg['rpcPassword'],
    $cfg['rpcHostIP'],
    $cfg['rpcHostPort']
);

function inferAssetType(string $name): string
{
    if (substr($name, -1) === '!') {
        return 'Owner';
    }
    if (strpos($name, '#') !== false && substr($name, 0, 1) !== '#') {
        return 'Unique';
    }
    if (substr($name, 0, 1) === '$') {
        return 'Restricted';
    }
    if (substr($name, 0, 1) === '#') {
        return 'Qualifier';
    }
    if (strpos($name, '/') !== false) {
        return 'Sub-asset';
    }
    return 'Main';
}

$assets = $rpc->listassets();
if (!is_array($assets)) {
    fwrite(STDERR, 'Unable to list assets: ' . ($rpc->error ?: 'unknown RPC error') . "\n");
    exit(1);
}

sort($assets, SORT_NATURAL | SORT_FLAG_CASE);
$total = count($assets);
$processed = 0;
$failed = 0;
$startedAt = time();

foreach ($assets as $name) {
    $metadata = $rpc->getassetdata($name);
    if (!is_array($metadata)) {
        $failed++;
        fwrite(STDERR, "Skipped {$name}: " . ($rpc->error ?: 'invalid metadata response') . "\n");
        continue;
    }

    $holders = $rpc->listaddressesbyasset($name);
    $database->upsertAsset(array(
        'name' => $name,
        'type' => inferAssetType($name),
        'amount' => isset($metadata['amount']) ? $metadata['amount'] : null,
        'units' => isset($metadata['units']) ? (int) $metadata['units'] : null,
        'reissuable' => !empty($metadata['reissuable']),
        'has_ipfs' => !empty($metadata['has_ipfs']),
        'ipfs_hash' => !empty($metadata['ipfs_hash']) ? $metadata['ipfs_hash'] : null,
        'holder_count' => is_array($holders) ? count($holders) : null,
    ));

    $processed++;
    if ($processed % 25 === 0 || $processed === $total) {
        fwrite(STDOUT, "Indexed {$processed}/{$total} assets\n");
    }
}

$database->removeMissing($assets);
$blockHeight = $rpc->getblockcount();
$database->setState('last_sync_at', time());
$database->setState('last_sync_duration', time() - $startedAt);
$database->setState('last_sync_total', $total);
$database->setState('last_sync_processed', $processed);
$database->setState('last_sync_failed', $failed);
if (is_numeric($blockHeight)) {
    $database->setState('block_height', (int) $blockHeight);
}

fwrite(STDOUT, "Sync complete: {$processed} indexed, {$failed} failed.\n");
exit($failed > 0 ? 2 : 0);
