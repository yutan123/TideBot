/**
 * 核心配置视图 (取代花里胡哨的仪表盘，直接作为主界面)
 */
export default class ConsoleView {
    constructor(container, store) {
        this.container = container;
        this.store = store;
        this.render();
        this.bindEvents();
    }

    render() {
        const { config } = this.store.state;
        this.container.innerHTML = `
            <div class="view-header">
                <h1>核心配置</h1>
                <p>配置大模型 API 与智能体基础设定。</p>
            </div>
            
            <div class="card">
                <div class="form-group">
                    <label>模型提供商 (Model)</label>
                    <input type="text" id="input-model" class="form-control" placeholder="例如: gpt-4-turbo, claude-3-opus" value="${config.modelName}">
                </div>
                
                <div class="form-group">
                    <label>API 密钥 (API Key)</label>
                    <input type="password" id="input-apikey" class="form-control" placeholder="sk-..." value="${config.apiKey}">
                </div>
            </div>

            <div class="card">
                <div class="form-group">
                    <label>系统设定 (System Prompt)</label>
                    <textarea id="input-prompt" class="form-control" placeholder="定义智能体的性格和职责...">${config.systemPrompt}</textarea>
                </div>
                
                <div class="form-group switch-wrapper">
                    <div>
                        <label style="margin-bottom: 0;">流式输出 (Stream)</label>
                        <span style="font-size: 13px; color: var(--text-muted);">启用 WebSocket 逐字返回</span>
                    </div>
                    <label class="switch">
                        <input type="checkbox" id="input-stream" ${config.enableStream ? 'checked' : ''}>
                        <span class="slider"></span>
                    </label>
                </div>
            </div>

            <button id="btn-save" class="btn btn-primary" style="width: 100%;">保存配置</button>
        `;
    }

    bindEvents() {
        const btnSave = this.container.querySelector('#btn-save');
        btnSave.addEventListener('click', () => {
            const modelName = this.container.querySelector('#input-model').value;
            const apiKey = this.container.querySelector('#input-apikey').value;
            const prompt = this.container.querySelector('#input-prompt').value;
            const stream = this.container.querySelector('#input-stream').checked;

            this.store.updateConfig('modelName', modelName);
            this.store.updateConfig('apiKey', apiKey);
            this.store.updateConfig('systemPrompt', prompt);
            this.store.updateConfig('enableStream', stream);
            
            // 此处可接入 Modal 组件做通知，当前用 alert 替代
            alert('配置已在本地更新，准备好连接后端。');
        });
    }
}