define g_docker::run(
  Hash $volumes = {},
  String $image,
  Hash $ports = {},
  Optional[String] $puppetizer_config = undef
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
      before => Docker::Run[$name]
    }
    $puppetizer_volumes = ["${runtime}:/var/opt/puppetizer/hiera/runtime.yaml:ro"]
  }
  
  $docker_ports = $ports.map | $host_port, $container_port | {
    "${host_port}:${container_port}"
  }
  
  g_docker::data { $name:
    volumes => $volumes
  }->
  docker::run { $name:
    image   => $image,
    remove_container_on_stop => true,
    remove_container_on_start => true,
    volumes => concat($docker_volumes, $puppetizer_volumes),
    ports => $docker_ports
  }
}
