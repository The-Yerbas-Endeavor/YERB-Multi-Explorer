<?php
class yerbAssetsViewer
{
    private $cfg;
    private $command;
    private $database;

    public function __construct()
    {
        require 'config.php';
        $this->cfg = $cfg;
        $this->database = $this->loadDatabase();

        $validCommands = array('viewholder', 'viewasset', 'listassets', 'search');
        $requested = isset($_GET['cmd']) ? $_GET['cmd'] : 'listassets';
        $this->command = in_array($requested, $validCommands, true) ? $requested : 'listassets';
    }

    public function run()
    {
        $command = $this->command;
        $data = $this->$command();
        $data['title'] = 'Yerbas Asset Explorer';

        include 'theme/' . $this->cfg['theme'] . '/header.php';
        include 'theme/' . $this->cfg['theme'] . '/' . $this->command . '.php';
        include 'theme/' . $this->cfg['theme'] . '/footer.php';
    }

    private function loadDatabase()
    {
        if (!extension_loaded('pdo_sqlite')) {
            return null;
        }

        $path = isset($this->cfg['databasePath'])
            ? $this->cfg['databasePath']
            : __DIR__ . '/storage/assets.sqlite';

        if (!is_file($path)) {
            return null;
        }

        try {
            require_once __DIR__ . '/src/AssetDatabase.php';
            $database = new AssetDatabase($path);
            return $database->isReady() ? $database : null;
        } catch (Exception $exception) {
            error_log('Asset cache unavailable: ' . $exception->getMessage());
            return null;
        }
    }

    private function listassets()
    {
        include 'profanityFilter.php';

        if ($this->database) {
            return $this->listAssetsFromCache();
        }

        return $this->listAssetsFromRpc();
    }

    private function listAssetsFromCache()
    {
        include_once 'profanityFilter.php';
        $pageSize = isset($this->cfg['assetsPerPage']) ? max(10, min(200, (int) $this->cfg['assetsPerPage'])) : 50;
        $currentPage = isset($_GET['page']) ? max(1, (int) $_GET['page']) : 1;
        $prefix = !empty($_GET['f']) ? strtoupper((string) $_GET['f']) : '';
        $query = isset($_GET['q']) ? trim((string) $_GET['q']) : '';
        $type = isset($_GET['type']) ? trim((string) $_GET['type']) : '';

        $result = $this->database->listAssets($query, $type, $currentPage, $pageSize, $prefix);
        $totalAssets = (int) $result['total'];
        $totalPages = max(1, (int) ceil($totalAssets / $pageSize));
        $currentPage = min($currentPage, $totalPages);

        if ($currentPage > 1 && $currentPage > $totalPages) {
            $currentPage = $totalPages;
            $result = $this->database->listAssets($query, $type, $currentPage, $pageSize, $prefix);
        }

        $stats = $this->database->stats();
        $state = $this->database->getState();
        $offset = ($currentPage - 1) * $pageSize;
        $assets = array();

        foreach ($result['items'] as $row) {
            $assets[] = array(
                'id' => base64_encode($row['name']),
                'name' => profanityFilter($row['name']),
                'rawName' => $row['name'],
                'amount' => $row['amount'],
                'units' => $row['units'] === null ? null : (int) $row['units'],
                'reissuable' => !empty($row['reissuable']),
                'ipfs' => !empty($row['has_ipfs']),
                'type' => $row['type'],
                'holderCount' => $row['holder_count'] === null ? null : (int) $row['holder_count'],
            );
        }

        return array(
            'nrAssets' => (int) $stats['total'],
            'filteredAssets' => $totalAssets,
            'ipfsEnabled' => (int) $stats['ipfs'],
            'reissuableAssets' => (int) $stats['reissuable'],
            'assetsList' => $assets,
            'blockHeight' => isset($state['block_height']) ? (int) $state['block_height'] : null,
            'currentPage' => $currentPage,
            'totalPages' => $totalPages,
            'pageSize' => $pageSize,
            'resultStart' => $totalAssets === 0 ? 0 : $offset + 1,
            'resultEnd' => min($offset + $pageSize, $totalAssets),
            'cacheEnabled' => true,
            'cacheUpdatedAt' => isset($state['last_sync_at']) ? (int) $state['last_sync_at'] : null,
            'cacheAge' => isset($state['last_sync_at']) ? max(0, time() - (int) $state['last_sync_at']) : null,
            'searchQuery' => $query,
            'selectedType' => $type,
        );
    }

