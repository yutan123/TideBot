export default class ChatView {
    constructor(container) {
        this.container = container;
        this.render();
    }

    render() {
        this.container.innerHTML = `
            <div class="chat-wrapper">
                <div class="chat-messages" id="chat-box">
                    <div style="text-align: center; margin-top: 40px;">
                        <div style="width: 48px; height: 48px; border-radius: 50%; background: var(--border-color); display: inline-flex; align-items: center; justify-content: center; margin-bottom: 16px;">
                            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" stroke-width="2"><path d="M12 2a10 10 0 1 0 10 10H12V2z"></path></svg>
                        </div>
                        <h2 style="font-size: 20px; font-weight: 600;">TideBot 引擎就绪</h2>
                        <p style="color: var(--text-muted); font-size: 14px; margin-top: 8px;">发送消息以测试 Agent 工作流。</p>
                    </div>
                </div>
                
                <div class="chat-input-area">
                    <button class="icon-btn" title="上传文件/附件">
                        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
                    </button>
                    <input type="text" placeholder="Type prompt..." id="chat-input">
                    <button class="icon-btn" style="background: var(--primary); color: #fff; padding: 10px;" id="btn-send">
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="22" y1="2" x2="11" y2="13"></line><polygon points="22 2 15 22 11 13 2 9 22 2"></polygon></svg>
                    </button>
                </div>
            </div>
        `;
    }
}