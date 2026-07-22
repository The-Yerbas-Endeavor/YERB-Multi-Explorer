<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import axios from 'axios';
import { io, type Socket } from 'socket.io-client';
import { Activity, Box, Coins, Database, Search, Server, WalletCards } from 'lucide-vue-next';

type Block = { height: number; hash: string; time: string; txCount: number };
type Transaction = { txid: string; blockHeight: number; time: string };
type AssetEvent = { asset: string; type: string; amount?: number; txid: string; blockHeight: number };
type Dashboard = {
  latestBlocks: Block[];
  latestTransactions: Transaction[];
  assetCount: number;
  assetEvents: AssetEvent[];
  sync?: { height?: number; status?: string };
};

const data = ref<Dashboard>({ latestBlocks: [], latestTransactions: [], assetCount: 0, assetEvents: [] });
const chainHeight = ref<number | null>(null);
const search = ref('');
const connected = ref(false);
const loading = ref(true);
let socket: Socket | undefined;

const syncPercent = computed(() => {
  if (!chainHeight.value || data.value.sync?.height == null) return 0;
  return Math.min(100, Math.max(0, ((data.value.sync.height + 1) / (chainHeight.value + 1)) * 100));
});

async function refresh() {
  const [dashboard, health] = await Promise.all([
    axios.get<Dashboard>('/api/v1/dashboard'),
    axios.get('/api/v1/health')
  ]);
  data.value = dashboard.data;
  chainHeight.value = health.data.chainHeight;
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
  <div class="min-h-screen bg-[#07110b] text-slate-100">
    <header class="border-b border-emerald-950/80 bg-[#09170f]/95 backdrop-blur">
      <div class="mx-auto flex max-w-7xl items-center justify-between px-5 py-4">
        <div class="flex items-center gap-3">
          <div class="grid h-10 w-10 place-items-center rounded-xl bg-emerald-500 font-black text-[#07110b]">Y</div>
          <div><h1 class="font-semibold tracking-wide">YERB Multi-Explorer</h1><p class="text-xs text-emerald-400">Yerbas network intelligence</p></div>
        </div>
        <nav class="hidden gap-6 text-sm text-slate-300 md:flex">
          <a href="/">Dashboard</a><a href="/blocks">Blocks</a><a href="/transactions">Transactions</a><a href="/assets">Assets</a><a href="/smartnodes">Smartnodes</a><a href="/markets">Markets</a><a href="/docs">API</a>
        </nav>
        <div class="flex items-center gap-2 text-xs"><span class="h-2 w-2 rounded-full" :class="connected ? 'bg-emerald-400' : 'bg-amber-400'"></span>{{ connected ? 'Live' : 'Connecting' }}</div>
      </div>
    </header>

    <main class="mx-auto max-w-7xl px-5 py-8">
      <section class="overflow-hidden rounded-3xl border border-emerald-900/50 bg-gradient-to-br from-emerald-950/90 to-[#0b1710] p-8 shadow-2xl shadow-black/30">
        <div class="max-w-3xl">
          <span class="rounded-full border border-emerald-700/60 px-3 py-1 text-xs text-emerald-300">Native Yerbas explorer</span>
          <h2 class="mt-5 text-4xl font-bold leading-tight md:text-5xl">Search every block, transaction, address, asset, and smartnode.</h2>
          <p class="mt-4 max-w-2xl text-slate-400">A purpose-built live explorer for the Yerbas blockchain, asset layer, network, and markets.</p>
          <form class="mt-7 flex gap-3" @submit.prevent="runSearch">
            <div class="relative flex-1"><Search class="absolute left-4 top-3.5 h-5 w-5 text-slate-500"/><input v-model="search" class="w-full rounded-xl border border-emerald-900 bg-black/30 py-3 pl-12 pr-4 outline-none focus:border-emerald-500" placeholder="Block height, hash, transaction, address, or asset" /></div>
            <button class="rounded-xl bg-emerald-500 px-6 font-semibold text-[#07110b] hover:bg-emerald-400">Search</button>
          </form>
        </div>
      </section>

      <section class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <article class="stat"><Box/><div><span>Indexed height</span><strong>{{ data.sync?.height ?? '—' }}</strong></div></article>
        <article class="stat"><Activity/><div><span>Chain height</span><strong>{{ chainHeight ?? '—' }}</strong></div></article>
        <article class="stat"><Coins/><div><span>Yerbas assets</span><strong>{{ data.assetCount.toLocaleString() }}</strong></div></article>
        <article class="stat"><Server/><div><span>Indexer</span><strong class="capitalize">{{ data.sync?.status ?? 'idle' }}</strong></div></article>
      </section>

      <section class="mt-6 rounded-2xl border border-emerald-950 bg-[#0b1710] p-5">
        <div class="flex justify-between text-sm"><span class="text-slate-400">Blockchain synchronization</span><span>{{ syncPercent.toFixed(2) }}%</span></div>
        <div class="mt-3 h-2 overflow-hidden rounded-full bg-black/40"><div class="h-full bg-emerald-500 transition-all" :style="{ width: `${syncPercent}%` }"></div></div>
      </section>

      <section class="mt-6 grid gap-6 lg:grid-cols-2">
        <article class="panel">
          <div class="panel-title"><Box/>Latest blocks<a href="/blocks">View all</a></div>
          <div v-if="loading" class="empty">Loading blocks…</div>
          <a v-for="block in data.latestBlocks" :key="block.hash" :href="`/block/${block.height}`" class="row">
            <div><strong>#{{ block.height }}</strong><small>{{ block.hash.slice(0, 18) }}…</small></div><div class="text-right"><strong>{{ block.txCount }} tx</strong><small>{{ new Date(block.time).toLocaleString() }}</small></div>
          </a>
          <div v-if="!loading && !data.latestBlocks.length" class="empty">Waiting for the indexer to write its first block.</div>
        </article>

        <article class="panel">
          <div class="panel-title"><Database/>Latest transactions<a href="/transactions">View all</a></div>
          <a v-for="tx in data.latestTransactions" :key="tx.txid" :href="`/tx/${tx.txid}`" class="row">
            <div><strong>{{ tx.txid.slice(0, 20) }}…</strong><small>Block #{{ tx.blockHeight }}</small></div><WalletCards class="h-5 w-5 text-emerald-400"/>
          </a>
          <div v-if="!loading && !data.latestTransactions.length" class="empty">No indexed transactions yet.</div>
        </article>
      </section>

      <section class="panel mt-6">
        <div class="panel-title"><Coins/>Recent asset activity<a href="/assets">Explore assets</a></div>
        <a v-for="event in data.assetEvents" :key="`${event.txid}:${event.asset}:${event.type}`" :href="`/asset/${encodeURIComponent(event.asset)}`" class="row">
          <div><strong>{{ event.asset }}</strong><small class="capitalize">{{ event.type }} · Block #{{ event.blockHeight }}</small></div><strong>{{ event.amount ?? '—' }}</strong>
        </a>
        <div v-if="!loading && !data.assetEvents.length" class="empty">No indexed asset activity yet.</div>
      </section>
    </main>
  </div>
</template>
