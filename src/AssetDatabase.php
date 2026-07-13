<?php

class AssetDatabase
{
    private $pdo;

    public function __construct($path)
    {
        $directory = dirname($path);
        if (!is_dir($directory) && !mkdir($directory, 0775, true) && !is_dir($directory)) {
            throw new RuntimeException('Unable to create storage directory: ' . $directory);
        }

        $this->pdo = new PDO('sqlite:' . $path, null, null, array(
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ));
        $this->pdo->exec('PRAGMA journal_mode=WAL');
        $this->pdo->exec('PRAGMA synchronous=NORMAL');
        $this->migrate();
    }

    private function migrate()
    {
        $this->pdo->exec(
            'CREATE TABLE IF NOT EXISTS assets (
                name TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                amount REAL,
                units INTEGER,
                reissuable INTEGER NOT NULL DEFAULT 0,
                has_ipfs INTEGER NOT NULL DEFAULT 0,
                ipfs_hash TEXT,
                holder_count INTEGER,
                updated_at INTEGER NOT NULL
            )'
        );
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_assets_type ON assets(type)');
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_assets_updated_at ON assets(updated_at DESC)');
        $this->pdo->exec(
            'CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )'
        );
    }

    public function upsertAsset(array $asset)
    {
        $statement = $this->pdo->prepare(
            'INSERT INTO assets (name, type, amount, units, reissuable, has_ipfs, ipfs_hash, holder_count, updated_at)
             VALUES (:name, :type, :amount, :units, :reissuable, :has_ipfs, :ipfs_hash, :holder_count, :updated_at)
             ON CONFLICT(name) DO UPDATE SET
                type = excluded.type,
                amount = excluded.amount,
                units = excluded.units,
                reissuable = excluded.reissuable,
                has_ipfs = excluded.has_ipfs,
                ipfs_hash = excluded.ipfs_hash,
                holder_count = excluded.holder_count,
                updated_at = excluded.updated_at'
        );
        $statement->execute(array(
            ':name' => $asset['name'],
            ':type' => $asset['type'],
            ':amount' => $asset['amount'],
            ':units' => $asset['units'],
            ':reissuable' => $asset['reissuable'] ? 1 : 0,
            ':has_ipfs' => $asset['has_ipfs'] ? 1 : 0,
            ':ipfs_hash' => $asset['ipfs_hash'],
            ':holder_count' => $asset['holder_count'],
            ':updated_at' => time(),
        ));
    }

    public function removeMissing(array $assetNames)
    {
        $this->pdo->beginTransaction();
        try {
            $this->pdo->exec('CREATE TEMP TABLE current_assets (name TEXT PRIMARY KEY)');
            $insert = $this->pdo->prepare('INSERT OR IGNORE INTO current_assets(name) VALUES (?)');
            foreach ($assetNames as $name) {
                $insert->execute(array($name));
            }
            $this->pdo->exec('DELETE FROM assets WHERE name NOT IN (SELECT name FROM current_assets)');
            $this->pdo->exec('DROP TABLE current_assets');
            $this->pdo->commit();
        } catch (Exception $exception) {
            $this->pdo->rollBack();
            throw $exception;
        }
    }

    public function setState($key, $value)
    {
        $statement = $this->pdo->prepare(
            'INSERT INTO sync_state(key, value) VALUES(:key, :value)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value'
        );
        $statement->execute(array(':key' => $key, ':value' => (string) $value));
    }

    public function getState()
    {
        $rows = $this->pdo->query('SELECT key, value FROM sync_state')->fetchAll();
        $state = array();
        foreach ($rows as $row) {
            $state[$row['key']] = $row['value'];
        }
        return $state;
    }

    public function listAssets($query, $type, $page, $perPage)
    {
        $where = array();
        $params = array();
        if ($query !== '') {
            $where[] = 'name LIKE :query ESCAPE "\\"';
            $params[':query'] = '%' . str_replace(array('\\', '%', '_'), array('\\\\', '\\%', '\\_'), $query) . '%';
        }
        if ($type !== '') {
            $where[] = 'type = :type';
            $params[':type'] = $type;
        }
        $whereSql = $where ? ' WHERE ' . implode(' AND ', $where) : '';

        $count = $this->pdo->prepare('SELECT COUNT(*) FROM assets' . $whereSql);
        $count->execute($params);
        $total = (int) $count->fetchColumn();

        $offset = max(0, ($page - 1) * $perPage);
        $sql = 'SELECT name, type, amount, units, reissuable, has_ipfs, ipfs_hash, holder_count, updated_at
                FROM assets' . $whereSql . ' ORDER BY name COLLATE NOCASE ASC LIMIT :limit OFFSET :offset';
        $statement = $this->pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $statement->bindValue($key, $value, PDO::PARAM_STR);
        }
        $statement->bindValue(':limit', $perPage, PDO::PARAM_INT);
        $statement->bindValue(':offset', $offset, PDO::PARAM_INT);
        $statement->execute();

        return array('items' => $statement->fetchAll(), 'total' => $total);
    }

    public function findAsset($name)
    {
        $statement = $this->pdo->prepare('SELECT * FROM assets WHERE name = :name');
        $statement->execute(array(':name' => $name));
        $result = $statement->fetch();
        return $result ?: null;
    }

    public function stats()
    {
        return $this->pdo->query(
            'SELECT COUNT(*) AS total,
                    SUM(has_ipfs) AS ipfs,
                    SUM(reissuable) AS reissuable,
                    SUM(CASE WHEN type = "Unique" THEN 1 ELSE 0 END) AS unique_assets
             FROM assets'
        )->fetch();
    }
}
