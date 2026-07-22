import Store from './store.js';
import Header from './components/Header.js';
import ChatView from './components/ChatView.js';
import APPConnectView from './components/APPConnectView.js';
import ModelProvidersView from './components/ModelProvidersView.js';

const store = new Store();
new Header(store);

const sidebar = document.getElementById('sidebar');
const viewContainer = document.getElementById('view-container');
const navLinks = document.querySelectorAll('.nav-links a');

// 路由映射表
const routeMap = {
    'chat': (container) => new ChatView(container),
    'app-connect': (container) => new APPConnectView(container, store),
    'model-providers': (container) => new ModelProvidersView(container),
    'welcome': (container) => {
        container.innerHTML = `<h2>欢迎使用 TideBot</h2><p style="color: var(--text-muted); margin-top: 10px;">请在左侧选择要配置的项目。</p>`;
    }
    // 其他设置页面暂时使用统一兜底
};

// 监听大模式切换
store.subscribe('modeChanged', (mode) => {
    if (mode === 'chat') {
        sidebar.classList.add('hidden');
        renderView('chat');
    } else {
        sidebar.classList.remove('hidden');
        renderView(store.state.currentConsoleView);
    }
});

// 监听侧边栏切换
store.subscribe('consoleViewChanged', (viewName) => {
    if (store.state.mode === 'console') {
        renderView(viewName);
    }
});

// 视图渲染执行器
function renderView(viewName) {
    viewContainer.innerHTML = '';
    const renderFn = routeMap[viewName];
    if (renderFn) {
        renderFn(viewContainer);
    } else {
        viewContainer.innerHTML = `<div class="card"><h3 style="color:var(--text-muted);">"${viewName}" 模块正在开发中...</h3></div>`;
    }
}

// 绑定侧边栏点击事件
navLinks.forEach(link => {
    link.addEventListener('click', (e) => {
        e.preventDefault();
        navLinks.forEach(l => l.classList.remove('active'));
        link.classList.add('active');
        store.setConsoleView(link.dataset.view);
    });
});

// 初始首屏渲染
renderView(store.state.currentConsoleView);