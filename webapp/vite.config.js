import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Servido pelo mesmo nginx que entrega o HLS e as gravações, sob /app/.
  // Servido na raiz; /live e /recordings têm locations próprias no nginx e
  // têm precedência, então não há colisão.
  base: "/",
  build: { outDir: "dist", emptyOutDir: true },
  server: {
    // Durante o desenvolvimento no Mac, as chamadas vão para o gravador real.
    proxy: {
      "/live": { target: "http://192.168.0.19:8088", changeOrigin: true },
      "/recordings": { target: "http://192.168.0.19:8088", changeOrigin: true },
    },
  },
});
