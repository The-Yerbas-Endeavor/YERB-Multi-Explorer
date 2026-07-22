<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import axios from 'axios';
import { io, type Socket } from 'socket.io-client';
import {
  Activity, Boxes, Box, ChartNoAxesCombined, CircleDollarSign, Coins, Database,
  Gauge, Globe2, HardDrive, Network, Search, Server, ShieldCheck, Timer,
  TrendingUp, Users, WalletCards, Zap
} from 'lucide-vue-next';

type Block = { height: number; hash: string; time: string; txCount: number; difficulty?: number; size?: number };
type Transaction = { txid: string; blockHeight: number; time: string; valueOut?: number; fees?: number };
type AssetEvent = { asset: string; type: string; amount?: number; txid: string; blockHeight: number };
type RichEntry = { address: string; balance: number };
type Dashboard = {
  latestBlocks: Block[];
  latestTransactions: Transaction[];
  assetCount: number;
  assetEvents: AssetEvent[];
  richList: RichEntry[];
  sync?: { height?: number; status?: string };
};
type CoinData = {
  identity: { name: string; ticker: string; type: string; algorithm: string; consensus: string; maxSupply: number; targetBlockTimeSeconds: number; assetLayer: boolean };
  chain: { height: number | null; difficulty: number | null; networkHashrate: number | null; verificationProgress: number | null; chainSize: number | null; tipTime: string | null };
  supply: { circulating: number | null; max: number; percentMined: number | null; remaining: number | null; marketCap: number | null; fullyDilutedValue: number | null };
  market: null | { exchange: string; pair: string; price: number; bid?: number; ask?: number; high24h?: number; low24h?: number; volume24h?: number; updatedAt: string };
  network: { connections: number | null; inbound: number | null; outbound: number | null; protocolVersion: number | null; walletVersion: number | null; subversion: string | null; relayFee: number | null; peerCount: number | null; mempoolTransactions: number | null; mempoolBytes: number | null };
  smartnodes: { active: number | null; total: number | null; collateral: number | null; lockedSupply: number | null; roiAnnual: number | null };
  indexer: { indexedHeight: number; status: string; indexedBlocks: number; indexedTransactions: number; indexedAssets: number };
};

const data = ref<Dashboard>({ latestBlocks: [], latestTransactions: [], assetCount: 0, assetEvents: [], richList: [] });
const coin = ref<CoinData | null>(null);
const search = ref('');
const connected = ref(false);
const loading = ref(true);
let socket: Socket | undefined;

const chainHeight = computed(() => coin.value?.chain.height ?? null);
const syncPercent = computed(() => {
  if (chainHeight.value == null || data.value.sync?.height == null) return 0;
  return Math.min(100, Math.max(0, ((data.value.sync.height + 1) / (chainHeight.value + 1)) * 100));
});

