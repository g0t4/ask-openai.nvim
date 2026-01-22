<script lang="ts">
import { computeWordDiff } from '../lib/patch-parser'
import type { WordDiffSegment } from '../lib/patch-parser'

interface Props {
  userMessage: string
  assistantResponse: string
}

let { userMessage, assistantResponse }: Props = $props()

// Parse the user message to extract selected code
const userSelection = $derived.by(() => {
  // Look for "Here is the code I selected:" followed by a markdown code block
  const match = userMessage.match(/Here is the code I selected:\s*```[^\n]*\n([\s\S]+?)```/)
  if (match) {
    return match[1]
  }
  return null
})

// Parse the assistant response to extract code (with or without code block)
const assistantCode = $derived.by(() => {
  // Try to extract from markdown code block first
  const match = assistantResponse.match(/```[^\n]*\n([\s\S]+?)```/)
  if (match) {
    return match[1]
  }
  // No code block - assume entire content is the replacement
  return assistantResponse
})

// Generate word diff
const diffData = $derived.by(() => {
  if (!userSelection) return null

  return {
    wordDiff: computeWordDiff(userSelection, assistantCode),
    hasSelection: true
  }
})
</script>

{#if !userSelection}
  <div class="rewrite-preview mb-6 rounded-lg border border-yellow-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-yellow-500/10 border-b border-yellow-500/30">
      <h3 class="text-sm font-semibold text-yellow-400">TLDR</h3>
      <p class="text-xs text-gray-400 mt-1">
        No user selection found in the last user message - cannot generate diff
      </p>
    </div>
  </div>
{:else if diffData}
  <div class="rewrite-preview mb-6 rounded-lg border border-purple-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-purple-500/10 border-b border-purple-500/30">
      <h3 class="text-sm font-semibold text-purple-400">TLDR</h3>
      <p class="text-xs text-gray-400 mt-1">
        Red shows removed text, green shows the assistant's rewrite
      </p>
    </div>

    <div class="p-2 bg-gray-900 font-mono text-sm overflow-x-auto">
      <div class="whitespace-pre-wrap">
        {#each diffData.wordDiff as segment}
          {#if segment.type === 'removed'}
            <span class="bg-red-900/60 text-red-300">{segment.value}</span>
          {:else if segment.type === 'added'}
            <span class="bg-green-900/60 text-green-300">{segment.value}</span>
          {:else}
            <span class="text-gray-300">{segment.value}</span>
          {/if}
        {/each}
      </div>
    </div>
  </div>
{/if}
