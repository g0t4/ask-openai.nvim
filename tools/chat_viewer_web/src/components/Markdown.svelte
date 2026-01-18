<script lang="ts">
  import { marked } from 'marked'
  import hljs from 'highlight.js'

  interface Props {
    content: string
  }

  let { content }: Props = $props()

  // Configure marked to use highlight.js for code blocks
  marked.setOptions({
    highlight: (code, lang) => {
      if (lang && hljs.getLanguage(lang)) {
        try {
          return hljs.highlight(code, { language: lang }).value
        } catch {}
      }
      return hljs.highlightAuto(code).value
    },
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
</style>
