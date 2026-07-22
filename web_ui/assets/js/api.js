/**
 * 统一 API 接口管理
 * 负责与后端进行数据交互，当前包含前端模拟数据供测试 UI
 */
export default class API {
    // 模拟获取穿透 API 地址
    static async getApiAddress() {
        return new Promise(resolve => {
            setTimeout(() => {
                resolve({ success: true, data: 'https://api.tidebot.network/v1/' + Math.random().toString(36).substring(7) });
            }, 1200);
        });
    }

    // 模拟获取一次性 API Key
    static async getApiKey() {
        return new Promise(resolve => {
            setTimeout(() => {
                resolve({ success: true, data: 'tb-' + Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15) });
            }, 800);
        });
    }

    // 模拟测试模型延迟
    static async testModelLatency(modelName) {
        return new Promise(resolve => {
            const latency = Math.floor(Math.random() * 800) + 100; // 模拟 100-900ms 延迟
            setTimeout(() => {
                resolve({ success: true, latency: latency, message: '通信正常' });
            }, latency);
        });
    }
}