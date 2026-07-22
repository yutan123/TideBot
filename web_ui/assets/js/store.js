// TideBot Global Reactive Store
const store = Vue.reactive({
    // Navigation State
    currentMode: 'console', // 'console' | 'chat'
    currentView: 'main',    // 'main' | 'app-connect'
    isDarkMode: true,

    // App Connection State (Temporary per session)
    apiAddress: null,
    apiKey: null,
    isGeneratingTunnel: false,
    isGeneratingKey: false,

    // Modal & Toast System State
    modal: {
        show: false,
        title: '',
        message: '',
        confirmText: '确定',
        cancelText: null,
        onConfirm: null
    },
    toast: {
        show: false,
        message: '',
        type: 'info' // 'info' | 'success' | 'warning' | 'error'
    },

    // Agent & System Config State
    systemConfig: {
        agentName: 'TideBot Core',
        model: 'GPT-4o (Primary Router)',
        fallbackModel: 'Claude 3.5 Sonnet',
        temperature: 0.7,
        streamResponse: true,
        cfTunnelAutoStart: true,
        adapters: {
            wechat: { enabled: true, status: '已连接', account: 'TideBot_Assistant' },
            telegram: { enabled: true, status: '在线 (Polling)', botName: '@TideBot_Official_Bot' },
            qq: { enabled: false, status: '未启用', account: '-' }
        },
        plugins: [
            { id: 'p1', name: 'Web Search Engine', version: 'v1.4.0', status: 'active', desc: '谷歌/必应网络实时搜索扩展' },
            { id: 'p2', name: 'Python Interpreter', version: 'v2.1.0', status: 'active', desc: '沙盒环境 Python 代码自动执行与图表渲染' },
            { id: 'p3', name: 'GitHub Integration', version: 'v0.9.2', status: 'disabled', desc: '代码仓库 Issue 与 PR 自动跟踪管理' }
        ]
    },

    // Chat State
    activeConversationId: 'c1',
    conversations: [
        {
            id: 'c1',
            title: 'TideBot 架构方案讨论',
            time: '17:20',
            messages: [
                { id: 'm1', sender: 'bot', text: '你好！我是 TideBot，你的全能 AI 智能体助手。有什么可以帮你的吗？', time: '17:20', thoughts: null },
                { id: 'm2', sender: 'user', text: '帮我规划一下最新的控制台 WebUI 风格和架构细节。', time: '17:21', thoughts: null },
                { id: 'm3', sender: 'bot', text: '没问题！建议采用 iOS & Telegram 毛玻璃极简质感，搭配平滑的弹性物理动画，划分 Console 与 Chat 模式，并提供单次会话级 Cloudflare 穿透连接。', time: '17:21', thoughts: 'Agent 状态: 调用 Plan-and-Solve 引擎 -> 生成 UI 架构方案卡片' }
            ]
        },
        {
            id: 'c2',
            title: 'Python 数据分析脚本编写',
            time: '昨天',
            messages: [
                { id: 'm1', sender: 'user', text: '需要一个处理 CSV 的脚本。', time: '昨天', thoughts: null },
                { id: 'm2', sender: 'bot', text: '已经为你准备好基于 pandas 的多维度分析脚本。', time: '昨天', thoughts: null }
            ]
        }
    ],

    // Global Methods
    toggleTheme() {
        this.isDarkMode = !this.isDarkMode;
        if (this.isDarkMode) {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
    },

    setMode(mode) {
        this.currentMode = mode;
        this.currentView = 'main';
    },

    openAppConnect() {
        this.currentView = 'app-connect';
    },

    showToast(message, type = 'success') {
        this.toast.message = message;
        this.toast.type = type;
        this.toast.show = true;
        setTimeout(() => {
            this.toast.show = false;
        }, 2500);
    },

    showAlert(title, message) {
        this.modal.title = title;
        this.modal.message = message;
        this.modal.cancelText = null;
        this.modal.confirmText = '我知道了';
        this.modal.onConfirm = () => { this.modal.show = false; };
        this.modal.show = true;
    },

    showConfirm(title, message, onConfirm) {
        this.modal.title = title;
        this.modal.message = message;
        this.modal.cancelText = '取消';
        this.modal.confirmText = '确认';
        this.modal.onConfirm = () => {
            this.modal.show = false;
            if (onConfirm) onConfirm();
        };
        this.modal.show = true;
    },

    // Cloudflare Tunnel API Address Mock
    fetchApiAddress() {
        this.isGeneratingTunnel = true;
        setTimeout(() => {
            const randomHash = Math.random().toString(36).substring(2, 8);
            this.apiAddress = `https://tidebot-tunnel-${randomHash}.trycloudflare.com/api/v1`;
            this.isGeneratingTunnel = false;
            this.showToast('Cloudflare 内网穿透已建立！', 'success');
        }, 1200);
    },

    // API Key Mock
    fetchApiKey() {
        this.isGeneratingKey = true;
        setTimeout(() => {
            const randomKey = Array.from({length: 24}, () => Math.floor(Math.random() * 16).toString(16)).join('');
            this.apiKey = `tb_live_${randomKey}`;
            this.isGeneratingKey = false;
            this.showToast('临时 API Key 生成成功！', 'success');
        }, 800);
    },

    copyToClipboard(text, label) {
        if (!text) return;
        navigator.clipboard.writeText(text).then(() => {
            this.showToast(`${label} 已复制到剪贴板`, 'success');
        }).catch(() => {
            this.showToast('复制失败，请手动选择复制', 'error');
        });
    }
});
