<script lang="ts">
import { highlight } from '../lib/highlight'

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

// Split code into before/middle/after parts, limiting context
const codeParts = $derived.by(() => {
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

  return {
    before,
    middle: assistantResponse.trim(),
    after,
    beforeOmitted,
    afterOmitted,
    startLineNum: beforeOmitted + 1
  }
})

// Track line ranges for highlighting
const lineRanges = $derived.by(() => {
  if (!codeParts) return null

  // Count lines in each section (a string with n newlines has n+1 lines, but we need to be careful with empty strings)
  const beforeLineCount = codeParts.before ? codeParts.before.split('\n').length : 0
  const middleLineCount = codeParts.middle ? codeParts.middle.split('\n').length : 0

  return {
    insertStart: beforeLineCount,
    insertEnd: beforeLineCount + middleLineCount - 1
  }
})

// Full merged code for syntax highlighting
const mergedCode = $derived(
  codeParts ? `${codeParts.before}${codeParts.middle}${codeParts.after}` : ''
)

// Detect language from the code or use auto-detection
const highlightedCode = $derived(highlight(mergedCode, 'auto'))

// Split highlighted code back into lines and match with insertion markers
const highlightedLines = $derived.by(() => {
  if (!lineRanges || !codeParts) return []

  const lines = highlightedCode.split('\n')
  return lines.map((html, idx) => ({
    html,
    isInserted: idx >= lineRanges.insertStart && idx <= lineRanges.insertEnd,
    lineNum: idx + codeParts.startLineNum
  }))
})
</script>

{#if codeParts}
  <div class="fim-preview mb-6 rounded-lg border border-cyan-500/30 bg-gray-900 overflow-hidden">
    <div class="px-4 py-2 bg-cyan-500/10 border-b border-cyan-500/30">
      <h3 class="text-sm font-semibold text-cyan-400">FIM Preview (Fill-in-the-Middle)</h3>
      <p class="text-xs text-gray-400 mt-1">
        Green highlighted lines show the assistant's completion inserted at <code class="text-cyan-300">&lt;|fim_middle|&gt;</code>
        {#if codeParts.beforeOmitted > 0 || codeParts.afterOmitted > 0}
          <span class="text-gray-500"> • Showing 10 lines of context before/after</span>
        {/if}
      </p>
    </div>

    <div class="overflow-x-auto">
      <pre class="!m-0 !bg-transparent"><code class="hljs">{#if codeParts.beforeOmitted > 0}<span class="flex"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">⋮</span><span class="pl-3 flex-1 text-gray-500 italic">... ({codeParts.beforeOmitted} lines omitted)</span></span>
{/if}{#each highlightedLines as line}<span class="flex {line.isInserted ? 'bg-green-500/20' : ''}"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">{line.lineNum}</span><span class="pl-3 flex-1">{@html line.html}</span></span>
{/each}{#if codeParts.afterOmitted > 0}<span class="flex"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">⋮</span><span class="pl-3 flex-1 text-gray-500 italic">... ({codeParts.afterOmitted} lines omitted)</span></span>
{/if}</code></pre>
    </div>
  </div>
{/if}

<style>
.fim-preview pre code.hljs {
  display: block;
  overflow-x: auto;
  padding: 0;
}

.fim-preview pre {
  margin: 0;
}
</style>
