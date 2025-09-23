import Pusher from 'pusher-js'
import { createInertiaApp, router } from '@inertiajs/vue3';
import { configureEcho } from '@laravel/echo-vue';
import { resolvePageComponent } from 'laravel-vite-plugin/inertia-helpers';
import type { DefineComponent } from 'vue';
import { createApp, h } from 'vue';
import '../css/app.css';
import { initializeTheme } from './composables/useAppearance';

;(window as any).Pusher = Pusher

const env = import.meta.env as any
const scheme = (env.VITE_REVERB_SCHEME ?? env.VITE_PUSHER_SCHEME ?? (location.protocol === 'https:' ? 'https' : 'http')) as string
const port   = Number(env.VITE_REVERB_PORT ?? env.VITE_PUSHER_PORT ?? (scheme === 'https' ? 443 : 80))
const host   = (env.VITE_REVERB_HOST ?? env.VITE_PUSHER_HOST ?? window.location.hostname) as string
const key    = (env.VITE_REVERB_APP_KEY ?? env.VITE_PUSHER_APP_KEY) as string
const basePath = String(env.VITE_REVERB_PATH ?? '/reverb').replace(/\/+$/, '')

configureEcho({
  broadcaster: 'reverb',
  key,
  wsHost: host,
  wsPort: port,
  wssPort: port,
  forceTLS: scheme === 'https',
  enabledTransports: ['ws', 'wss'],
  // Reverb is proxied at /reverb, the websocket endpoint is /reverb/app
  wsPath: `${basePath}/app`,
})

const appName = import.meta.env.VITE_APP_NAME || 'Laravel';

createInertiaApp({
    title: (title) => {
        // Check if we're in PWA mode
        const isPWA = window.matchMedia('(display-mode: standalone)').matches;
        if (isPWA) {
            return 'wormhole.systems';
        }
        // In browser mode, use the normal title format
        return title ? `${title} | ${appName}` : appName;
    },
    resolve: (name) => resolvePageComponent(`./pages/${name}.vue`, import.meta.glob<DefineComponent>('./pages/**/*.vue')),
    setup({ el, App, props, plugin }) {
        createApp({ render: () => h(App, props) })
            .use(plugin)
            .mount(el);
    },
    progress: {
        color: '#4B5563',
        delay: 1_000,
    },
});

initializeTheme();
