#!/bin/bash

# 加载 .env 文件中的环境变量
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# 显示进度条的函数
show_progress() {
  local progress=$1
  local total=$2
  local percent=$((progress * 100 / total))
  local filled=$((percent / 2))
  local empty=$((50 - filled))

  printf "\r[%-${filled}s%${empty}s] %d%%" "$(printf '#%.0s' $(seq 1 $filled))" "" "$percent"
  if [[ $progress -eq $total ]]; then
    echo ""
  fi
}

# 提取内网 IP 地址
#LOKI_HOST=$(hostname -I | awk '{print $1}')


# 检查容器是否存在
check_container_exists() {
  local name=$1
  docker ps -a --format '{{.Names}}' | grep -w $name > /dev/null
}

# 检查端口是否被占用
check_port_conflict() {
  local port=$1
  netstat -tuln | grep ":$port " > /dev/null
}

# 检查 docker-compose 文件是否存在
check_docker_compose_file() {
  if [ ! -f docker-compose.yml ]; then
    echo "错误: 未找到 docker-compose.yml 文件。请确保在正确的目录中。"
    exit 1
  fi
  if [ ! -f .env ]; then
    echo "错误: 未找到 .env 环境变量文件。请确保在正确的目录中。"
    exit 1
  fi
}

# 执行 Docker Compose 并检查错误
run_docker_compose() {
  local service=$1
  docker-compose up -d $service
  if [ $? -ne 0 ]; then
    echo "错误: 启动 $service 失败。请检查 Docker Compose 配置和网络连接。"
    exit 1
  fi
}

# 提示用户输入新的端口
prompt_for_port() {
  local service=$1
  local default_port=$2
  local new_port

#  echo "端口 $default_port 已被占用。请输入新的端口号（当前端口: $default_port）："
  read -e -p "检测到端口冲突,输入新的端口号(当前端口: $default_port): " new_port
  echo "$new_port"
}

# 删除容器
remove_container() {
  local name=$1
  echo "删除已存在的 $name 容器..."
  docker rm -f $name > /dev/null 2>&1
}

# 提示用户是否删除现有容器
prompt_for_action() {
  local name=$1
  echo ""
  echo "检测到 $name 容器已存在。请选择操作:"
  echo "y/Y: 跳过安装"
  echo "n/N: 删除容器并重新安装"
  read -e -p "输入选项: " choice
  case $choice in
    [yY])
      echo "$name 容器存在，跳过安装。"
      return 1
      ;;
    [nN])
      remove_container $name
      if check_port_conflict $port; then
      port=$(prompt_for_port "Grafana" $port)
      fi
      return 0
      ;;
    *)
      echo "无效选项，跳过安装。"
      return 1
      ;;
  esac
}

# 生成 Prometheus 配置文件
generate_prometheus_config() {
  if [ ! -d ./prometheus-config ];then
     mkdir ./prometheus-config
  fi
  cat <<EOF > ./prometheus-config/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 1m
  scrape_timeout: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets:
           - $PROMETHEUS_HOST:9093
rule_files:
   - "/usr/local/monitor/rule/*.yml"
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["$PROMETHEUS_HOST:9090"]
EOF
}

# 生成 Promtail 配置文件
generate_promtail_config() {
  if [ ! -d ./promtail-config ];then
     mkdir ./promtail-config
  fi
  cat <<EOF > ./promtail-config/promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0
				
positions:
  filename: /tmp/positions.yaml

clients:
  - url: "http://$LOKI_HOST:3100/loki/api/v1/push"

scrape_configs:
#收集系统日志，可以按需求更改为其它路径的日志文件
#- job_name: monitor-logs
#  static_configs:
#  - targets:
#      - localhost
#    labels:
#      job: monitor-logs
#      __path__: "/host/var/log/*.log"

#收集docker容器日志
- job_name: docker-containers-logs
  docker_sd_configs:
    - host: "unix:///host/var/run/docker.sock"  #注意这里的/host，是挂载宿主机的根目录
      refresh_interval: 5s
  relabel_configs:
    - source_labels: ['__meta_docker_container_name']
      target_label: '$PROMTAIL_TARGET_LABEL'  #区分开，方便标签查找
EOF
}

# 生成 Alertmanager 配置文件
generate_alertmanager_config() {
  if [ ! -d ./alertmanager-config ];then
     mkdir ./alertmanager-config
  fi
  cat <<EOF > ./alertmanager-config/alertmanager.yml
#global:
#  resolve_timeout: 5m
receivers:
- name: 'feishu-webhook'
  webhook_configs:
  - url: '$WEBHOOK_CONFIG'
route:
  group_by: ['alertname','job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 2h
  receiver: 'feishu-webhook'

inhibit_rules:
- source_match:
    severity: 'critical'
  target_match:
    severity: 'warning'
  equal: ['job','instance']
EOF
}

# 生成 loki 配置文件
generate_loki_config() {
  if [ ! -d ./loki-config ];then
     mkdir ./loki-config
  fi
  cat <<EOF > ./loki-config/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

query_range:
  results_cache:
    cache:
      embedded_cache:
        enabled: true
        max_size_mb: 100

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://$ALERTMANAGER_HOST:9093
EOF
}

# 安装 Grafana
install_grafana() {
  local name="grafana"
  local port=3000
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Grafana..."
#      docker run -d --name=grafana -p $port:3000 grafana/grafana:latest > /dev/null
       run_docker_compose grafana
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "Grafana" $port)
    fi
    echo "正在安装 Grafana..."
#    docker run -d --name=grafana -p $port:3000 grafana/grafana:latest > /dev/null
     run_docker_compose grafana
  fi
}

