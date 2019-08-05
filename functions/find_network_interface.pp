function g_docker::find_network_interface(
  String $name
) >> String {
  $net_config = g_docker::find_network_config($name)

  if $net_config {
    if $net_config['options']['com.docker.network.bridge.name'] {
      $iface = $net_config['options']['com.docker.network.bridge.name']
    } else {
      $iface = "br-${net_config['id'][0,12]}"
    }
    $iface
  }
}
