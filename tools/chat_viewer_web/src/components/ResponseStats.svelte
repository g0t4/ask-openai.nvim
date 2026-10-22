<script lang="ts">
  import type { ResponseStats } from '../lib/types'
  import { formatResponseStats } from '../lib/response-stats'
  let { response }: { response?: ResponseStats | null } = $props()
  const lines = $derived(formatResponseStats(response))
</script>

{#if lines.length}
  <div class="my-3 flex flex-col gap-1 text-xs text-gray-400 font-mono">
    {#each lines as line}<div class="whitespace-pre-wrap">{line}</div>{/each}
  </div>
{/if}
