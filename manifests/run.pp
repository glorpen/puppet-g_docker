define g_docker::run(
  Hash $volumes = {},
  String $image,
  Hash $ports = {}
){
  
  include ::g_docker
  
  $docker_volumes = flatten($volumes.map | $data_name, $data_config | {
    $data_config['binds'].map | $bind_name, $bind_path | {
      "${::g_docker::data_path}/${name}/${data_name}/${bind_name}:${bind_path}:rw"
    }
  })
  
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
    volumes => $docker_volumes,
    ports => $docker_ports
  }
}
