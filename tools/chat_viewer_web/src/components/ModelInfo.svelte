<script lang="ts">
  import type { Timings } from '../lib/types'

  interface Props {
    model: string
    timings?: Timings | null
  }

  let { model, timings }: Props = $props()

  function humanizeInt(value: number): string {
    return value.toLocaleString()
  }

  function humanizeFloat(value: number, decimals: number = 1): string {
    return value.toLocaleString(undefined, { 
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals 
    })
  }

  function formatTimings(): string[] {
    if (!timings) return []

    const lines: string[] = []

    // Cache tokens (if present and > 0)
    if (timings.cache_n != null && timings.cache_n > 0) {
      lines.push(`cached: ${humanizeInt(timings.cache_n)} tokens`)
    }

    // Inbound speed
    if (timings.prompt_per_second != null && timings.prompt_per_second > 0) {
      lines.push(`in: ${humanizeInt(timings.prompt_n ?? 0)} tokens @ ${humanizeFloat(timings.prompt_per_second)} tok/sec`)
    }

    // Outbound speed
    if (timings.predicted_per_second != null && timings.predicted_per_second > 0) {
      lines.push(`out: ${humanizeInt(timings.predicted_n ?? 0)} tokens @ ${humanizeFloat(timings.predicted_per_second)} tok/sec`)
    }

    // Draft tokens (speculative decoding / MTP)
    if (timings.draft_n != null && timings.draft_n > 0) {
      const draftAccepted = timings.draft_n_accepted ?? 0
      lines.push(`  draft: ${humanizeInt(draftAccepted)} accepted / ${humanizeInt(timings.draft_n)} tokens`)
    }

    return lines
  }

  const timingLines = formatTimings()
</script>

{#if model}
  <div class="model-info mb-4 rounded-lg border border-gray-700 bg-gray-800/50">
    <div class="px-4 py-2 text-sm">
      <span class="text-gray-400">Model:</span>
      <span class="text-gray-200 font-medium ml-2">{model}</span>
    </div>
    
    {#if timingLines.length > 0}
      <div class="px-4 pb-2 text-sm space-y-0.5">
        {#each timingLines as line}
          <div class="text-gray-400">{line}</div>
        {/each}
      </div>
    {/if}
  </div>
{/if}
