import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { localDirectoryListing } from './vite-plugins/local-directory-listing'

export default defineConfig({
  plugins: [svelte(), localDirectoryListing()],
  // Base path for GitHub Pages - update if deploying to a different repo
  base: '/ask-openai.nvim/',
  server: {
    port: 5173,
    fs: {
      // Disable strict file serving - we're fetching external URLs, not local files
      strict: false,
    },
  },
})
