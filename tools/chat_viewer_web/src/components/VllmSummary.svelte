<script lang="ts">
  import type { Message } from '../lib/types'
  import { vllmGenerations, humanizeInt, optionalMetric, totalTokens, draftAcceptance } from '../lib/response-stats'
  let { messages }: { messages: Message[] } = $props()
  const generations = $derived(vllmGenerations(messages))
  const totalGenerated = $derived(generations.reduce((sum, { response }) => sum + (response.usage?.completion_tokens ?? 0), 0))
  function count(value?: number | null) { return value == null ? '—' : humanizeInt(value) }
</script>

{#if generations.length}
  <section class="mt-8 space-y-4">
    <h2 class="text-lg font-semibold text-gray-200">vLLM Generations</h2>
    <p class="text-xs text-gray-400">Input includes cached tokens. Overall output throughput includes prefill; prompt tok/s is unavailable.</p>
    <div class="overflow-x-auto rounded-lg border border-gray-700">
      <table class="w-full text-xs text-right font-mono whitespace-nowrap">
        <thead class="bg-gray-800 text-gray-300"><tr>
          {#each ['Message', 'Input', 'Cached', 'Output', 'Reasoning', 'Total', 'Draft accepted', 'Mean accept length'] as label}
            <th class="px-3 py-2">{label}</th>
          {/each}
        </tr></thead>
        <tbody class="text-gray-400">
          {#each generations as { index, response }}
            <tr class="border-t border-gray-700">
              <td class="px-3 py-2">#{index}</td>
              <td class="px-3 py-2">{count(response.usage?.prompt_tokens)}</td>
              <td class="px-3 py-2">{count(response.usage?.prompt_tokens_details?.cached_tokens)}</td>
              <td class="px-3 py-2">{count(response.usage?.completion_tokens)}</td>
              <td class="px-3 py-2">{count(response.usage?.completion_tokens_details?.reasoning_tokens)}</td>
              <td class="px-3 py-2">{count(totalTokens(response))}</td>
              <td class="px-3 py-2">{draftAcceptance(response) ?? '—'}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.speculative_decoding?.mean_acceptance_length)}</td>
            </tr>
          {/each}
          <tr class="border-t border-gray-700 font-semibold"><td class="px-3 py-2">Total output</td><td></td><td></td><td class="px-3 py-2">{count(totalGenerated)}</td><td colspan="4"></td></tr>
        </tbody>
      </table>
    </div>
    <div class="overflow-x-auto rounded-lg border border-gray-700">
      <table class="w-full text-xs text-right font-mono whitespace-nowrap">
        <thead class="bg-gray-800 text-gray-300"><tr>
          {#each ['Message', 'TTFT', 'Queue', 'Decode', 'Mean ITL', 'Overall output (includes prefill)'] as label}
            <th class="px-3 py-2">{label}</th>
          {/each}
        </tr></thead>
        <tbody class="text-gray-400">
          {#each generations as { index, response }}
            <tr class="border-t border-gray-700">
              <td class="px-3 py-2">#{index}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.time_to_first_token_ms, ' ms')}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.queue_time_ms, ' ms')}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.generation_time_ms, ' ms')}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.mean_itl_ms, ' ms')}</td>
              <td class="px-3 py-2">{optionalMetric(response.metrics?.tokens_per_second, ' tok/s')}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>
{/if}
