/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{svelte,js,ts}'],
  theme: {
    extend: {
      colors: {
        // Match your Python viewer's role colors
        'role-system': '#d946ef',    // magenta
        'role-developer': '#06b6d4', // cyan
        'role-user': '#22c55e',      // green
        'role-assistant': '#eab308', // yellow
        'role-tool': '#ef4444',      // red
      },
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
  ],
}
