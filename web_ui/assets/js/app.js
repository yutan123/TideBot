import Store from './store.js';
import Navbar from './components/Navbar.js';
import ConsoleView from './components/ConsoleView.js';
import ChatView from './components/ChatView.js';
import APPConnectView from './components/APPConnectView.js';

// 初始化状态中心
const store = new Store();

// 初始化导航/侧边栏
new Navbar(store);

// 视图容器
const viewContainer = document.getElementById('view-container');

// 路由分发器
function renderView(viewName) {
    viewContainer.innerHTML = ''; // 清空当前视图

    switch (viewName) {
        case 'console':
            new ConsoleView(viewContainer, store);
            break;
        case 'chat':
            new ChatView(viewContainer, store);
            break;
        case 'connect':
            new APPConnectView(viewContainer, store);
            break;
        default:
            new ConsoleView(viewContainer, store);
    }
}

// 监听视图切换事件
store.subscribe('viewChanged', (viewName) => {
    renderView(viewName);
});

// 首屏渲染
renderView(store.state.currentView);