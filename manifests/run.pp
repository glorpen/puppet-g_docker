define g_docker::run(
  Hash $volumes = {},
  String $image,
  Hash $ports = {},
  Optional[String] $puppetizer_config = undef,
  Array[Variant[String,Hash]] $networks = []
){
  
  include ::g_docker
  
  $docker_volumes = $volumes.map | $data_name, $data_config | {
    $data_config['binds'].map | $bind_name, $bind_conf | {
      $path = $bind_conf['path']
      $flag = $bind_conf['readonly']?{
        false => 'rw',
        default => 'ro'
      }
      "${::g_docker::data_path}/${name}/${data_name}/${bind_name}:${path}:${flag}"
    }
  }.flatten
  
  if $puppetizer_config == undef {
    $puppetizer_volumes = []
  } else {
    $runtime = "${::g_docker::puppetizer_conf_path}/${name}.yaml"
    file { $runtime:
      ensure => present,
      source => $puppetizer_config,
      require => File[$::g_docker::puppetizer_conf_path],
      notify => Docker::Run[$name]
    }
    $puppetizer_volumes = ["${runtime}:/var/opt/puppetizer/hiera/runtime.yaml:ro"]
  }
  
  $docker_ports = $ports.map | $host_port_info, $container_port | {
    $_port_info = split($host_port_info,'/')
    $_protocol = $_port_info[1]?{
      undef => 'tcp',
      default => $_port_info[1]
    }
    $_host_port = $_port_info[0]
    
    create_resources("${::g_docker::firewall_base}_run", {
      "${name}:${_host_port}:${_protocol}" => {
        'host_port' => $_host_port,
        'protocol' => $_protocol
      }
    })
    "${_host_port}:${container_port}/${_protocol}"
  }
  
  $docker_command = $::docker::docker_command
  
  $network_commands = $networks.map | $v | {
    # TODO: require g_docker::network ?
    if ($v =~ String) {
      "/usr/bin/${docker_command} network connect '${v}' '${name}'"
    } else {
      "/usr/bin/${docker_command} network connect --alias '${v['alias']}' '${v['name']}' '${name}'"
    }
  }
  
  if $network_commands {
    $other_commands = $network_commands[1,-1].reduce("") | $memo, $v | {
      "${memo}\nExecStartPre=-${v}"
    }
    $systemd_params = {
      'ExecStartPre' => "-${network_commands[0]}${other_commands}"
    }
  } else {
    $systemd_params = {}
  }
  
  g_docker::data { $name:
    volumes => $volumes
  }->
  docker::run { $name:
    image   => $image,
    remove_container_on_stop => true,
    remove_container_on_start => false, # so "docker create" command will be run
    volumes => concat($docker_volumes, $puppetizer_volumes),
    ports => $docker_ports,
    extra_systemd_parameters => $systemd_params
  }
}
