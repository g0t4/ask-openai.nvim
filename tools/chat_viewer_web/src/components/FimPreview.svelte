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
    middle: assistantResponse,
    after,
    beforeOmitted,
    afterOmitted,
    startLineNum: beforeOmitted + 1
  }
})

// Build the merged code and track which character ranges are inserted
const mergedData = $derived.by(() => {
  if (!codeParts) return null

  // Merge strings FIRST to preserve exact newline structure
  const mergedCode = codeParts.before + codeParts.middle + codeParts.after

  // Calculate character positions where the middle part starts and ends
  const middleStart = codeParts.before.length
  const middleEnd = middleStart + codeParts.middle.length

  // Split merged code into lines
  const lines = mergedCode.split('\n')

  // Track which character ranges in each line are inserted
  let currentPos = 0
  const allLines = lines.map(line => {
    const lineStart = currentPos
    const lineEnd = currentPos + line.length

    // Calculate the inserted character range within this line
    let insertedStart = null
    let insertedEnd = null

    if (lineStart < middleEnd && lineEnd >= middleStart) {
      // This line overlaps with the inserted middle range
      insertedStart = Math.max(0, middleStart - lineStart)
      insertedEnd = Math.min(line.length, middleEnd - lineStart)
    }

    currentPos = lineEnd + 1 // +1 for the \n that was removed by split
    return { line, insertedStart, insertedEnd }
  })

  return { allLines, mergedCode }
})

// Detect language from the code or use auto-detection
const highlightedCode = $derived(mergedData ? highlight(mergedData.mergedCode, 'auto') : '')

// Helper function to wrap a character range in HTML with a span
function wrapCharRange(html: string, start: number, end: number): string {
  if (start === null || end === null || start >= end) return html

  // Track position in text content (ignoring HTML tags)
  let textPos = 0
  let result = ''
  let insideTag = false
  let inserted = false

  for (let i = 0; i < html.length; i++) {
    const char = html[i]

    if (char === '<') {
      insideTag = true
    } else if (char === '>') {
      insideTag = false
      result += char
      continue
    }

    if (insideTag) {
      result += char
      continue
    }

    // We're at a text character
    if (!inserted && textPos === start) {
      result += '<span class="bg-green-500/20">'
      inserted = true
    }

    result += char
    textPos++

    if (inserted && textPos === end) {
      result += '</span>'
      inserted = false
    }
  }

  // Close span if we reached end of string
  if (inserted) {
    result += '</span>'
  }

  return result
}

// Split highlighted code back into lines and apply insertion markers
const highlightedLines = $derived.by(() => {
  if (!mergedData || !codeParts) return []

  const htmlLines = highlightedCode.split('\n')

  return htmlLines.map((html, idx) => {
    const lineData = mergedData.allLines[idx]
    const isFullyInserted = lineData?.insertedStart === 0 && lineData?.insertedEnd === lineData.line.length
    const isPartiallyInserted = lineData?.insertedStart !== null && !isFullyInserted

    // Apply character-level wrapping for partial insertions
    const processedHtml = isPartiallyInserted
      ? wrapCharRange(html, lineData.insertedStart, lineData.insertedEnd)
      : html

    return {
      html: processedHtml,
      isFullyInserted,
      lineNum: idx + codeParts.startLineNum
    }
  })
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
      <pre class="!m-0 !bg-transparent"><code class="hljs">{#if codeParts.beforeOmitted > 0}<span class="line-container"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">⋮</span><span class="pl-3 flex-1 text-gray-500 italic">... ({codeParts.beforeOmitted} lines omitted)</span></span>{'\n'}{/if}{#each highlightedLines as line, idx}<span class="line-container {line.isFullyInserted ? 'bg-green-500/20' : ''}"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">{line.lineNum}</span><span class="pl-3 flex-1">{@html line.html}</span></span>{idx < highlightedLines.length - 1 ? '\n' : ''}{/each}{#if codeParts.afterOmitted > 0}{'\n'}<span class="line-container"><span class="inline-block w-12 text-right pr-3 text-gray-500 select-none border-r border-gray-700 flex-shrink-0">⋮</span><span class="pl-3 flex-1 text-gray-500 italic">... ({codeParts.afterOmitted} lines omitted)</span></span>{/if}</code></pre>
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

.fim-preview .line-container {
  display: inline;
}
</style>
