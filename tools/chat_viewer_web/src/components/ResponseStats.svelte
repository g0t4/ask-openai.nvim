<script lang="ts">
  import type { ResponseStats } from '../lib/types'
  import { formatResponseStats } from '../lib/response-stats'
  let { response }: { response?: ResponseStats | null } = $props()
  const lines = $derived(formatResponseStats(response))
</script>

{#if lines.length}
  <div class="my-3 grid gap-x-6 gap-y-1 sm:grid-cols-2 text-xs text-gray-400 font-mono">
    {#each lines as line}<div>{line}</div>{/each}
  </div>
{/if}
