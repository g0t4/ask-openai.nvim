<script lang="ts">
import { computeWordDiff } from '../lib/patch-parser'
import type { WordDiffSegment } from '../lib/patch-parser'

interface Props {
  userMessage: string
  assistantResponse: string
}

let { userMessage, assistantResponse }: Props = $props()

// Parse the user message to extract the code with <|fim_middle|> marker
const parsedCode = $derived.by(() => {
  // Look for markdown code block first (handles ```filename.foo format)
  const markdownMatch = userMessage.match(/```[^\n]*\n([\s\S]+?)```/)
  if (markdownMatch) {
    return markdownMatch[1]
  }

  // Fall back to text after trigger phrases
  const lines = userMessage.split('\n')
  const startIdx = lines.findIndex(line =>
    (line.includes('Please complete') && line.includes('<|fim_middle|>')) ||
    (line.includes('Please suggest text to replace') && line.includes('<|fim_middle|>'))
  )

  if (startIdx === -1) return null

  // Code starts after this line
  return lines.slice(startIdx + 1).join('\n')
})

// Limit context and generate word diff
const diffData = $derived.by(() => {
  if (!parsedCode) return null

  const markerIdx = parsedCode.indexOf('<|fim_middle|>')
  if (markerIdx === -1) return null

  const CONTEXT_LINES = 10

  const beforeFull = parsedCode.substring(0, markerIdx)
  const afterFull = parsedCode.substring(markerIdx + '<|fim_middle|>'.length)

  // Limit before context to last N lines
  const beforeLines = beforeFull.split('\n')
  const beforeOmitted = beforeLines.length > CONTEXT_LINES ? beforeLines.length - CONTEXT_LINES : 0
  const before = beforeLines.length > CONTEXT_LINES
    ? beforeLines.slice(-CONTEXT_LINES).join('\n')
    : beforeFull

  // Limit after context to first N lines
  const afterLines = afterFull.split('\n')
  const afterOmitted = afterLines.length > CONTEXT_LINES ? afterLines.length - CONTEXT_LINES : 0
  const after = afterLines.length > CONTEXT_LINES
    ? afterLines.slice(0, CONTEXT_LINES).join('\n')
    : afterFull

  // "Old" text is just the context (no marker - it wasn't in the original code)
  const oldText = before + after

  // "New" text has the assistant's completion inserted
  const newText = before + assistantResponse + after

  return {
    wordDiff: computeWordDiff(oldText, newText),
    beforeOmitted,
    afterOmitted
  }
})
</script>

{#if diffData}
  <div class="fim-preview mb-6 rounded-lg border border-cyan-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-cyan-500/10 border-b border-cyan-500/30">
      <h3 class="text-sm font-semibold text-cyan-400">FIM Preview (Fill-in-the-Middle)</h3>
      <p class="text-xs text-gray-400 mt-1">
        Green shows the assistant's completion inserted at <code class="text-cyan-300">&lt;|fim_middle|&gt;</code>
        {#if diffData.beforeOmitted > 0 || diffData.afterOmitted > 0}
          <span class="text-gray-500"> • Showing 10 lines of context before/after</span>
        {/if}
      </p>
    </div>

    <div class="p-2 bg-gray-900 font-mono text-sm overflow-x-auto">
      <div class="whitespace-pre-wrap">
        {#if diffData.beforeOmitted > 0}
          <div class="text-gray-500 mb-1">... ({diffData.beforeOmitted} lines omitted)</div>
        {/if}
        {#each diffData.wordDiff as segment}
          {#if segment.type === 'removed'}
            <span class="bg-red-900/60 text-red-300">{segment.value}</span>
          {:else if segment.type === 'added'}
            <span class="bg-green-900/60 text-green-300">{segment.value}</span>
          {:else}
            <span class="text-gray-300">{segment.value}</span>
          {/if}
        {/each}
        {#if diffData.afterOmitted > 0}
          <div class="text-gray-500 mt-1">... ({diffData.afterOmitted} lines omitted)</div>
        {/if}
      </div>
    </div>
  </div>
{/if}