function number(value: number | null | undefined, digits = 0) {
  if (value == null || Number.isNaN(value)) return '—';
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: digits }).format(value);
}
function compact(value: number | null | undefined) {
  if (value == null || Number.isNaN(value)) return '—';
  return new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 2 }).format(value);
}
function money(value: number | null | undefined) {
  if (value == null || Number.isNaN(value)) return '—';
  return new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: value < 1 ? 8 : 2 }).format(value);
}
function bytes(value: number | null | undefined) {
  if (value == null) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let current = value;
  let unit = 0;
  while (current >= 1024 && unit < units.length - 1) { current /= 1024; unit += 1; }
  return `${current.toFixed(unit > 1 ? 2 : 0)} ${units[unit]}`;
}
function hashrate(value: number | null | undefined) {
  if (value == null) return '—';
  const units = ['H/s', 'KH/s', 'MH/s', 'GH/s', 'TH/s'];
  let current = value;
  let unit = 0;
  while (current >= 1000 && unit < units.length - 1) { current /= 1000; unit += 1; }
  return `${current.toFixed(2)} ${units[unit]}`;
}
function ago(value: string | null | undefined) {
  if (!value) return '—';
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

async function refresh() {
  const [dashboard, coinResponse] = await Promise.all([
    axios.get<Dashboard>('/api/v1/dashboard'),
    axios.get<CoinData>('/api/v1/coin')
  ]);
  data.value = dashboard.data;
  coin.value = coinResponse.data;
  loading.value = false;
}

async function runSearch() {
  const q = search.value.trim();
  if (!q) return;
  const response = await axios.get('/api/v1/search', { params: { q } });
  const item = response.data.results?.[0];
  if (!item) return alert('No matching Yerbas block, transaction, address, or asset was found.');
  if (item.height != null) location.href = `/block/${item.height}`;
  else if (item.txid) location.href = `/tx/${item.txid}`;
  else if (item.address) location.href = `/address/${item.address}`;
  else if (item.name) location.href = `/asset/${encodeURIComponent(item.name)}`;
}

onMounted(async () => {
  await refresh();
  socket = io({ path: '/socket.io' });
  socket.on('connect', () => { connected.value = true; });
  socket.on('disconnect', () => { connected.value = false; });
  socket.on('explorer:event', async () => refresh());
});

onUnmounted(() => socket?.disconnect());
</script>

<template>
  <div class="app-shell">
    <header class="topbar">
      <div class="topbar-inner">
        <div class="brand">
          <div class="brand-mark">Y</div>
          <div><h1>YERB Explorer</h1><p>Yerbas network intelligence</p></div>
        </div>
        <nav class="desktop-nav">
          <a href="/">Overview</a><a href="/blocks">Blocks</a><a href="/transactions">Transactions</a><a href="/assets">Assets</a><a href="/smartnodes">Smartnodes</a><a href="/markets">Markets</a><a href="/richlist">Rich list</a><a href="/docs">API</a>
        </nav>
        <div class="live-pill"><span :class="connected ? 'live-dot online' : 'live-dot'"/>{{ connected ? 'Live' : 'Connecting' }}</div>
      </div>
    </header>

    <main class="page-wrap">
      <section class="hero-modern">
        <div class="hero-copy">
          <span class="eyebrow">Native Yerbas blockchain explorer</span>
          <h2>Everything happening on Yerbas, in one place.</h2>
          <p>Live blocks, transactions, assets, smartnodes, network health, supply, markets and holder distribution.</p>
          <form class="search-shell" @submit.prevent="runSearch">
            <Search class="search-icon"/>
            <input v-model="search" placeholder="Search block, hash, transaction, address or asset" />
            <button>Search</button>
          </form>
        </div>
        <div class="hero-network">
          <div class="network-orb"><Network/><span>{{ number(coin?.chain.height) }}</span><small>Current block</small></div>
          <div class="orbit orbit-one"></div><div class="orbit orbit-two"></div>
        </div>
      </section>

      <section class="metric-grid primary-metrics">
        <article class="metric-card"><div class="metric-icon"><CircleDollarSign/></div><div><span>YERB price</span><strong>{{ money(coin?.market?.price) }}</strong><small>{{ coin?.market ? `${coin.market.exchange} · ${coin.market.pair}` : 'Awaiting market feed' }}</small></div></article>
        <article class="metric-card"><div class="metric-icon"><TrendingUp/></div><div><span>Market cap</span><strong>{{ money(coin?.supply.marketCap) }}</strong><small>FDV {{ money(coin?.supply.fullyDilutedValue) }}</small></div></article>
        <article class="metric-card"><div class="metric-icon"><Coins/></div><div><span>Circulating supply</span><strong>{{ compact(coin?.supply.circulating) }} YERB</strong><small>{{ number(coin?.supply.percentMined, 2) }}% of max supply</small></div></article>
        <article class="metric-card"><div class="metric-icon"><Gauge/></div><div><span>Network hashrate</span><strong>{{ hashrate(coin?.chain.networkHashrate) }}</strong><small>Difficulty {{ number(coin?.chain.difficulty, 8) }}</small></div></article>
      </section>

      <section class="sync-strip">
        <div><span>Indexer synchronization</span><strong>{{ syncPercent.toFixed(2) }}%</strong></div>
        <div class="sync-track"><div :style="{ width: `${syncPercent}%` }"></div></div>
        <small>#{{ number(data.sync?.height) }} indexed of #{{ number(chainHeight) }}</small>
      </section>

      <section class="section-heading"><div><span class="eyebrow">Network overview</span><h3>Live chain health</h3></div><a href="/network">View network details →</a></section>
      <section class="metric-grid secondary-metrics">
        <article class="mini-card"><Timer/><span>Block time</span><strong>{{ coin?.identity.targetBlockTimeSeconds ?? 60 }} sec</strong></article>
        <article class="mini-card"><Activity/><span>Tip age</span><strong>{{ ago(coin?.chain.tipTime) }}</strong></article>
        <article class="mini-card"><Users/><span>Connected peers</span><strong>{{ number(coin?.network.peerCount) }}</strong></article>
        <article class="mini-card"><Database/><span>Mempool</span><strong>{{ number(coin?.network.mempoolTransactions) }} tx</strong></article>
        <article class="mini-card"><HardDrive/><span>Blockchain size</span><strong>{{ bytes(coin?.chain.chainSize) }}</strong></article>
        <article class="mini-card"><Boxes/><span>Yerbas assets</span><strong>{{ number(data.assetCount) }}</strong></article>
        <article class="mini-card"><Server/><span>Protocol</span><strong>{{ number(coin?.network.protocolVersion) }}</strong></article>
        <article class="mini-card"><ShieldCheck/><span>Verification</span><strong>{{ coin?.chain.verificationProgress != null ? `${(coin.chain.verificationProgress * 100).toFixed(3)}%` : '—' }}</strong></article>
      </section>

      <section class="content-grid">
        <article class="data-panel wide-panel">
          <div class="panel-head"><div><Box/><span>Latest blocks</span></div><a href="/blocks">View all</a></div>
          <div class="table-head"><span>Height</span><span>Transactions</span><span>Size</span><span>Age</span></div>
          <a v-for="block in data.latestBlocks" :key="block.hash" :href="`/block/${block.height}`" class="table-row four-col">
            <div><strong>#{{ block.height }}</strong><small>{{ block.hash.slice(0, 16) }}…</small></div><div>{{ number(block.txCount) }}</div><div>{{ bytes(block.size) }}</div><div>{{ ago(block.time) }}</div>
          </a>
          <div v-if="!loading && !data.latestBlocks.length" class="empty">Waiting for the block indexer.</div>
        </article>

        <article class="data-panel">
          <div class="panel-head"><div><Zap/><span>Smartnodes</span></div><a href="/smartnodes">Details</a></div>
          <div class="smartnode-hero"><strong>{{ number(coin?.smartnodes.active) }} / {{ number(coin?.smartnodes.total) }}</strong><span>active smartnodes</span></div>
          <div class="detail-list">
            <div><span>Required collateral</span><strong>{{ coin?.smartnodes.collateral ? `${number(coin.smartnodes.collateral)} YERB` : 'Pending live schedule' }}</strong></div>
            <div><span>Locked supply</span><strong>{{ coin?.smartnodes.lockedSupply ? `${compact(coin.smartnodes.lockedSupply)} YERB` : 'Pending index' }}</strong></div>
            <div><span>Annual ROI</span><strong>{{ coin?.smartnodes.roiAnnual ? `${number(coin.smartnodes.roiAnnual, 2)}%` : 'Pending reward data' }}</strong></div>
          </div>
        </article>
      </section>

      <section class="content-grid">
        <article class="data-panel">
          <div class="panel-head"><div><WalletCards/><span>Latest transactions</span></div><a href="/transactions">View all</a></div>
          <a v-for="tx in data.latestTransactions" :key="tx.txid" :href="`/tx/${tx.txid}`" class="list-row">
            <div><strong>{{ tx.txid.slice(0, 22) }}…</strong><small>Block #{{ tx.blockHeight }}</small></div><div class="align-right"><strong>{{ tx.valueOut != null ? `${number(tx.valueOut, 8)} YERB` : 'Transaction' }}</strong><small>{{ ago(tx.time) }}</small></div>
          </a>
          <div v-if="!loading && !data.latestTransactions.length" class="empty">No indexed transactions yet.</div>
        </article>

        <article class="data-panel">
          <div class="panel-head"><div><ChartNoAxesCombined/><span>Top holders</span></div><a href="/richlist">Rich list</a></div>
          <a v-for="(holder, index) in data.richList" :key="holder.address" :href="`/address/${holder.address}`" class="holder-row">
            <span class="rank">{{ index + 1 }}</span><div><strong>{{ holder.address.slice(0, 15) }}…{{ holder.address.slice(-7) }}</strong><small>{{ number(holder.balance, 8) }} YERB</small></div>
          </a>
          <div v-if="!loading && !data.richList.length" class="empty">Rich-list data will appear after address indexing.</div>
        </article>
      </section>

      <section class="data-panel asset-panel">
        <div class="panel-head"><div><Coins/><span>Recent asset activity</span></div><a href="/assets">Explore assets</a></div>
        <div class="asset-grid">
          <a v-for="event in data.assetEvents" :key="`${event.txid}:${event.asset}:${event.type}`" :href="`/asset/${encodeURIComponent(event.asset)}`" class="asset-card">
            <span class="asset-type">{{ event.type }}</span><strong>{{ event.asset }}</strong><small>Block #{{ event.blockHeight }}</small><b>{{ event.amount ?? '—' }}</b>
          </a>
        </div>
        <div v-if="!loading && !data.assetEvents.length" class="empty">No indexed asset activity yet.</div>
      </section>

      <section class="coin-specs">
        <div><span class="eyebrow">Coin specifications</span><h3>Built specifically for Yerbas</h3><p>A modern presentation of the important network, monetary and client details users expect from a full coin explorer.</p></div>
        <dl>
          <div><dt>Ticker</dt><dd>YERB</dd></div><div><dt>Consensus</dt><dd>{{ coin?.identity.consensus ?? 'PoW + smartnodes' }}</dd></div><div><dt>Algorithm</dt><dd>{{ coin?.identity.algorithm ?? 'GhostRider' }}</dd></div><div><dt>Block time</dt><dd>{{ coin?.identity.targetBlockTimeSeconds ?? 60 }} seconds</dd></div><div><dt>Maximum supply</dt><dd>{{ number(coin?.identity.maxSupply) }} YERB</dd></div><div><dt>Asset layer</dt><dd>{{ coin?.identity.assetLayer ? 'Native assets enabled' : 'Unavailable' }}</dd></div><div><dt>Client</dt><dd>{{ coin?.network.subversion ?? 'Pending RPC' }}</dd></div><div><dt>Relay fee</dt><dd>{{ coin?.network.relayFee != null ? `${coin.network.relayFee} YERB` : '—' }}</dd></div>
        </dl>
      </section>
    </main>
  </div>
</template>
