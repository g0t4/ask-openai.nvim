<script lang="ts">
  import { marked } from 'marked'
  import hljs from 'highlight.js'
  import { getLanguageFromPath } from '../lib/highlight'

  interface Props {
    content: string
  }

  let { content }: Props = $props()

  // Custom renderer for code blocks
  const renderer = new marked.Renderer()

  renderer.code = function(token: any) {
    const code = token.text
    const lang = token.lang || ''

    // Check if lang looks like a file path (contains / or . with extension)
    const isFilePath = lang.includes('/') || (lang.includes('.') && lang.split('.').length > 1)

    if (isFilePath) {
      // Extract language from file path
      const language = getLanguageFromPath(lang)

      // Highlight the code
      let highlightedCode: string
      try {
        if (language && hljs.getLanguage(language)) {
          highlightedCode = hljs.highlight(code, { language }).value
        } else {
          highlightedCode = hljs.highlightAuto(code).value
        }
      } catch {
        highlightedCode = code
      }

      // Return custom HTML with filename header
      return `<div class="code-block-with-file">
        <div class="code-file-header">${lang}</div>
        <pre class="code-content"><code class="hljs">${highlightedCode}</code></pre>
      </div>`
    }

    // For non-file-path langs, use default behavior with highlighting
    let highlightedCode: string
    try {
      if (lang && hljs.getLanguage(lang)) {
        highlightedCode = hljs.highlight(code, { language: lang }).value
      } else {
        highlightedCode = hljs.highlightAuto(code).value
      }
    } catch {
      highlightedCode = code
    }

    return `<pre><code class="hljs language-${lang}">${highlightedCode}</code></pre>`
  }

  // Configure marked
  marked.setOptions({
    renderer: renderer,
  })

  const html = $derived(marked.parse(content) as string)
</script>

<div class="prose prose-invert prose-sm max-w-none">
  {@html html}
</div>

<style>
  /* Custom prose styling for dark theme */
  :global(.prose) {
    --tw-prose-body: rgb(229, 231, 235);
    --tw-prose-headings: rgb(243, 244, 246);
    --tw-prose-links: rgb(96, 165, 250);
    --tw-prose-bold: rgb(243, 244, 246);
    --tw-prose-code: rgb(251, 191, 36);
    --tw-prose-pre-bg: rgb(31, 41, 55);
    --tw-prose-pre-code: rgb(229, 231, 235);
  }

  :global(.prose code) {
    background-color: rgb(55, 65, 81);
    padding: 0.125rem 0.25rem;
    border-radius: 0.25rem;
    font-size: 0.875em;
  }

  :global(.prose pre) {
    background-color: rgb(31, 41, 55);
    border: 1px solid rgb(75, 85, 99);
  }

  :global(.prose pre code) {
    background-color: transparent;
    padding: 0;
  }

  :global(.prose a) {
    text-decoration: none;
  }

  :global(.prose a:hover) {
    text-decoration: underline;
  }

  /* Code blocks with file headers */
  :global(.prose .code-block-with-file) {
    border: 1px solid rgb(75, 85, 99);
    border-radius: 0.375rem;
    overflow: hidden;
    margin: 1rem 0;
  }

  :global(.prose .code-file-header) {
    padding: 0.375rem 0.75rem;
    background-color: rgba(55, 65, 81, 0.5);
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 0.875rem;
    color: rgb(96, 165, 250);
    border-bottom: 1px solid rgb(75, 85, 99);
  }

  :global(.prose .code-content) {
    margin: 0;
    padding: 0.5rem;
    background-color: rgb(31, 41, 55);
    border: none;
  }

  :global(.prose .code-content code) {
    background-color: transparent;
    padding: 0;
  }
</style>
