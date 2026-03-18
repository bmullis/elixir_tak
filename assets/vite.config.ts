import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteStaticCopy } from "vite-plugin-static-copy";
import path from "path";

const cesiumSource = path.resolve(
  __dirname,
  "node_modules/cesium/Build/Cesium"
);

export default defineConfig(({ command }) => {
  const isDev = command === "serve";

  return {
    plugins: [
      react(),
      viteStaticCopy({
        targets: [
          { src: `${cesiumSource}/Workers`, dest: "cesium" },
          { src: `${cesiumSource}/Assets`, dest: "cesium" },
          { src: `${cesiumSource}/ThirdParty`, dest: "cesium" },
          { src: `${cesiumSource}/Widgets`, dest: "cesium" },
        ],
      }),
    ],
    base: isDev ? "/" : "/dashboard/",
    define: {
      CESIUM_BASE_URL: JSON.stringify(isDev ? "/cesium" : "/dashboard/cesium"),
    },
    build: {
      outDir: "../priv/static/dashboard",
      emptyOutDir: true,
    },
    server: {
      port: 5173,
      proxy: {
        "/api": "http://localhost:8080",
        "/socket/dashboard": {
          target: "ws://localhost:8080",
          ws: true,
        },
      },
    },
  };
});
