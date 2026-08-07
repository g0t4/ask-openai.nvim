<script lang="ts">
import { computeWordDiff } from '../lib/patch-parser'
import type { WordDiffSegment } from '../lib/patch-parser'

interface Props {
  userMessage: string
  assistantResponse: string
}

let { userMessage, assistantResponse }: Props = $props()

// qwen native FIM markers
const QWEN_PREFIX = '<|fim_prefix|>'
const QWEN_SUFFIX = '<|fim_suffix|>'
const QWEN_MIDDLE = '<|fim_middle|>'
// deepseek native FIM markers (fullwidth pipe ｜ + ▁ between words)
const DS_BEGIN = '\uff5cfim\u2581begin\uff5c>'
const DS_HOLE = '\uff5cfim\u2581hole\uff5c>'
const DS_END = '\uff5cfim\u2581end\uff5c>'

// Regex matching either FIM hole marker (used to split prefix/suffix)
const HOLE_REGEX = /<\|fim_middle\|>|\uff5cfim\u2581hole\uff5c>/

// deepseek native FIM prompts include repo/file context before the FIM file.
// Extract just the FIM file's code and normalize it to `prefix + hole + suffix`
// so the rest of the logic is shared with qwen.
function normalizeDeepseek(rawPrompt: string): string | null {
  const beginIdx = rawPrompt.lastIndexOf(DS_BEGIN)
  const holeIdx = rawPrompt.lastIndexOf(DS_HOLE)
  if (beginIdx === -1 || holeIdx === -1) return null

  const prefix = rawPrompt.substring(beginIdx + DS_BEGIN.length, holeIdx)
  const endIdx = rawPrompt.lastIndexOf(DS_END)
  const suffix = endIdx > holeIdx
    ? rawPrompt.substring(holeIdx + DS_HOLE.length, endIdx)
    : rawPrompt.substring(holeIdx + DS_HOLE.length)

  return prefix + DS_HOLE + suffix
}

// qwen native FIM prompts also include repo/file context before the FIM file.
// Extract just the FIM file's code and normalize it to `prefix + hole + suffix`.
function normalizeQwen(rawPrompt: string): string | null {
  const prefixIdx = rawPrompt.lastIndexOf(QWEN_PREFIX)
  const suffixIdx = rawPrompt.lastIndexOf(QWEN_SUFFIX)
  if (prefixIdx === -1 || suffixIdx === -1) return null

  const prefix = rawPrompt.substring(prefixIdx + QWEN_PREFIX.length, suffixIdx)
  const middleIdx = rawPrompt.lastIndexOf(QWEN_MIDDLE)
  const suffix = middleIdx > suffixIdx
    ? rawPrompt.substring(suffixIdx + QWEN_SUFFIX.length, middleIdx)
    : rawPrompt.substring(suffixIdx + QWEN_SUFFIX.length)

  return prefix + QWEN_MIDDLE + suffix
}

// Parse the user message to extract the code with the FIM hole marker
const parsedCode = $derived.by(() => {
  // deepseek native FIM: raw prompt with ｜fim▁hole｜>
  const deepseekCode = normalizeDeepseek(userMessage)
  if (deepseekCode) return deepseekCode

  // qwen native FIM: raw prompt with <|fim_prefix|>...<|fim_suffix|>...<|fim_middle|>
  const qwenCode = normalizeQwen(userMessage)
  if (qwenCode) return qwenCode

  // qwen chat completion: look for markdown code block first (handles ```filename.foo format)
  const markdownMatch = userMessage.match(/```[^\n]*\n([\s\S]+?)```/)
  if (markdownMatch) {
    return markdownMatch[1]
  }

  // qwen chat completion: fall back to text after trigger phrases
  const lines = userMessage.split('\n')
  const startIdx = lines.findIndex(line =>
    (line.includes('Please complete') && line.includes(QWEN_MIDDLE)) ||
    (line.includes('Please suggest text to replace') && line.includes(QWEN_MIDDLE))
  )

  if (startIdx === -1) return null

  // Code starts after this line
  return lines.slice(startIdx + 1).join('\n')
})

// Limit context and generate word diff
const diffData = $derived.by(() => {
  if (!parsedCode) return null

  const markerMatch = parsedCode.match(HOLE_REGEX)
  if (!markerMatch) return null
  const marker = markerMatch[0]
  const markerIdx = markerMatch.index

  const CONTEXT_LINES = 10

  const beforeFull = parsedCode.substring(0, markerIdx)
  const afterFull = parsedCode.substring(markerIdx + marker.length)

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
    afterOmitted,
    marker
  }
})
</script>

{#if diffData}
  <div class="fim-preview mb-6 rounded-lg border border-cyan-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-cyan-500/10 border-b border-cyan-500/30">
      <h3 class="text-sm font-semibold text-cyan-400">TLDR</h3>
      <p class="text-xs text-gray-400 mt-1">
        Green shows the assistant's completion inserted at <code class="text-cyan-300">{diffData.marker}</code>
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
