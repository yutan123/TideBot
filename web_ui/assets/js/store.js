/**
 * 状态管理器 (Pub/Sub 模式)
 * 职责：管理应用级状态，解耦组件间通信。
 */
export default class Store {
    constructor() {
        this.state = {
            currentView: 'console', // 默认视图
            config: {
                modelName: '',
                apiKey: '',
                systemPrompt: '你是一个得力的 AI 助手。',
                enableStream: true
            },
            isConnected: false // 设备连接状态
        };
        this.listeners = {};
    }

    // 订阅事件
    subscribe(event, callback) {
        if (!this.listeners[event]) {
            this.listeners[event] = [];
        }
        this.listeners[event].push(callback);
    }

    // 发布事件
    emit(event, data) {
        if (this.listeners[event]) {
            this.listeners[event].forEach(callback => callback(data));
        }
    }

    // 更新配置
    updateConfig(key, value) {
        this.state.config[key] = value;
        this.emit('configUpdated', this.state.config);
    }

    // 切换视图
    setView(viewName) {
        if (this.state.currentView !== viewName) {
            this.state.currentView = viewName;
            this.emit('viewChanged', viewName);
        }
    }
}