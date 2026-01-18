import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  server: {
    fs: {
      // Disable strict file serving - we're fetching external URLs, not local files
      strict: false,
    },
  },
})
