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
  // Look for markdown code block first
  const markdownMatch = userMessage.match(/```[\w]*\n([\s\S]+?)```/)
  if (markdownMatch) {
    return markdownMatch[1]
  }

  // Fall back to text after "Please complete <|fim_middle|> in the following code"
  const lines = userMessage.split('\n')
  const startIdx = lines.findIndex(line =>
    line.includes('Please complete') && line.includes('<|fim_middle|>')
  )

  if (startIdx === -1) return null

  // Code starts after this line
  return lines.slice(startIdx + 1).join('\n')
})

// Generate word diff between code with marker and completed code
const wordDiff = $derived.by((): WordDiffSegment[] | null => {
  if (!parsedCode) return null

  const markerIdx = parsedCode.indexOf('<|fim_middle|>')
  if (markerIdx === -1) return null

  // "Old" text has the marker
  const oldText = parsedCode

  // "New" text has the marker replaced with the assistant's response
  const newText = parsedCode.substring(0, markerIdx) +
                  assistantResponse +
                  parsedCode.substring(markerIdx + '<|fim_middle|>'.length)

  return computeWordDiff(oldText, newText)
})
</script>

{#if wordDiff}
  <div class="fim-preview mb-6 rounded-lg border border-cyan-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-cyan-500/10 border-b border-cyan-500/30">
      <h3 class="text-sm font-semibold text-cyan-400">FIM Preview (Fill-in-the-Middle)</h3>
      <p class="text-xs text-gray-400 mt-1">
        Red shows the <code class="text-cyan-300">&lt;|fim_middle|&gt;</code> marker being replaced, green shows the assistant's completion
      </p>
    </div>

    <div class="p-2 bg-gray-900 font-mono text-sm overflow-x-auto">
      <div class="whitespace-pre-wrap">
        {#each wordDiff as segment}
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
