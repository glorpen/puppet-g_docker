class g_docker::firewall::noop {
  $docker_config = {
    "iptables" => false,
    "ip_masq" => false
  }
}
