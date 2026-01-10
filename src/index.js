const HIDE_IP_SEGMENTS = true; 
const DEFAULT_NODE_NAME = "未知节点";

function maskIPAddress(ip) {
    if (!HIDE_IP_SEGMENTS) return ip;
    if (ip.includes('.')) {
        const parts = ip.split('.');
        if (parts.length === 4) return `${parts[0]}.${parts[1]}.x.x`;
    }
    if (ip.includes(':')) {
        const parts = ip.split(':');
        if (parts.length >= 4) return `${parts.slice(0, parts.length - 4).join(':')}:xxxx:xxxx:xxxx:xxxx`;
    }
    return ip;
}

function isTelegramEnabled(env) {
    return !!(env.TG_BOT_TOKEN && env.TG_CHANNEL_ID);
}

export default {
    async fetch(request, env) {
        if (request.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
        
        const auth = request.headers.get('Authorization');
        if (!auth || auth !== `Bearer ${env.API_SECRET}`) return new Response('Unauthorized', { status: 401 });

        let body;
        try {
            body = await request.json();
        } catch (e) {
            return new Response('Invalid JSON', { status: 400 });
        }
        
        const { prefix, ip, type = 'A', ttl, zone_name, node_name } = body;
        if (!prefix || !ip || !zone_name) return new Response('Missing required fields', { status: 400 });

        const recordType = (type.toUpperCase() === 'AAAA') ? 'AAAA' : 'A';
        const recordTTL = ttl || parseInt(env.DEFAULT_TTL) || 1;
        const fullRecordName = `${prefix}.${zone_name}`;

        // === 修改重点：使用 API Token 的 Headers ===
        const cfHeaders = {
            'Authorization': `Bearer ${env.CF_DNS_API_TOKEN}`, // 使用新的 Token 变量
            'Content-Type': 'application/json'
        };

        // 1. 获取 Zone ID
        let zoneId = env.CF_ZONE_ID;
        if (!zoneId) {
            const zoneResp = await fetch(`https://api.cloudflare.com/client/v4/zones?name=${zone_name}`, {
                headers: cfHeaders
            });
            const zoneData = await zoneResp.json();
            if (!zoneData.success || zoneData.result.length === 0) {
                return new Response(`Zone not found: ${zone_name}`, { status: 404 });
            }
            zoneId = zoneData.result[0].id;
        }

        // 2. 查找现有记录
        const recordsResp = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records?type=${recordType}&name=${encodeURIComponent(fullRecordName)}`, {
            headers: cfHeaders
        });
        const recordsData = await recordsResp.json();
        const existingRecordId = (recordsData.success && recordsData.result.length > 0) ? recordsData.result[0].id : null;

        // 3. 创建或更新
        const endpoint = existingRecordId 
            ? `https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${existingRecordId}`
            : `https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records`;
        
        const method = existingRecordId ? 'PUT' : 'POST';
        const payload = {
            type: recordType,
            name: fullRecordName,
            content: ip,
            ttl: recordTTL,
            proxied: false
        };

        const updateResp = await fetch(endpoint, {
            method: method,
            headers: cfHeaders,
            body: JSON.stringify(payload)
        });
        const updateData = await updateResp.json();

        if (!updateData.success) {
            return new Response(JSON.stringify({ success: false, errors: updateData.errors }), { 
                status: 500, 
                headers: { 'Content-Type': 'application/json' } 
            });
        }

        // 4. TG 通知
        const action = existingRecordId ? 'updated' : 'created';
        let tgStatus = 'disabled';
        if (isTelegramEnabled(env)) {
            const tgSuccess = await sendTelegramNotification(env, action, prefix, ip, node_name || DEFAULT_NODE_NAME);
            tgStatus = tgSuccess ? 'sent' : 'failed';
        }

        return new Response(JSON.stringify({
            success: true,
            action: action,
            record: updateData.result,
            telegram_notification: tgStatus
        }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });
    }
};

async function sendTelegramNotification(env, action, recordName, ip, nodeName) {
    try {
        const actionText = action === 'updated' ? '更新' : '创建';
        const displayIP = maskIPAddress(ip);
        const message = `🚀 DDNS
- 节点名称: ${nodeName}
- 记录变更: ${actionText}
- 记录名称: ${recordName}
- 新 IP: ${displayIP}`;

        const resp = await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                chat_id: env.TG_CHANNEL_ID,
                text: message,
                parse_mode: 'Markdown'
            })
        });
        const data = await resp.json();
        return data.ok;
    } catch (e) {
        console.error('TG Exception:', e);
        return false;
    }
}
