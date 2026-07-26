import { defineConfig } from "vite-plus";

export default defineConfig({
  staged: {
    "*": "secretlint --no-glob",
  },
});
