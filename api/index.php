<?php

$root = dirname(__DIR__);
require $root . '/config.php';
require_once $root . '/src/AssetDatabase.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: public, max-age=30');
header('X-Content-Type-Options: nosniff');

function respond($payload, $status = 200)
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

try {
    $databasePath = isset($cfg['databasePath']) ? $cfg['databasePath'] : $root . '/storage/assets.sqlite';
    if (!file_exists($databasePath)) {
        respond(array('error' => 'Asset index has not been initialized.'), 503);
    }

    $database = new AssetDatabase($databasePath);
    $resource = isset($_GET['resource']) ? trim((string) $_GET['resource']) : 'assets';

    if ($resource === 'status') {
        respond(array(
            'data' => array(
                'stats' => $database->stats(),
                'sync' => $database->getState(),
            ),
        ));
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
        respond(array('data' => $asset));
    }

    if ($resource !== 'assets') {
        respond(array('error' => 'Unknown API resource.'), 404);
    }

    $query = isset($_GET['q']) ? trim((string) $_GET['q']) : '';
    $type = isset($_GET['type']) ? trim((string) $_GET['type']) : '';
    $page = max(1, isset($_GET['page']) ? (int) $_GET['page'] : 1);
    $perPage = isset($_GET['per_page']) ? (int) $_GET['per_page'] : 50;
    $perPage = max(1, min(200, $perPage));

    $result = $database->listAssets($query, $type, $page, $perPage);
    $totalPages = max(1, (int) ceil($result['total'] / $perPage));

    respond(array(
        'data' => $result['items'],
        'meta' => array(
            'page' => $page,
            'per_page' => $perPage,
            'total' => $result['total'],
            'total_pages' => $totalPages,
            'query' => $query,
            'type' => $type,
        ),
    ));
} catch (Exception $exception) {
    error_log('Asset API error: ' . $exception->getMessage());
    respond(array('error' => 'Internal API error.'), 500);
}
