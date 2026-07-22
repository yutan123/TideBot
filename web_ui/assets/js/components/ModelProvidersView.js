import API from '../api.js';
import Modal from './Modal.js';

export default class ModelProvidersView {
    constructor(container) {
        this.container = container;
        this.render();
    }

    render() {
        this.container.innerHTML = `
            <h2>模型提供商配置</h2>
            <p style="color: var(--text-muted); margin-bottom: 24px;">配置大语言模型、TTS (文字转语音)、STT及 Agent 驱动引擎。</p>
            
            <div class="card">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                    <div class="card-title" style="margin: 0;">OpenAI 兼容接口</div>
                    <span style="background: var(--border-color); padding: 4px 8px; border-radius: 4px; font-size: 12px;">LLM</span>
                </div>
                
                <div class="input-group">
                    <input type="text" class="input-field" placeholder="Base URL (例如: https://api.openai.com/v1)" value="https://api.openai.com/v1">
                </div>
                <div class="input-group">
                    <input type="password" class="input-field" placeholder="API Key (sk-...)">
                </div>
                
                <div style="display: flex; justify-content: flex-end; gap: 12px; margin-top: 16px;">
                    <button class="btn btn-ghost" id="btn-test-openai">连通性测试</button>
                    <button class="btn btn-primary">保存配置</button>
                </div>
            </div>
        `;

        this.container.querySelector('#btn-test-openai').addEventListener('click', async (e) => {
            const btn = e.target;
            btn.innerText = '发送测试消息中...'; btn.disabled = true;
            
            // 调用 api.js 里的模拟请求
            const res = await API.testModelLatency('OpenAI');
            
            btn.innerText = '连通性测试'; btn.disabled = false;
            Modal.show('测试成功', `成功与模型提供商建立连接。<br><br>响应延迟: <strong>${res.latency} ms</strong>`);
        });
    }
}