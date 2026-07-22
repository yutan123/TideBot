import API from '../api.js';
import Modal from './Modal.js';

export default class APPConnectView {
    constructor(container, store) {
        this.container = container;
        this.store = store;
        this.render();
    }

    render() {
        const data = this.store.state.appConnect;
        
        this.container.innerHTML = `
            <div style="max-width: 600px; margin: 0 auto; padding-top: 20px;">
                <h2 style="margin-bottom: 8px;">连接外部应用</h2>
                <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 32px;">在此获取内网穿透地址与一次性密钥。重启引擎后配置将失效。</p>
                
                <div class="card">
                    <div class="card-title">API 访问地址</div>
                    <div class="input-group">
                        <input type="text" class="input-field" id="val-api-address" readonly 
                            value="${data.apiAddress || '未获取到API地址'}">
                        <button class="btn btn-primary" id="btn-get-address">获取地址</button>
                        <button class="btn btn-ghost" id="btn-copy-address">复制</button>
                    </div>
                </div>

                <div class="card">
                    <div class="card-title">安全鉴权密钥 (API Key)</div>
                    <div class="input-group">
                        <input type="text" class="input-field" id="val-api-key" readonly 
                            value="${data.apiKey || '还未获取APIkey'}">
                        <button class="btn btn-primary" id="btn-get-key">生成密钥</button>
                        <button class="btn btn-ghost" id="btn-copy-key">复制</button>
                    </div>
                </div>

                <div class="card" style="text-align: center; padding: 40px 20px;">
                    <div style="margin-bottom: 16px; color: var(--text-main);">
                        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="5" y="2" width="14" height="20" rx="2" ry="2"></rect><line x1="12" y1="18" x2="12.01" y2="18"></line></svg>
                    </div>
                    <h3 style="margin-bottom: 12px;">获取 TideBot 移动端</h3>
                    <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 24px;">使用专属移动应用获得沉浸式 AI 体验。</p>
                    <button class="btn btn-primary" id="btn-download-app">敬请期待</button>
                </div>
            </div>
        `;

        this.bindEvents();
    }

    bindEvents() {
        // 获取 API 地址
        this.container.querySelector('#btn-get-address').addEventListener('click', async (e) => {
            const btn = e.target;
            btn.innerText = '获取中...'; btn.disabled = true;
            const res = await API.getApiAddress();
            this.store.updateAppConnect('apiAddress', res.data);
            this.render(); // 重新渲染更新数据
            Modal.toast('穿透地址获取成功');
        });

        // 复制功能封装
        const bindCopy = (btnId, inputId, msg) => {
            this.container.querySelector(btnId).addEventListener('click', () => {
                const val = this.container.querySelector(inputId).value;
                if(val.includes('未获取')) return Modal.show('提示', '请先获取配置信息。');
                navigator.clipboard.writeText(val).then(() => Modal.toast(msg));
            });
        };
        bindCopy('#btn-copy-address', '#val-api-address', '地址已复制');
        
        // 获取 Key
        this.container.querySelector('#btn-get-key').addEventListener('click', async (e) => {
            e.target.innerText = '生成中...'; e.target.disabled = true;
            const res = await API.getApiKey();
            this.store.updateAppConnect('apiKey', res.data);
            this.render();
            Modal.toast('API Key 生成成功');
        });
        bindCopy('#btn-copy-key', '#val-api-key', '密钥已复制');

        this.container.querySelector('#btn-download-app').addEventListener('click', () => {
            Modal.show('开发中', '移动端 App 正在加紧研发中，敬请期待下一个版本的发布！');
        });
    }
}