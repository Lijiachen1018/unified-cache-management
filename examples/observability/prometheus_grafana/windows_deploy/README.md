# UCM Prometheus + Grafana 部署工具（for Windows PC）

一键将 Prometheus + Grafana 监控栈部署到远程服务器。


## 打包成独立 exe

### 运行编译脚本
在 windows pc，到 ` examples/observability/prometheus_grafana/windows_deploy/` 目录下找到
```bat
build.bat
```
双击即可自动编译，输出到项目根目录 `dist/UCMObsDeploy.exe`。

## 一键部署 Grafana + Prometheus 可视化界面

在 windows pc 上打开 `dist/UCMObsDeploy.exe`，连接到远程服务器，并填写关键信息，一键部署
- 填写远程服务器 SSH 连接信息 (主机、端口、用户名、密码)
- 点击 "连接测试" 确认连接正常
- 确认容器镜像名称是否正确 (自动从 `docker-compose.yaml` 读取)
- 填写 vLLM 服务地址 (每行一个, `host:port` 格式)
- 点击 "开始部署"
- 部署成功后会自动显示 Grafana 访问地址，账号密码


## 访问
打开网页浏览器，输入 Grafana 访问地址（登录提示修改密码），运行推理测试后等待几分钟，即可查看指标