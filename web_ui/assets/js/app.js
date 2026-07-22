// Vue Main Application Initialization
const { createApp } = Vue;

const app = createApp({
    setup() {
        Vue.onMounted(() => {
            // Render Lucide icons
            if (window.lucide) window.lucide.createIcons();
        });
        return { store };
    }
});

// Register Components
app.component('navbar-component', NavbarComponent);
app.component('console-view', ConsoleView);
app.component('chat-view', ChatView);
app.component('app-connect-view', AppConnectView);
app.component('modal-component', ModalComponent);

// Mount Vue Application
app.mount('#app');
