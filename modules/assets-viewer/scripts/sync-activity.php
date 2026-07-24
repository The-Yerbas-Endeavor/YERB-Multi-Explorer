#!/usr/bin/env php
<?php

declare(strict_types=1);

$root = dirname(__DIR__);
require $root . '/config.php';
require_once $root . '/rpc.php';
require_once $root . '/src/AssetDatabase.php';
require_once $root . '/src/ActivityDatabase.php';

$databasePath = isset($cfg['databasePath']) ? $cfg['databasePath'] : $root . '/storage/assets.sqlite';
$activity = new ActivityDatabase($databasePath);
$assets = new AssetDatabase($databasePath);
$rpc = new Yerbas($cfg['rpcUsername'], $cfg['rpcPassword'], $cfg['rpcHostIP'], $cfg['rpcHostPort']);

$tip = $rpc->getblockcount();
if (!is_numeric($tip)) {
    fwrite(STDERR, 'Unable to read block height: ' . ($rpc->error ?: 'unknown RPC error') . "\n");
    exit(1);
}

$state = $assets->getState();
$initialDepth = isset($cfg['activityInitialBlocks']) ? max(1, min(10000, (int) $cfg['activityInitialBlocks'])) : 500;
$lastHeight = isset($state['activity_height']) ? (int) $state['activity_height'] : max(0, (int) $tip - $initialDepth);
$start = max(0, $lastHeight - 6);
$end = (int) $tip;

function classifyAssetOutput(array $script): ?string
{
    $type = strtolower((string) ($script['type'] ?? ''));
    if (strpos($type, 'new_asset') !== false || strpos($type, 'new asset') !== false) {
        return 'Issue';
    }
    if (strpos($type, 'reissue') !== false) {
        return 'Reissue';
    }
    if (strpos($type, 'transfer_asset') !== false || strpos($type, 'transfer asset') !== false) {
        return 'Transfer';
    }
    return isset($script['asset']) ? 'Transfer' : null;
}

for ($height = $start; $height <= $end; $height++) {
    $hash = $rpc->getblockhash($height);
    if (!is_string($hash) || $hash === '') {
        fwrite(STDERR, "Unable to resolve block {$height}: " . ($rpc->error ?: 'unknown error') . "\n");
        exit(1);
    }
    if ($activity->hasBlock($height, $hash)) {
        continue;
    }

    $block = $rpc->getblock($hash, 2);
    if (!is_array($block)) {
        fwrite(STDERR, "Unable to decode block {$height}: " . ($rpc->error ?: 'unknown error') . "\n");
        exit(1);
    }

    $events = array();
    foreach (($block['tx'] ?? array()) as $tx) {
        if (!is_array($tx)) {
            continue;
        }
        $txid = (string) ($tx['txid'] ?? '');
        foreach (($tx['vout'] ?? array()) as $vout) {
            $script = isset($vout['scriptPubKey']) && is_array($vout['scriptPubKey']) ? $vout['scriptPubKey'] : array();
            $asset = isset($script['asset']) && is_array($script['asset']) ? $script['asset'] : null;
            if (!$asset || empty($asset['name'])) {
                continue;
            }
            $eventType = classifyAssetOutput($script);
            if ($eventType === null) {
                continue;
            }
            $voutNumber = isset($vout['n']) ? (int) $vout['n'] : 0;
            $addresses = isset($script['addresses']) && is_array($script['addresses']) ? $script['addresses'] : array();
            $events[] = array(
                ':event_key' => $txid . ':' . $voutNumber . ':' . $asset['name'],
                ':txid' => $txid,
                ':vout' => $voutNumber,
                ':block_height' => $height,
                ':block_hash' => $hash,
                ':block_time' => (int) ($block['time'] ?? time()),
                ':event_type' => $eventType,
                ':asset_name' => (string) $asset['name'],
                ':amount' => isset($asset['amount']) ? (float) $asset['amount'] : null,
                ':units' => isset($asset['units']) ? (int) $asset['units'] : null,
                ':reissuable' => array_key_exists('reissuable', $asset) ? (!empty($asset['reissuable']) ? 1 : 0) : null,
                ':ipfs_hash' => isset($asset['ipfs_hash']) ? (string) $asset['ipfs_hash'] : null,
                ':address' => isset($addresses[0]) ? (string) $addresses[0] : null,
                ':created_at' => time(),
            );
        }
    }

    $activity->replaceBlock($height, $hash, (int) ($block['time'] ?? time()), count($block['tx'] ?? array()), $events);
    $assets->setState('activity_height', $height);
    $assets->setState('activity_hash', $hash);
    $assets->setState('activity_sync_at', time());
    if ($height % 25 === 0 || $height === $end) {
        fwrite(STDOUT, "Activity indexed through block {$height}; " . count($events) . " asset events in block\n");
    }
}

exit(0);
