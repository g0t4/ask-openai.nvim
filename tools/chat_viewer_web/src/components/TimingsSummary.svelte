<script lang="ts">
  import type { Message } from '../lib/types'
  import { timingSummaries } from '../lib/timings-summary'
  let { messages }: { messages: Message[] } = $props()
  const summaries = $derived(timingSummaries(messages))
</script>

{#each summaries as summary}
  <section class="mt-8 space-y-4">
    <h2 class="text-lg font-semibold text-gray-200">{summary.name} assistant timings</h2>
    <div class="overflow-x-auto rounded-lg border border-gray-700">
      <table class="w-full text-xs text-right font-mono">
        <thead class="bg-gray-800 text-gray-300"><tr>
          {#each summary.headers as label}<th class="px-3 py-2 whitespace-normal">{label}</th>{/each}
        </tr></thead>
        <tbody class="text-gray-400">
          {#each summary.rows as row}
            <tr class="border-t border-gray-700">
              {#each row as cell, index}<td class="px-3 py-2 whitespace-pre-line" class:opacity-60={summary.headers[index] === 'reasoning tokens' || summary.headers[index] === 'thinking %'}>{cell}</td>{/each}
            </tr>
          {/each}
          <tr class="border-t border-gray-700 font-semibold">
            {#each summary.totals as cell}<td class="px-3 py-2">{cell}</td>{/each}
          </tr>
        </tbody>
      </table>
    </div>
    <p class="text-xs text-gray-400">Durations are summed phase times, not elapsed agent wall time.</p>
  </section>
{/each}
