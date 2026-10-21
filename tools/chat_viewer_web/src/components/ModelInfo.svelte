<script lang="ts">
  import type { ResponseStats as Stats } from '../lib/types'
  import ResponseStats from './ResponseStats.svelte'
  let { model, responseStats }: { model?: string; responseStats?: Stats | null } = $props()
</script>

<div class="model-info mb-4 rounded-lg border border-gray-700 bg-gray-800/50 px-4 py-2 text-sm">
  {#if model}
    <span class="text-gray-400">Model:</span>
    <span class="text-gray-200 font-medium ml-2">{model}</span>
  {/if}
  <ResponseStats response={responseStats} />
</div>
