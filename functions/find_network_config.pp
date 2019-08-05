function g_docker::find_network_config(
  String $name
) >> Hash {
  $::facts['g_docker']['networks'].filter | $net_config | {
    $net_config['driver'] == 'bridge' and $net_config['name'] == $name
  }[0]
}
