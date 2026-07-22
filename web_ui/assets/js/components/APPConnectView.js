/**
 * 终端连接视图 (去除虚假状态，展示真实空状态)
 */
export default class APPConnectView {
    constructor(container, store) {
        this.container = container;
        this.store = store;
        this.render();
    }

    render() {
        const isConnected = this.store.state.isConnected;

        this.container.innerHTML = `
            <div class="view-header">
                <h1>终端连接</h1>
                <p>将移动端 App 或外部平台接入此底座。</p>
            </div>
            
            <div class="card" style="text-align: center; padding: 60px 20px;">
                ${isConnected ? 
                    `<div style="color: var(--success); font-weight: 600; font-size: 18px;">✅ 已建立安全连接</div>` : 
                    `<div class="empty-state">
                        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" style="margin-bottom: 16px; color: #d2d2d7;">
                            <rect x="5" y="2" width="14" height="20" rx="2" ry="2"></rect>
                            <line x1="12" y1="18" x2="12.01" y2="18"></line>
                        </svg>
                        <h3 style="color: var(--text-main); margin-bottom: 8px;">等待设备接入</h3>
                        <p style="font-size: 14px;">请在 TideBot 移动端扫描控制台或输入下方密钥。</p>
                        <div style="margin-top: 24px; padding: 12px; background: var(--bg-color); border-radius: var(--radius-md); font-family: monospace; letter-spacing: 2px;">
                            WS-WAITING-CONNECTION
                        </div>
                    </div>`
                }
            </div>
        `;
    }
}