define g_docker::firewall::native_run(
  $host_port,
  $protocol
){
  g_firewall::ipv6 { "200 docker publish ${name}/${protocol}":
    dport => $host_port,
    proto => $protocol
  }
}
