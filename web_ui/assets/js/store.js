export default class Store {
    constructor() {
        this.state = {
            mode: 'console', // 'console' 或 'chat'
            currentConsoleView: 'welcome', // 控制台侧边栏激活的视图
            theme: localStorage.getItem('tidebot_theme') || 'light', // 'light' 或 'dark'
            appConnect: {
                apiAddress: null,
                apiKey: null
            }
        };
        this.listeners = {};
    }

    subscribe(event, callback) {
        if (!this.listeners[event]) this.listeners[event] = [];
        this.listeners[event].push(callback);
    }

    emit(event, data) {
        if (this.listeners[event]) {
            this.listeners[event].forEach(callback => callback(data));
        }
    }

    setMode(mode) {
        if (this.state.mode !== mode) {
            this.state.mode = mode;
            this.emit('modeChanged', mode);
        }
    }

    setConsoleView(view) {
        if (this.state.currentConsoleView !== view) {
            this.state.currentConsoleView = view;
            this.emit('consoleViewChanged', view);
        }
    }

    toggleTheme() {
        this.state.theme = this.state.theme === 'light' ? 'dark' : 'light';
        localStorage.setItem('tidebot_theme', this.state.theme);
        this.emit('themeChanged', this.state.theme);
    }

    updateAppConnect(key, value) {
        this.state.appConnect[key] = value;
        this.emit('appConnectUpdated', this.state.appConnect);
    }
}