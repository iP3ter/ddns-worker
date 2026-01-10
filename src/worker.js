const HIDE_IP_SEGMENTS = true; // 设置为true时，隐藏IP的C段和D段（最后两段）
const DEFAULT_NODE_NAME = "未知节点"; // 默认节点名称

function maskIPAddress(ip) {
    if (!HIDE_IP_SEGMENTS) {
        return ip;
    }
    
    if (ip.includes('.')) {
        const segments = ip.split('.');
        if (segments.length === 4) {
            return `${segments[0]}.${segments[1]}.x.x`;
        }
    }
    
    if (ip.includes(':')) {
        const segments = ip.split(':');
        if (segments.length >= 4) {
            const visiblePart = segments.slice(0, segments.length - 4).join(':');
            return `${visiblePart}:xxxx:xxxx:xxxx:xxxx`;
        }
    }
    
    return ip;
}

// 检查 Telegram 是否已配置
function isTelegramEnabled(env) {
    return !!(env.TG_BOT_TOKEN && env.TG_CHANNEL_ID);
}

export default {
    async fetch(request, env){
        if(request.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });

        const auth = request.headers.get('Authorization');
        if(!auth || auth !== `Bearer ${env.API_SECRET}`) return new Response('Unauthorized', { status: 401 });
  
        const { prefix, ip, type = 'A', ttl, zone_name, node_name } = await request.json();
        
        if(!prefix || !ip) return new Response('Bad Gateway: prefix and ip are required', { status: 400 });
        const recordType = (type.toUpperCase() === 'AAAA') ? 'AAAA' : 'A';
        
        const recordTTL = ttl || parseInt(env.DEFAULT_TTL) || 1;

        const fullRecordName = `${prefix}.${zone_name}`;

        let recordId = null;
        let zoneId = env.CF_ZONE_ID;
        if(zoneId == null){
            const Api = 'https://api.cloudflare.com/client/v4/zones?name=' + (zone_name);
            const response = await fetch(Api, {
                headers: {
                'X-Auth-Email': env.CF_API_EMAIL,
                'X-Auth-Key': env.CF_API_KEY,
                'Content-Type': 'application/json'
                }
            });
            const data = await response.json();
            zoneId = data.result[0].id;
        }

        const recordsUrl = `https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records?type=${recordType}&name=${encodeURIComponent(fullRecordName)}`;
        
        const recordsResponse = await fetch(recordsUrl, {
            headers: {
                'X-Auth-Email': env.CF_API_EMAIL,
                'X-Auth-Key': env.CF_API_KEY,
                'Content-Type': 'application/json'
            }
        });
  
        const recordsData = await recordsResponse.json();
        
        if(recordsData.success && recordsData.result.length > 0){
            recordId = recordsData.result[0].id;
        }

        const endpoint = recordId 
          ? `https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records/${recordId}`
          : `https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records`;
        
        const method = recordId ? 'PUT' : 'POST';
        
        const recordData = {
            type: recordType,
            name: fullRecordName,
            content: ip,
            ttl: recordTTL,
            proxied: false
        };
        
        if(recordId) recordData.id = recordId;
  
        const cfResponse = await fetch(endpoint, {
            method: method,
            headers: {
                'X-Auth-Email': env.CF_API_EMAIL,
                'X-Auth-Key': env.CF_API_KEY,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(recordData)
        });
  
        const cfData = await cfResponse.json();

        if(!cfData.success)
            return new Response(JSON.stringify({
                success: false,
                errors: cfData.errors
            }), {
                status: 500,
                headers: { 'Content-Type': 'application/json' }
            });
        
        const action = recordId ? 'updated' : 'created';
        const nodeName = node_name || DEFAULT_NODE_NAME;
        
        // 只有配置了 Telegram 才发送通知
        let telegramSent = false;
        if (isTelegramEnabled(env)) {
            telegramSent = await sendTelegramNotification(env, action, prefix, ip, nodeName);
        }

        return new Response(JSON.stringify({
            success: true,
            action: recordId ? 'updated' : 'created',
            record: cfData.result,
            telegram_notification: isTelegramEnabled(env) ? (telegramSent ? 'sent' : 'failed') : 'disabled'
        }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}

async function sendTelegramNotification(env, action, recordName, ip, nodeName) {
    try {
        if(action == 'updated') action = '更新';
        else action = '创建';
        
        // 根据配置决定是否隐藏IP的最后两段
        const displayIP = maskIPAddress(ip);
        
        const message = `🚀 CCB-DDNS
- 节点名称: ${nodeName}
- 记录变更: ${action.toUpperCase()}
- 记录名称: ${recordName}
- 新 IP: ${displayIP}`;

        const telegramUrl = `https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`;
        const response = await fetch(telegramUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                chat_id: env.TG_CHANNEL_ID, 
                text: message,
                parse_mode: 'Markdown'
            })
        });

        const data = await response.json();
        if (!data.ok) {
            console.error('TG Error:', data);
            return false;
        }
        return true;
    } catch (error) {
        console.error('TG Exception:', error);
        return false;
    }
}
