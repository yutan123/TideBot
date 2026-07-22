export default class Modal {
    /**
     * 显示自定义对话框
     * @param {string} title - 标题
     * @param {string} content - 内容
     */
    static show(title, content) {
        const overlay = document.createElement('div');
        overlay.style.cssText = `
            position: fixed; top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.4); backdrop-filter: blur(4px); -webkit-backdrop-filter: blur(4px);
            display: flex; align-items: center; justify-content: center;
            z-index: 9999; opacity: 0; transition: opacity 0.2s ease;
        `;
        
        const card = document.createElement('div');
        card.style.cssText = `
            background: var(--card-bg); width: 320px; border-radius: 16px;
            padding: 24px; text-align: center; box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transform: scale(0.9); transition: transform 0.2s cubic-bezier(0.25, 0.8, 0.25, 1);
            border: 1px solid var(--border-color);
        `;
        
        card.innerHTML = `
            <h3 style="margin-bottom: 8px; color: var(--text-main); font-size: 18px;">${title}</h3>
            <p style="color: var(--text-muted); font-size: 14px; margin-bottom: 24px; line-height: 1.5;">${content}</p>
            <button class="btn btn-primary" style="width: 100%;" id="btn-modal-ok">我知道了</button>
        `;
        
        overlay.appendChild(card);
        document.body.appendChild(overlay);

        requestAnimationFrame(() => {
            overlay.style.opacity = '1';
            card.style.transform = 'scale(1)';
        });

        card.querySelector('#btn-modal-ok').addEventListener('click', () => {
            overlay.style.opacity = '0';
            card.style.transform = 'scale(0.9)';
            setTimeout(() => document.body.removeChild(overlay), 200);
        });
    }

    /**
     * 顶部轻提示 Toast
     */
    static toast(msg) {
        const toast = document.createElement('div');
        toast.style.cssText = `
            position: fixed; top: 80px; left: 50%; transform: translate(-50%, -20px);
            background: var(--text-main); color: var(--bg-color); padding: 10px 20px;
            border-radius: 30px; font-size: 14px; font-weight: 500;
            z-index: 10000; opacity: 0; transition: all 0.3s ease;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        `;
        toast.innerText = msg;
        document.body.appendChild(toast);
        
        requestAnimationFrame(() => {
            toast.style.opacity = '1';
            toast.style.transform = 'translate(-50%, 0)';
        });
        
        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translate(-50%, -20px)';
            setTimeout(() => document.body.removeChild(toast), 300);
        }, 2000);
    }
}