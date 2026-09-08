import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({plugins:[react()],define:{'process.env.NODE_ENV':JSON.stringify('production')},base:'./',build:{lib:{entry:'src/main.tsx',name:'LullyUI',formats:['iife'],fileName:()=> 'lully.js'},cssCodeSplit:false,rollupOptions:{output:{assetFileNames:'[name][extname]'}}}});
