/**
 * 导航条/侧边栏组件
 * 职责：处理菜单高亮、路由切换触发、移动端抽屉收放。
 */
export default class Navbar {
    constructor(store) {
        this.store = store;
        this.links = document.querySelectorAll('.nav-links a');
        this.sidebar = document.getElementById('sidebar');
        this.menuToggle = document.getElementById('menu-toggle');
        this.bindEvents();
    }

    bindEvents() {
        // 路由切换
        this.links.forEach(link => {
            link.addEventListener('click', (e) => {
                e.preventDefault();
                const view = link.getAttribute('data-view');
                
                // 更新 UI 高亮
                this.links.forEach(l => l.classList.remove('active'));
                link.classList.add('active');

                // 移动端点击后自动收起侧边栏
                if (window.innerWidth <= 768) {
                    this.sidebar.classList.remove('open');
                }

                this.store.setView(view);
            });
        });

        // 移动端汉堡菜单切换
        if (this.menuToggle) {
            this.menuToggle.addEventListener('click', () => {
                this.sidebar.classList.toggle('open');
            });
        }
    }
}