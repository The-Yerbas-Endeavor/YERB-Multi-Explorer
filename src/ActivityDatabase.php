<?php

class ActivityDatabase
{
    private $pdo;

    public function __construct($path)
    {
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
        $this->pdo->exec('CREATE TABLE IF NOT EXISTS blocks (
            height INTEGER PRIMARY KEY,
            hash TEXT NOT NULL UNIQUE,
            block_time INTEGER NOT NULL,
            tx_count INTEGER NOT NULL DEFAULT 0,
            indexed_at INTEGER NOT NULL
        )');
        $this->pdo->exec('CREATE TABLE IF NOT EXISTS asset_activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_key TEXT NOT NULL UNIQUE,
            txid TEXT NOT NULL,
            vout INTEGER NOT NULL,
            block_height INTEGER NOT NULL,
            block_hash TEXT NOT NULL,
            block_time INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            asset_name TEXT NOT NULL,
            amount REAL,
            units INTEGER,
            reissuable INTEGER,
            ipfs_hash TEXT,
            address TEXT,
            created_at INTEGER NOT NULL
        )');
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_activity_time ON asset_activity(block_time DESC, id DESC)');
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_activity_asset ON asset_activity(asset_name COLLATE NOCASE, block_height DESC)');
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_activity_txid ON asset_activity(txid)');
        $this->pdo->exec('CREATE INDEX IF NOT EXISTS idx_activity_type ON asset_activity(event_type, block_height DESC)');
    }

    public function hasBlock($height, $hash)
    {
        $statement = $this->pdo->prepare('SELECT 1 FROM blocks WHERE height = :height AND hash = :hash');
        $statement->execute(array(':height' => $height, ':hash' => $hash));
        return (bool) $statement->fetchColumn();
    }

    public function replaceBlock($height, $hash, $time, $txCount, array $events)
    {
        $this->pdo->beginTransaction();
        try {
            $delete = $this->pdo->prepare('DELETE FROM asset_activity WHERE block_height = :height');
            $delete->execute(array(':height' => $height));
            $delete = $this->pdo->prepare('DELETE FROM blocks WHERE height = :height');
            $delete->execute(array(':height' => $height));

            $block = $this->pdo->prepare('INSERT INTO blocks(height, hash, block_time, tx_count, indexed_at) VALUES(?,?,?,?,?)');
            $block->execute(array($height, $hash, $time, $txCount, time()));

            $insert = $this->pdo->prepare('INSERT OR IGNORE INTO asset_activity
                (event_key, txid, vout, block_height, block_hash, block_time, event_type, asset_name, amount, units, reissuable, ipfs_hash, address, created_at)
                VALUES (:event_key,:txid,:vout,:block_height,:block_hash,:block_time,:event_type,:asset_name,:amount,:units,:reissuable,:ipfs_hash,:address,:created_at)');
            foreach ($events as $event) {
                $insert->execute($event);
            }
            $this->pdo->commit();
        } catch (Exception $exception) {
            if ($this->pdo->inTransaction()) {
                $this->pdo->rollBack();
            }
            throw $exception;
        }
    }

    public function recent($limit = 25, $asset = '', $type = '', $afterId = 0)
    {
        $where = array();
        $params = array();
        if ($asset !== '') {
            $where[] = 'asset_name = :asset COLLATE NOCASE';
            $params[':asset'] = $asset;
        }
        if ($type !== '') {
            $where[] = 'event_type = :type';
            $params[':type'] = $type;
        }
        if ((int) $afterId > 0) {
            $where[] = 'id > :after_id';
            $params[':after_id'] = (int) $afterId;
        }
        $sql = 'SELECT * FROM asset_activity' . ($where ? ' WHERE ' . implode(' AND ', $where) : '') . ' ORDER BY block_height DESC, id DESC LIMIT :limit';
        $statement = $this->pdo->prepare($sql);
        foreach ($params as $key => $value) {
            $statement->bindValue($key, $value, $key === ':after_id' ? PDO::PARAM_INT : PDO::PARAM_STR);
        }
        $statement->bindValue(':limit', max(1, min(200, (int) $limit)), PDO::PARAM_INT);
        $statement->execute();
        return $statement->fetchAll();
    }

    public function latestId()
    {
        return (int) $this->pdo->query('SELECT COALESCE(MAX(id), 0) FROM asset_activity')->fetchColumn();
    }

    public function latestBlock()
    {
        $row = $this->pdo->query('SELECT height, hash, block_time, tx_count, indexed_at FROM blocks ORDER BY height DESC LIMIT 1')->fetch();
        return $row ?: null;
    }

    public function networkStats()
    {
        $today = strtotime('today UTC');
        $statement = $this->pdo->prepare('SELECT
            COUNT(*) AS events_today,
            COALESCE(SUM(CASE WHEN event_type = "Issue" THEN 1 ELSE 0 END),0) AS issues_today,
            COALESCE(SUM(CASE WHEN event_type = "Transfer" THEN 1 ELSE 0 END),0) AS transfers_today,
            COALESCE(SUM(CASE WHEN event_type = "Reissue" THEN 1 ELSE 0 END),0) AS reissues_today,
            COUNT(DISTINCT asset_name) AS active_assets_today
            FROM asset_activity WHERE block_time >= :today');
        $statement->execute(array(':today' => $today));
        return $statement->fetch();
    }
}
