import Modal from './Modal.js';

export default class Header {
    constructor(store) {
        this.store = store;
        this.titleSpan = document.querySelector('#brand-title .subtitle');
        this.themeBtn = document.getElementById('btn-theme-toggle');
        this.connectBtn = document.getElementById('btn-connect-app');
        this.segmentItems = document.querySelectorAll('.segment-item');
        this.indicator = document.querySelector('.segment-indicator');
        
        this.bindEvents();
        this.updateThemeUI(this.store.state.theme);
    }

    bindEvents() {
        // 主题切换
        this.themeBtn.addEventListener('click', () => {
            this.store.toggleTheme();
        });

        this.store.subscribe('themeChanged', (theme) => {
            this.updateThemeUI(theme);
        });

        // 大模式切换 (控制台/Chat)
        this.segmentItems.forEach((item, index) => {
            item.addEventListener('click', () => {
                const mode = item.dataset.mode;
                
                // 动画滑块
                this.indicator.style.transform = `translateX(${index * 100}%)`;
                
                this.segmentItems.forEach(el => el.classList.remove('active'));
                item.classList.add('active');
                
                // 更改左侧标题
                this.titleSpan.innerText = mode === 'console' ? '控制台' : 'chat';
                
                this.store.setMode(mode);
            });
        });

        // 连接 APP 按钮触发视图切换
        this.connectBtn.addEventListener('click', () => {
            if (this.store.state.mode !== 'console') {
                // 如果在聊天模式，先切回控制台
                this.segmentItems[0].click(); 
            }
            this.store.setConsoleView('app-connect');
            // 清理左侧侧边栏高亮
            document.querySelectorAll('.nav-links a').forEach(a => a.classList.remove('active'));
        });
    }

    updateThemeUI(theme) {
        if (theme === 'dark') {
            document.body.classList.add('theme-dark');
            // 切换为月亮图标
            this.themeBtn.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path></svg>`;
        } else {
            document.body.classList.remove('theme-dark');
            // 切换为太阳图标
            this.themeBtn.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"></circle><line x1="12" y1="1" x2="12" y2="3"></line><line x1="12" y1="21" x2="12" y2="23"></line><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line><line x1="1" y1="12" x2="3" y2="12"></line><line x1="21" y1="12" x2="23" y2="12"></line><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line></svg>`;
        }
    }
}