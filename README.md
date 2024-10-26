 [原帖](https://www.nodeseek.com/post-29975-1)  [项目地址](https://github.com/LloydAsp/nfd)
 
 从@BotFather获取token，并且可以发送/setjoingroups来禁止此Bot被添加到群组
从uuidgenerator获取一个随机uuid作为secret
从@username_to_id_bot获取你的用户id
登录cloudflare，创建一个worker
配置worker的变量
增加一个ENV_BOT_TOKEN变量，数值为从步骤1中获得的token
增加一个ENV_BOT_SECRET变量，数值为从步骤2中获得的secret
增加一个ENV_ADMIN_UID变量，数值为从步骤3中获得的用户id
绑定kv数据库，创建一个Namespace Name为nfd的kv数据库，在setting -> variable中设置KV Namespace Bindings：nfd -> nfd
点击Quick Edit，复制这个文件到编辑器中
通过打开https://xxx.workers.dev/registerWebhook来注册websoket

 [魔改版](https://www.nodeseek.com/post-122678-1)  [项目地址](https://github.com/small-haozi/worker-SXbot.js)
需要添加一个 kv 空间名字为：FRAUD_LIST，并绑定到 workers
