import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  // Base path for GitHub Pages - update if deploying to a different repo
  base: '/ask-openai.nvim/',
  server: {
    fs: {
      // Disable strict file serving - we're fetching external URLs, not local files
      strict: false,
    },
  },
})
