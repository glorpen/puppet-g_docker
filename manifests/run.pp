# @summary Creates docker system services
#
# @param ensure
#   Create or remove service.
# @param init
#   Run an init inside the container.
# @param localtime
#   Mount /etc/localtime inside container.
#
define g_docker::run(
  String $image,
  Enum['present','absent'] $ensure = 'present',
  Hash[String, Hash] $volumes = {},
  Hash[Stdlib::AbsolutePath, Hash] $mounts = {},
  Hash $ports = {},
  Array[Variant[String,Hash]] $networks = [],
  Array[String] $capabilities = [],
  String $network = 'bridge',
  Hash[String, Variant[String, Integer]] $env = {},
  Variant[String, Array[String]] $args = [],
  Integer $stop_wait_time = 10,
  Array[String] $depends_on = [],
  Optional[Array[Variant[String, Integer], 2, 2]] $user = undef,
  Boolean $localtime = true,
  Hash[String, String] $hosts = {},
  Hash[String, Hash] $runtime_configs = {},
  Enum['HUP','USR1', 'USR2'] $reload_signal = 'HUP',
  Hash[String, String] $labels = {},
  Array[String] $devices = [],
  Boolean $init = false
){

  include ::g_docker

  $docker_command = $::docker::docker_command
  $sanitised_name = ::docker::sanitised_name($name)

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

  g_docker::runtime_config { $name:
    ensure        => $ensure,
    reload_signal => $reload_signal,
    require       => Class['docker']
  }

  if $ensure == 'present' {
    # when absent should be cleaned by parent dir
    $config_volumes = $runtime_configs.map |$group_name, $group| {
      $group_config = $group - 'target'
      g_docker::runtime_config::group { "${name}:${group_name}":
        container  => $name,
        group_name => $group_name,
        *          => $group_config
      }
      $group_path = "${::g_docker::runtime_config_path}/${sanitised_name}/${group_name}"
      # mount dirs only, since puppet replaces single file and changes inode so it will not update on container side
      g_docker::mount_options('bind', "${group_path}/", $group['target'], true)
    }
  } else {
    $config_volumes = []
  }

  $docker_ports = $ports.map | $host_port_info, $container_port | {
    if ($host_port_info =~ G_docker::PortRange) {
      $_protocol = 'tcp'
      $_host_port = $host_port_info
    } else {
      $_port_info = split($host_port_info,'/')
      $_protocol = $_port_info[1]?{
        undef => 'tcp',
        default => $_port_info[1]
      }
      $_host_port = $_port_info[0]
    }

    $_container_port_info = $container_port?{
      String => split($container_port, '/'),
      default => [$container_port]
    }
    $_container_port = $_container_port_info[0]
    $_port_side = $_container_port_info[1]?{
      undef => 'internal',
      default => $_container_port_info[1]
    }

    if $::g_docker::firewall::run_type != undef {
      create_resources($::g_docker::firewall::run_type, {
        "${name}:${_host_port}:${_protocol}" => {
          'ensure'       => $ensure,
          'host_port'    => $_host_port,
          'protocol'     => $_protocol,
          'host_network' => $network == 'host',
          'port_side'    => $_port_side
        }
      })
    }
    "${_host_port}:${container_port}/${_protocol}"
  }

  $network_commands = $networks.map | $v | {
    if ($v =~ String) {
      G_docker::Network[$v]->G_docker::Compat::Run[$name]
      "/usr/bin/${docker_command} network connect '${v}' '${sanitised_name}'"
    } else {
      G_docker::Network[$v['name']]->G_docker::Compat::Run[$name]
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

  if $init {
    $_params_init = ['--init']
  } else {
    $_params_init = []
  }

  $_extra_parameters = concat(
    $_params_caps,
    $devices.map | $v | { "    --device ${v}" },
    concat($docker_volumes, $docker_mounts, $config_volumes, $localtime_mount).map | $v | {
      "    --mount ${v}"
    },
    $hosts.map | $k, $v | {
      "    --add-host ${k}:${v}"
    },
    $_user_parameters,
    $_params_init
  )

  $_data_ensure = $volumes.empty?{
    true    => absent,
    default => $ensure
  }
  g_docker::data { $name:
    ensure  => $_data_ensure,
    volumes => $volumes
  }

  $_safe_env = $env.map | $k, $v | {
    $_escaped_v = regsubst(
        String($v),
        '("|\'|\\$|\\\\)',
        '\\\\\1',
        'G'
    )
    "${k}=${_escaped_v}"
  }

  g_docker::compat::run { $name:
    ensure                    => $ensure,
    image                     => $image,
    remove_container_on_stop  => true,
    remove_container_on_start => true,
    remove_volume_on_start    => true,
    remove_volume_on_stop     => true,
    ports                     => $docker_ports,
    extra_parameters          => $_extra_parameters,
    net                       => $network,
    env                       => $_safe_env,
    command                   => $_image_command,
    stop_wait_time            => $stop_wait_time,
    after_create              => $network_commands.join("\n"),
    depends                   => $depends_on,
    labels                    => $labels
  }

  if $ensure == 'present' {
    G_docker::Compat::Run[$depends_on]
    ->G_docker::Compat::Run[$name]

    G_docker::Data[$name]
    ->G_docker::Compat::Run[$name]
  } else {
    G_docker::Compat::Run[$name]
    ->G_docker::Data[$name]

    G_docker::Compat::Run[$name]
    ->G_docker::Compat::Run[$depends_on]
  }
}
