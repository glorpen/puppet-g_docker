define g_docker::firewall::native_run(
  Integer $host_port,
  String $protocol,
  Boolean $host_network
){
  if $host_network {
    g_firewall { "200 docker publish ${name}":
      dport => $host_port,
      proto => $protocol,
      action => 'accept'
    }
  } else {
    g_firewall::ipv6 { "200 docker publish ${name}":
      dport => $host_port,
      proto => $protocol,
      action => 'accept'
    }
  }
}
