/**
 * 全局弹窗组件 (工具类)
 * 职责：提供通用提示/确认框，带毛玻璃遮罩。
 */
export default class Modal {
    static show(title, content) {
        // 创建遮罩
        const overlay = document.createElement('div');
        overlay.style.cssText = `
            position: fixed; top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.4); backdrop-filter: blur(4px);
            display: flex; align-items: center; justify-content: center;
            z-index: 1000; opacity: 0; transition: opacity 0.2s;
        `;

        // 创建卡片
        const card = document.createElement('div');
        card.className = 'card';
        card.style.cssText = `
            width: 90%; max-width: 400px; margin: 0;
            transform: scale(0.95); transition: transform 0.2s;
        `;
        
        card.innerHTML = `
            <h3 style="margin-bottom: 12px; font-size: 18px;">${title}</h3>
            <p style="color: var(--text-muted); font-size: 15px; margin-bottom: 24px;">${content}</p>
            <div style="text-align: right;">
                <button class="btn btn-primary" id="modal-close">确定</button>
            </div>
        `;

        overlay.appendChild(card);
        document.body.appendChild(overlay);

        // 动画触发
        requestAnimationFrame(() => {
            overlay.style.opacity = '1';
            card.style.transform = 'scale(1)';
        });

        // 销毁事件
        const closeBtn = card.querySelector('#modal-close');
        closeBtn.addEventListener('click', () => {
            overlay.style.opacity = '0';
            card.style.transform = 'scale(0.95)';
            setTimeout(() => document.body.removeChild(overlay), 200);
        });
    }
}