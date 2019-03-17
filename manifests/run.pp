define g_docker::run(
  Enum['present','absent'] $ensure = 'present',
  Hash[String, Hash] $volumes = {},
  Hash[Stdlib::Absolutepath, Hash] $mounts = {},
  String $image,
  Hash $ports = {},
  Optional[String] $puppetizer_config = undef,
  Array[Variant[String,Hash]] $networks = [],
  Array[String] $capabilities = [],
  String $network = 'bridge',
  Hash[String, Variant[String, Integer]] $env = {},
  Variant[String, Array[String]] $args = [],
  Integer $stop_wait_time = 10,
  Array[String] $depends_on = [],
  Optional[Array[Variant[String, Integer], 2, 2]] $user = undef,
  Boolean $localtime = true,
){
  
  include ::g_docker
  
  $docker_command = $::docker::docker_command
  $sanitised_name = ::docker::sanitised_name($name)
  $service_prefix = 'docker-'
  
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
  
  if $localtime {
    $localtime_mount = ['type=bind,source=/etc/localtime,destination=/etc/localtime,readonly']
  } else {
    $localtime_mount = []
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
    }
    
    if $ensure == 'present' {
      # run apply when yaml changed and service is not refreshing
      
      exec {"puppetizer runtime semaphore for ${service_prefix}${name}":
        require => File[$puppetizer_runtime],
        subscribe => Service["${service_prefix}${sanitised_name}"],
        refreshonly => true,
        path => '/bin:/usr/bin',
        command => "touch ${puppetizer_runtime}.lock"
      }
      
      # run puppet apply when config changed
      exec { "puppetizer runtime apply for ${service_prefix}${name}":
        require => Exec["puppetizer runtime semaphore for ${service_prefix}${name}"],
        subscribe => File[$puppetizer_runtime],
        tries => 3,
        logoutput => true,
        refreshonly => true,
        path => '/bin:/usr/bin',
        unless => "test -f ${puppetizer_runtime}.lock",
        command => "${docker_command} exec '${sanitised_name}' /bin/sh -ec 'if [ -f /var/opt/puppetizer/initialized ]; then /opt/puppetizer/bin/apply; fi'",
      }
      
      exec { "puppetizer runtime cleanup ${service_prefix}${name}":
        subscribe => [
          Exec["puppetizer runtime semaphore for ${service_prefix}${name}"],
          Exec["puppetizer runtime semaphore for ${service_prefix}${name}"]
        ],
        path => '/bin:/usr/bin',
        command => "rm ${puppetizer_runtime}.lock",
        refreshonly => true,
      }
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
      "/usr/bin/${docker_command} network connect '${v}' '${sanitised_name}'"
    } else {
      G_docker::Network[$v['name']]->Docker::Run[$name]
      $options = delete_undef_values([
        if $v['alias'] { "--alias '${v['alias']}'" },
        if $v['ip'] { "--ip '${v['ip']}'" },
        if $v['ip6'] { "--ip6 '${v['ip6']}'" }
      ]).join(' ')
      "/usr/bin/${docker_command} network connect ${options} '${v['name']}' '${sanitised_name}'"
    }
  }
  
  $_params_caps = $capabilities.map | $v | {
    "--cap-add ${v}"
  }
  
  $_image_command = if ($args =~ String) {
    $args
  } else {
    $args.join(' ')
  }
  
  if $user {
    if ($user[0] =~ String) {
      if (defined(User[$user[0]])) {
        User[$user[0]]->G_docker::Data[$name]
      }
      
      $_user_param_uid = "\$(id -u ${user[0]})"
    } else {
      $_user_param_uid = $user[0]
    }
    
    if ($user[1] =~ String) {
      if (defined(Group[$user[1]])) {
        Group[$user[1]]->G_docker::Data[$name]
      }
      $_user_param_gid = "\$(id -g ${user[1]})"
    } else {
      $_user_param_gid = $user[1]
    }
    
    $_user_parameters = ["\\\n    -u ${_user_param_uid}:${_user_param_gid}"]
  } else {
    $_user_parameters = []
  }
  
  $_extra_parameters = concat(
    $_params_caps,
    concat($docker_volumes, $docker_mounts, $puppetizer_volumes, $localtime_mount).map | $v | {
      "\\\n    --mount ${v}"
    },
    $_user_parameters
  )
  
  g_docker::data { $name:
    ensure => $volumes.empty?{
      true => absent,
      default => $ensure
    },
    volumes => $volumes,
    puppetized => $puppetizer_config != undef
  }
  
  $_safe_env = $env.map | $k, $v | {
    $_escaped_v = shell_escape(String($v))
    "${k}=${_escaped_v}"
  }
  
  docker::run { $name:
    ensure => $ensure,
    image   => $image,
    remove_container_on_stop => true,
    remove_container_on_start => true,
    ports => $docker_ports,
    extra_parameters => $_extra_parameters,
    net => $network,
    env => $_safe_env,
    command => $_image_command,
    stop_wait_time => $stop_wait_time,
    service_prefix => $service_prefix,
    after_create => $network_commands.join("\n"),
    depends => $depends_on
  }
  
  if $ensure == 'present' {
    G_docker::Run[$depends_on]
    ->G_docker::Data[$name]
    ->Docker::Run[$name]
  } else {
    Docker::Run[$name]
    ->G_docker::Data[$name]
    ->G_docker::Run[$depends_on]
  }
  
  
}
