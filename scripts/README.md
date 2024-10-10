# 脚本使用说明：
1. 文件说明
* .env
  存放环境变量
  默认变量说明：
  
  PROMETHEUS_HOST="172.31.40.254"  #prometheus地址
  
  LOKI_HOST="172.31.40.254"  #日志存储系统地址
  
  ALERTMANAGER_HOST="172.31.40.254"  #告警系统地址
  
  PROMTAIL_TARGET_LABEL="changeMe_container_name"  #自定义，日志推送标签，按服务器作用或主机名区分,必须要改。不然日志系统标签会重复
  
  WEBHOOK_CONFIG=""  #发送告警URL
  
* install.sh
  执行的脚本文件
  
* docker-compose.yml
  docker脚本文件
  
# 执行方式
* sh install.sh

# 功能使用说明
请选择要安装的组件（可以使用空格分隔多个选项）：
1. Grafana(监控可视化平台)
2. Prometheus(数据收集)
3. Loki(日志存储)
4. Promtail(日志收集)
5. Node Exporter(监控系统性能)
6. cAdvisor(监控docker性能)
7. Alertmanager(发送告警通知)
0. 全部安装


#通过选择不同的选项，安装不同的组件，多个组件安装，可以使用空格分割，例如：
请选择要安装的组件（可以使用空格分隔多个选项）：
1. Grafana(监控可视化平台)
2. Prometheus(数据收集)
3. Loki(日志存储)
4. Promtail(日志收集)
5. Node Exporter(监控系统性能)
6. cAdvisor(监控docker性能)
7. Alertmanager(发送告警通知)
0. 全部安装
输入选项: 1 2 3

# 执行脚本示例：
请选择要安装的组件（可以使用空格分隔多个选项）：
1. Grafana(监控可视化平台)
2. Prometheus(数据收集)
3. Loki(日志存储)
4. Promtail(日志收集)
5. Node Exporter(监控系统性能)
6. cAdvisor(监控docker性能)
7. Alertmanager(发送告警通知)
0. 全部安装
输入选项: 1

检测到 grafana 容器已存在。请选择操作:
y/Y: 跳过安装

n/N: 删除容器并重新安装

输入选项: n

删除已存在的 grafana 容器... 


正在安装 Grafana...

[+] Running 1/1

 ✔ Container grafana  Started                                                                                                                                                      0.4s 
[##################################################] 100%

所有安装操作完成！
