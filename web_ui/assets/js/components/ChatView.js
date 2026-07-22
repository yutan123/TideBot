/**
 * 对话测试视图 (预留真实接口对接位置，不写死假数据)
 */
export default class ChatView {
    constructor(container, store) {
        this.container = container;
        this.store = store;
        this.render();
    }

    render() {
        this.container.innerHTML = `
            <div class="view-header">
                <h1>对话测试</h1>
                <p>在控制台内直接验证模型与智能体逻辑。</p>
            </div>
            
            <div class="card" style="display: flex; flex-direction: column; height: 500px; padding: 0; overflow: hidden;">
                <!-- 聊天消息区 -->
                <div id="chat-history" style="flex: 1; padding: 24px; overflow-y: auto; background: #fafafa;">
                    <div class="empty-state">
                        <p>环境已准备就绪，输入消息开始测试。</p>
                    </div>
                </div>
                <!-- 输入区 -->
                <div style="padding: 16px; border-top: 1px solid var(--card-border); background: #fff;">
                    <div style="display: flex; gap: 12px;">
                        <input type="text" id="chat-input" class="form-control" placeholder="发送测试消息...">
                        <button class="btn btn-primary">发送</button>
                    </div>
                </div>
            </div>
        `;
    }
}