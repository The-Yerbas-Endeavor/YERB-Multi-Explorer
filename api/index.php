<?php

$root = dirname(__DIR__);
require $root . '/config.php';
require_once $root . '/src/AssetDatabase.php';
require_once $root . '/src/ActivityDatabase.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=15, stale-while-revalidate=30');
header('X-Content-Type-Options: nosniff');
header('Access-Control-Allow-Origin: *');

function respond($payload, $status = 200)
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $databasePath = isset($cfg['databasePath']) ? $cfg['databasePath'] : $root . '/storage/assets.sqlite';
    if (!file_exists($databasePath)) {
        respond(array('error' => 'Explorer index has not been initialized.'), 503);
    }

    $database = new AssetDatabase($databasePath);
    $activity = new ActivityDatabase($databasePath);
    $resource = isset($_GET['resource']) ? trim((string) $_GET['resource']) : 'assets';

    if ($resource === 'status' || $resource === 'stats') {
        respond(array('data' => array(
            'assets' => $database->stats(),
            'activity' => $activity->networkStats(),
            'sync' => $database->getState(),
        )));
    }

    if ($resource === 'activity') {
        $limit = isset($_GET['limit']) ? (int) $_GET['limit'] : 25;
        $asset = isset($_GET['asset']) ? trim((string) $_GET['asset']) : '';
        $type = isset($_GET['type']) ? trim((string) $_GET['type']) : '';
        respond(array('data' => $activity->recent($limit, $asset, $type), 'meta' => array(
            'limit' => max(1, min(200, $limit)), 'asset' => $asset, 'type' => $type,
        )));
    }

    if ($resource === 'asset') {
        $name = isset($_GET['name']) ? trim((string) $_GET['name']) : '';
        if ($name === '') {
            respond(array('error' => 'Missing asset name.'), 400);
        }
        $asset = $database->findAsset($name);
        if (!$asset) {
            respond(array('error' => 'Asset not found.'), 404);
        }
        $asset['activity'] = $activity->recent(100, $asset['name']);
        respond(array('data' => $asset));
    }

    if ($resource === 'search') {
        $query = isset($_GET['q']) ? trim((string) $_GET['q']) : '';
        if ($query === '') {
            respond(array('data' => array(), 'meta' => array('query' => '')));
        }
        $result = $database->listAssets($query, '', 1, 20);
        respond(array('data' => array('assets' => $result['items']), 'meta' => array('query' => $query, 'total' => $result['total'])));
    }

    if ($resource !== 'assets') {
        respond(array('error' => 'Unknown API resource.'), 404);
    }

    $query = isset($_GET['q']) ? trim((string) $_GET['q']) : '';
    $type = isset($_GET['type']) ? trim((string) $_GET['type']) : '';
    $prefix = isset($_GET['prefix']) ? trim((string) $_GET['prefix']) : '';
    $page = max(1, isset($_GET['page']) ? (int) $_GET['page'] : 1);
    $perPage = max(1, min(200, isset($_GET['per_page']) ? (int) $_GET['per_page'] : 50));
    $result = $database->listAssets($query, $type, $page, $perPage, $prefix);

    respond(array('data' => $result['items'], 'meta' => array(
        'page' => $page,
        'per_page' => $perPage,
        'total' => $result['total'],
        'total_pages' => max(1, (int) ceil($result['total'] / $perPage)),
        'query' => $query,
        'type' => $type,
        'prefix' => $prefix,
    )));
} catch (Exception $exception) {
    error_log('Explorer API error: ' . $exception->getMessage());
    respond(array('error' => 'Internal API error.'), 500);
}