    private function listAssetsFromRpc()
    {
        include_once 'profanityFilter.php';
        $results = array();

        if (!empty($_GET['f'])) {
            if ($_GET['f'] === '0..9') {
                for ($i = 0; $i < 10; $i++) {
                    $batch = $this->getRPCresults('listassets', $i . '*');
                    if (is_array($batch)) {
                        $results = array_merge($results, $batch);
                    }
                }
            } else {
                $filter = strtoupper(substr((string) $_GET['f'], 0, 1)) . '*';
                $results = $this->getRPCresults('listassets', $filter);
            }
        } else {
            $results = $this->getRPCresults('listassets');
        }

        if (!is_array($results)) {
            return array(
                'error' => 'Unable to retrieve assets from the Yerbas node.',
                'nrAssets' => 0,
                'filteredAssets' => 0,
                'ipfsEnabled' => 0,
                'reissuableAssets' => 0,
                'assetsList' => array(),
                'blockHeight' => null,
                'currentPage' => 1,
                'totalPages' => 1,
                'pageSize' => 50,
                'cacheEnabled' => false,
            );
        }

        sort($results, SORT_NATURAL | SORT_FLAG_CASE);
        $totalAssets = count($results);
        $pageSize = isset($this->cfg['assetsPerPage']) ? max(10, min(200, (int) $this->cfg['assetsPerPage'])) : 50;
        $totalPages = max(1, (int) ceil($totalAssets / $pageSize));
        $currentPage = isset($_GET['page']) ? max(1, (int) $_GET['page']) : 1;
        $currentPage = min($currentPage, $totalPages);
        $offset = ($currentPage - 1) * $pageSize;
        $pageResults = array_slice($results, $offset, $pageSize);
        $blockHeight = $this->getRPCresults('getblockcount');

        $data = array(
            'nrAssets' => $totalAssets,
            'filteredAssets' => $totalAssets,
            'ipfsEnabled' => 0,
            'reissuableAssets' => 0,
            'assetsList' => array(),
            'blockHeight' => is_numeric($blockHeight) ? (int) $blockHeight : null,
            'currentPage' => $currentPage,
            'totalPages' => $totalPages,
            'pageSize' => $pageSize,
            'resultStart' => $totalAssets === 0 ? 0 : $offset + 1,
            'resultEnd' => min($offset + $pageSize, $totalAssets),
            'cacheEnabled' => false,
        );

        foreach ($pageResults as $id) {
            $metadata = $this->getRPCresults('getassetdata', $id);
            if (!is_array($metadata)) {
                $metadata = array();
            }

            $hasIpfs = !empty($metadata['has_ipfs']);
            $reissuable = !empty($metadata['reissuable']);
            if ($hasIpfs) {
                $data['ipfsEnabled']++;
            }
            if ($reissuable) {
                $data['reissuableAssets']++;
            }

            $data['assetsList'][] = array(
                'id' => base64_encode($id),
                'name' => profanityFilter($id),
                'rawName' => $id,
                'amount' => isset($metadata['amount']) ? $metadata['amount'] : null,
                'units' => isset($metadata['units']) ? (int) $metadata['units'] : null,
                'reissuable' => $reissuable,
                'ipfs' => $hasIpfs,
                'type' => $this->inferAssetType($id),
                'holderCount' => null,
            );
        }

        return $data;
    }

    private function viewasset()
    {
        $encodedId = isset($_GET['id']) ? (string) $_GET['id'] : '';
        $id = base64_decode($encodedId, true);
        if ($id === false || $id === '') {
            return array('error' => 'Invalid asset identifier.');
        }

        $cached = $this->database ? $this->database->findAsset($id) : null;
        $result = $cached ?: $this->getRPCresults('getassetdata', $id);
        if (!is_array($result)) {
            return array('error' => 'Unable to retrieve this asset.');
        }

        $data = array(
            'name' => isset($result['name']) ? $result['name'] : $id,
            'amount' => isset($result['amount']) ? $result['amount'] : 0,
            'units' => isset($result['units']) ? (int) $result['units'] : 0,
            'reissuable' => !empty($result['reissuable']),
            'ipfs_hash' => !empty($result['ipfs_hash']) ? $result['ipfs_hash'] : false,
            'type' => isset($result['type']) ? $result['type'] : $this->inferAssetType($id),
            'issuer' => '',
            'addresses' => array(),
            'nrAssetHolders' => isset($result['holder_count']) ? (int) $result['holder_count'] : 0,
            'cacheEnabled' => (bool) $cached,
        );

        $issuerResults = $this->getRPCresults('listaddressesbyasset', $id . '!');
        if (is_array($issuerResults) && count($issuerResults) === 1) {
            $data['issuer'] = key($issuerResults);
        } elseif (is_array($issuerResults) && count($issuerResults) > 1) {
            $data['issuer'] = 'Multiple issuer addresses detected';
        }

        $holders = $this->getRPCresults('listaddressesbyasset', $id);
        if (is_array($holders)) {
            arsort($holders, SORT_NUMERIC);
            $data['addresses'] = $holders;
            $data['nrAssetHolders'] = count($holders);
        }

        return $data;
    }

    private function viewholder()
    {
        $id = isset($_GET['id']) ? trim((string) $_GET['id']) : '';
        if ($id === '') {
            return array('error' => 'Invalid holder address.');
        }

        $result = $this->getRPCresults('listassetbalancesbyaddress', $id);
        if (!is_array($result)) {
            return array('error' => 'Unable to retrieve balances for this address.');
        }

        arsort($result, SORT_NUMERIC);
        return array(
            'id' => $id,
            'assets' => $result,
            'assetCount' => count($result),
        );
    }

    private function search()
    {
        $query = isset($_POST['q']) ? trim((string) $_POST['q']) : '';
        if ($query === '') {
            header('Location: ./');
            exit;
        }

        if ($this->database && $this->database->findAsset($query)) {
            header('Location: ./?cmd=viewasset&id=' . rawurlencode(base64_encode($query)));
            exit;
        }

        if (is_array($this->getRPCresults('getassetdata', $query))) {
            header('Location: ./?cmd=viewasset&id=' . rawurlencode(base64_encode($query)));
            exit;
        }

        if (is_array($this->getRPCresults('listassetbalancesbyaddress', $query))) {
            header('Location: ./?cmd=viewholder&id=' . rawurlencode($query));
            exit;
        }

        header('Location: ./?q=' . rawurlencode($query));
        exit;
    }

    private function inferAssetType($name)
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

    private function getRPCresults($command, $param = '')
    {
        require_once 'rpc.php';
        $yerb = new Yerbas(
            $this->cfg['rpcUsername'],
            $this->cfg['rpcPassword'],
            $this->cfg['rpcHostIP'],
            $this->cfg['rpcHostPort']
        );

        return $param === '' ? $yerb->$command() : $yerb->$command($param);
    }
}
?>