# 安装 Prometheus
install_prometheus() {
  local name="prometheus"
  local port=9090
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Prometheus..."
      generate_prometheus_config
#      docker run -d --name=prometheus -p $port:9090 -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus:latest > /dev/null
       run_docker_compose prometheus
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "Prometheus" $port)
    fi
    echo "正在安装 Prometheus..."
    generate_prometheus_config
 #   docker run -d --name=prometheus -p $port:9090 -v $(pwd)/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus:latest > /dev/null
     run_docker_compose prometheus
  fi
}

# 安装 Loki
install_loki() {
  local name="loki"
  local port=3100
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Loki..."
      generate_loki_config
  #    docker run -d --name=loki -p $port:3100 grafana/loki:latest > /dev/null
       run_docker_compose loki
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "Loki" $port)
      echo $port
    fi
    echo "正在安装 Loki..."
    generate_loki_config
#    docker run -d --name=loki -p $port:3100 grafana/loki:latest > /dev/null
     run_docker_compose loki
  fi
}

# 安装 Promtail
install_promtail() {
  local name="promtail"
  local port=9080
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Promtail..."
      generate_promtail_config
#      docker run -d --name=promtail -v $(pwd)/promtail.yml:/etc/promtail/promtail.yml -p $port:9080 grafana/promtail:latest > /dev/null
      run_docker_compose promtail
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$prompt_for_port
    fi
    echo "正在安装 Promtail..."
    generate_promtail_config
 #   docker run -d --name=promtail -v $(pwd)/promtail.yml:/etc/promtail/promtail.yml -p $port:9080 grafana/promtail:latest > /dev/null
    run_docker_compose promtail
  fi
}

# 安装 Node Exporter
install_node_exporter() {
  local name="node_exporter"
  local port=9100
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Node Exporter..."
#      docker run -d --name=node_exporter -p $port:9100 prom/node-exporter:latest > /dev/null
      run_docker_compose node_exporter
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "Node Exporter" $port)
    fi
    echo "正在安装 Node Exporter..."
#    docker run -d --name=node_exporter -p $port:9100 prom/node-exporter:latest > /dev/null
    run_docker_compose node_exporter
  fi
}

# 安装 cAdvisor
install_cadvisor() {
  local name="cadvisor"
  local port=8080
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 cAdvisor..."
#      docker run -d --name=cadvisor -p $port:8080 google/cadvisor:latest > /dev/null
      run_docker_compose cadvisor
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "cAdvisor" $port)
    fi
    echo "正在安装 cAdvisor..."
#    docker run -d --name=cadvisor -p $port:8080 google/cadvisor:latest > /dev/null
    run_docker_compose cadvisor
  fi
}

# 安装 alertmanager
install_alertmanager() {
  local name="alertmanager"
  local port=9093
  if check_container_exists $name; then
    if prompt_for_action $name; then
      echo "正在安装 Alertmanager..."
      generate_alertmanager_config
      run_docker_compose alertmanager
    else
      return  # 跳过安装
    fi
  else
    if check_port_conflict $port; then
      port=$(prompt_for_port "Alertmanager" $port)
    fi
    echo "正在安装 Alertmanager..."
#    docker run -d --name=cadvisor -p $port:8080 google/cadvisor:latest > /dev/null
    generate_alertmanager_config
    run_docker_compose alertmanager
  fi
}

# 显示菜单
show_menu() {
  echo "请选择要安装的组件（可以使用空格分隔多个选项）："
  echo "1. Grafana(监控可视化平台)"
  echo "2. Prometheus(数据收集)"
  echo "3. Loki(日志存储)"
  echo "4. Promtail(日志收集)"
  echo "5. Node Exporter(监控系统性能)"
  echo "6. cAdvisor(监控docker性能)"
  echo "7. Alertmanager(发送告警通知)"
  echo "0. 全部安装"
}

# 主函数
main() {
  check_docker_compose_file
  show_menu
  read -e -p "输入选项: " -a choices

  # 设置总进度
  total=${#choices[@]}
  progress=0

  for choice in "${choices[@]}"; do
    case $choice in
      1) if ! install_grafana; then continue; fi ;;
      2) if ! install_prometheus; then continue; fi ;;
      3) if ! install_loki; then continue; fi ;;
      4) if ! install_promtail; then continue; fi ;;
      5) if ! install_node_exporter; then continue; fi ;;
      6) if ! install_cadvisor; then continue; fi ;;
      7) if ! install_alertmanager; then continue; fi ;;
      0)
        for i in 1 2 3 4 5 6 7; do
          case $i in
            1) if ! install_grafana; then continue; fi ;;
            2) if ! install_prometheus; then continue; fi ;;
            3) if ! install_loki; then continue; fi ;;
            4) if ! install_promtail; then continue; fi ;;
            5) if ! install_node_exporter; then continue; fi ;;
            6) if ! install_cadvisor; then continue; fi ;;
            7) if ! install_alertmanager; then continue; fi ;;
          esac
        done
        ;;
      *)
        echo "无效选项: $choice" >&2
        continue
        ;;
    esac

    # 更新进度条
    progress=$((progress + 1))
    show_progress $progress $total
  done

  echo -e "\n所有安装操作完成！"
}

main
