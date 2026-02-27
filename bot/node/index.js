// 1. 设置密钥与加盐 (请将引号内的内容修改为您自定义的字符串)
process.env.HOTUPDATE_SECRET = 'babama123	'; 
process.env.HOTUPDATE_SALT = 'babama100';

// 2. 设置服务器配置信息
process.env.SERVERS_JSON = '[{"host":"dynamic-8.magmanode.com","port":25756,"minBots":1,"maxBots":3,"version":"1.21.11"},{"host":"free.cloudblaze.org","port":20253,"minBots":1,"maxBots":3,"version":"1.21.10"}]';

// 3. 导入 mcbots 模块
const { initialize, shutdown } = require('@baipiaodajun/mcbots');

// 4. 初始化机器人
initialize().then(() => {
  console.log('mcbots start successed');
}).catch(err => {
  console.error('mcbots start fail:', err);
});

// 5. 监听系统信号以确保正常关闭
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);