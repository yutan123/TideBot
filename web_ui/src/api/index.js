/**
 * 核心接口统一管理 (API Gateway)
 * 严格按照要求：无假数据。在后端未就绪前，默认返回 null 或 0
 */

const BASE_URL = '' // 后续填入后端实际地址

// 通用请求包装 (预留)
async function request(endpoint, options = {}) {
  try {
    const res = await fetch(`${BASE_URL}${endpoint}`, options)
    if (!res.ok) return null
    return await res.json()
  } catch (error) {
    console.error(`API Error at ${endpoint}:`, error)
    return null
  }
}

// ================= 全局设置相关 =================
export const getSystemSettings = async () => {
  return null
}

export const updateSystemSettings = async (settings) => {
  return null
}

// ================= 模型提供商 (LLM, TTS, SST, Agent) =================
export const getModelProviders = async () => {
  return null
}

// 测试模型延迟 (返回真实毫秒数，若失败或无数据返回 0)
export const testModelDelay = async (providerId, modelName) => {
  return 0
}

// ================= App 连接与内网穿透 =================
export const generateTunnelUrl = async () => {
  return null // 成功后应返回真实的 url 字符串
}

export const generateApiKey = async () => {
  return null 
}

export const getAppConnectStatus = async () => {
  return null
}

// ================= 插件与 Skills =================
export const getPluginsList = async () => {
  return null
}

export const togglePluginStatus = async (pluginId, isActive) => {
  return null
}