<script lang="ts">
  import { highlight } from '../lib/highlight'

  interface Props {
    code: string
    language?: string
  }

  let { code, language = 'text' }: Props = $props()

  const highlighted = $derived(highlight(code, language))
</script>

<pre class="overflow-x-auto text-sm bg-gray-900 p-3 rounded"><code class="hljs">{@html highlighted}</code></pre>
