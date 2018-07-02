define g_docker::run(
  Enum['present','absent'] $ensure = 'present',
  Hash $volumes = {},
  Hash $mounts = {},
  String $image,
  Hash $ports = {},
  Optional[String] $puppetizer_config = undef,
  Array[Variant[String,Hash]] $networks = [],
  Array[String] $capabilities = [],
  String $network = 'bridge',
  Hash $env = {},
  Variant[String, Array[String]] $args = [],
  Integer $stop_wait_time = 10
){
  
  include ::g_docker
  
  $docker_command = $::docker::docker_command
  
  # TODO: make function
  $docker_volumes = $volumes.map | $data_name, $data_config | {
    $data_config['binds'].map | $bind_name, $bind_conf | {
      g_docker::mount_options(
        'bind',
        "${::g_docker::data_path}/${name}/${data_name}/${bind_name}",
        $bind_conf['path'],
        $bind_conf['readonly'],
        $bind_conf['propagation']
      )
    }
  }.flatten
  
  $docker_mounts = $mounts.map | $container_path, $mount_conf | {
    g_docker::mount_options(
      $mount_conf['type'],
      $mount_conf['source'],
      $container_path,
      $mount_conf['readonly'],
      $mount_conf['propagation']
    )
  }
  
  if $puppetizer_config == undef {
    $puppetizer_volumes = []
  } else {
    $puppetizer_runtime_dir = "${::g_docker::puppetizer_conf_path}/${name}"
    $puppetizer_runtime = "${puppetizer_runtime_dir}/runtime.yaml"
    file { $puppetizer_runtime_dir:
      ensure => $ensure?{
        'present' => 'directory',
        default => 'absent',
      },
      recurse => true,
      backup => false,
      force => true
    }->
    file { $puppetizer_runtime:
      ensure => $ensure,
      source => $puppetizer_config,
      require => File[$::g_docker::puppetizer_conf_path],
    }~>
    # run puppet apply when config changed
    exec { "puppetizer runtime apply for docker-${name}":
      require => Docker::Run[$name],
      refreshonly => true,
      tries => 3,
      command => "/usr/bin/${docker_command} exec '${name}' /bin/sh -c 'test -f /var/opt/puppetizer/initialized && (/opt/puppetizer/bin/apply; exit $?); exit 0'"
    }
    $puppetizer_volumes = [
      g_docker::mount_options('bind', $puppetizer_runtime_dir, '/var/opt/puppetizer/hiera', true)
    ]
  }
  
  $docker_ports = $ports.map | $host_port_info, $container_port | {
    if ($host_port_info =~ Integer) {
      $_protocol = 'tcp'
      $_host_port = $host_port_info
    } else {
      $_port_info = split($host_port_info,'/')
      $_protocol = $_port_info[1]?{
        undef => 'tcp',
        default => $_port_info[1]
      }
      $_host_port = Integer($_port_info[0])
    }
    
    create_resources("${::g_docker::firewall_base}_run", {
      "${name}:${_host_port}:${_protocol}" => {
        'ensure' => $ensure,
        'host_port' => $_host_port,
        'protocol' => $_protocol,
        'host_network' => $network == 'host'
      }
    })
    "${_host_port}:${container_port}/${_protocol}"
  }
  
  $network_commands = $networks.map | $v | {
    if ($v =~ String) {
      G_docker::Network[$v]->Docker::Run[$name]
      "/usr/bin/${docker_command} network connect '${v}' '${name}'"
    } else {
      G_docker::Network[$v['name']]->Docker::Run[$name]
      $options = delete_undef_values([
        if $v['alias'] { "--alias '${v['alias']}'" },
        if $v['ip'] { "--ip '${v['ip']}'" },
        if $v['ip6'] { "--ip6 '${v['ip6']}'" }
      ]).join(' ')
      "/usr/bin/${docker_command} network connect ${options} '${v['name']}' '${name}'"
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
  
  $_params_caps = $capabilities.map | $v | {
    "--cap-add ${v}"
  }
  
  $_image_command = if ($args =~ String) {
    $args
  } else {
    $args.join(' ')
  }
  
  $_extra_parameters = concat(
    $_params_caps,
    concat($docker_volumes, $docker_mounts, $puppetizer_volumes).map | $v | {
      "\\\n    --mount ${v}"
    }
  )
  
  g_docker::data { $name:
    ensure => $volumes.empty?{
      true => absent,
      default => $ensure
    },
    volumes => $volumes
  }
  docker::run { $name:
    ensure => $ensure,
    image   => $image,
    remove_container_on_stop => true,
    remove_container_on_start => false, # so "docker create" command will be run
    ports => $docker_ports,
    extra_systemd_parameters => $systemd_params,
    extra_parameters => $_extra_parameters,
    net => $network,
    env => $env.map | $k, $v | {
      "${k}=${v}"
    },
    command => $_image_command,
    stop_wait_time => $stop_wait_time
  }
  
  if $ensure == 'present' {
    G_docker::Data[$name]
    ->Docker::Run[$name]
  } else {
    Docker::Run[$name]
    ->G_docker::Data[$name]
  }
}
