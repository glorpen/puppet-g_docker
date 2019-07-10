# @summary Setups Docker.
#
# @param [String] data_vg_name
#   LVM volume group to use for container persistent data.
# @param data_path
#   Directory where persistent data volumes will be mounted.
# @param runtime_config_path
#   Directory for runtime configuration files.
# @param instances
#   Containers to create (uses g_docker::run).
# @param registries
#   Registries to log in (uses docker::registry).
# @param insecure_registries
#   Names of registries to mark as insecure.
# @param ipv6_cidr
#   IPv6 subnet to use.
# @param networks
#   Manages docker networks (uses g_docker::network).
# @param auto_prune
#   Creates cron job to prune images/containers/data volumes not used for given time.
# @param auto_prune_options
#   Cron options for prune job
# @param docker_data_path
#   Docker data dir, defaults to `/var/lib/docker`.
# @param service_prefix
#   Prefix to use for created services, defaults to `docker-`.
# @param log_driver
#   Logging driver, defaults to `syslog`.
# @param log_level
#   Log level, one of 'debug', 'info', 'warn', 'error', 'fatal', defaults to `info`.
# @param log_options
#   Log driver specific options.
# @param tcp_bind
#   Bind docker daemon to given tcp host:port.
# @param socket_bind
#   Docker socket path, defaults to `/var/run/docker.sock`.
# @param version
#   Docker engine version, defaults to 'present'.
#
class g_docker(
  String $data_vg_name,
  String $data_path = '/mnt/docker',
  String $runtime_config_path = '/etc/docker/config.d',
  Hash $instances = {},
  Hash $registries = {},
  Optional[String] $ipv6_cidr = undef,
  Hash $networks = {},
  Array[String] $insecure_registries = [],
  Optional[String] $auto_prune = '24h',
  Hash $auto_prune_options = {
    'hour'    => '*/4',
    'minute'  => 0,
  },
  String $docker_data_path = '/var/lib/docker',
  String $service_prefix = 'docker-',
  String $log_driver = 'syslog',
  Enum['debug', 'info', 'warn', 'error', 'fatal'] $log_level = 'info',
  Hash[String, String] $log_options = {},
  Variant[String,Array[String],Undef] $tcp_bind = undef, #host:port
  Optional[String] $socket_bind = '/var/run/docker.sock',
  String $version = 'present',
  Optional[String] $export_metrics = undef
){

  include stdlib

  if $::facts["g_docker"]["installed"] {
    $_ver = $::facts["g_docker"]["version"]
    # remove leading zeros from version and split engine type 
    $_version_parts = split(regsubst($_ver, /\.0+([0-9])/, '.\1', 'G'), /-/)
    $installed_version = SemVer($_version_parts[0])
    $installed_version_symbol = $_version_parts[1]?{
      undef   => 'ce',
      default => $_version_parts[1]
    }
  } else {
    $installed_version = undef
    $installed_version_symbol = undef
  }

  contain g_docker::firewall
  if $::g_docker::firewall::helper != undef {
    include $::g_docker::firewall::helper

    Class[::g_docker::firewall]
    ->Class[$::g_docker::firewall::helper]
  }

  contain g_docker::storage
  if $::g_docker::storage::helper != undef {
    include $::g_docker::storage::helper

    Class[::g_docker::storage]
    ->Class[$::g_docker::storage::helper]
  }

  file { $data_path:
    ensure       => directory,
    backup       => false,
    force        => true,
    purge        => true,
    recurse      => true,
    recurselimit => 2 # /mnt/docker/<container name>/<bind name>
  }

  file { $runtime_config_path:
    ensure  => directory,
    backup  => false,
    force   => true,
    purge   => true,
    recurse => true,
    require => Class['docker']
  }

  if $ipv6_cidr == undef {
    $_docker_ipv6_params = []
  } else {
    $_docker_ipv6_params = ['--ipv6', '--fixed-cidr-v6', $ipv6_cidr]
  }
  $_docker_insecure_reg_params = $insecure_registries.map | $n | {
    "--insecure-registry ${n}"
  }

  if $export_metrics {
    $_docker_metrics_params = ['--experimental', "--metrics-addr=${export_metrics}"]
  } else {
    $_docker_metrics_params = []
  }

  $_docker_params = concat(['--userland-proxy=false'], $_docker_ipv6_params, $_docker_insecure_reg_params, $_docker_metrics_params)

  case $::facts['os']['name'] {
    'Centos': {
      $_repo_location = "https://download.docker.com/linux/centos/${::operatingsystemmajrelease}/\$basearch/stable"
      $_repo_key = 'https://download.docker.com/linux/centos/gpg'
    }
    'Fedora': {
      $_repo_location = "https://download.docker.com/linux/fedora/${::operatingsystemmajrelease}/\$basearch/stable"
      $_repo_key = 'https://download.docker.com/linux/fedora/gpg'
    }
    default: {
      $_repo_location = undef
      $_repo_key = undef
    }
  }

  $opt_bind_socket = $socket_bind?{
    undef   => undef,
    default => "unix://${socket_bind}"
  }
  $opt_bind_tcp = $tcp_bind?{
    undef   => undef,
    default => any2array($tcp_bind).map |$v| { "tcp://${v}" }
  }

  class { 'docker':
    docker_ce_source_location => $_repo_location,
    docker_ce_key_source      => $_repo_key,
    version                   => $version,
    extra_parameters          => $_docker_params,
    ip_forward                => true,
    root_dir                  => $docker_data_path,
    log_level                 => $log_level,
    log_driver                => $log_driver,
    log_opt                   => $log_options.map |$k, $v| { "${k}=${v}" },
    socket_bind               => $opt_bind_socket,
    tcp_bind                  => $opt_bind_tcp,
    *                         => $::g_docker::firewall::docker_config + $::g_docker::storage::docker_config
  }

  create_resources(::g_docker::run, $instances)
  create_resources(::docker::registry, $registries)
  create_resources(::g_docker::network, $networks)

  $prune_script = '/usr/local/bin/g-docker-prune'

  $_autoprune_ensure = $auto_prune?{
    undef   => 'absent',
    default => 'file'
  }
  file { $prune_script:
    ensure  => $_autoprune_ensure,
    content => epp('g_docker/prune.sh.epp', {
      'interval' => $auto_prune
    }),
    mode    => 'u=rwx,go=rx'
  }

  if $auto_prune != undef {
    include cron
    # prune unused docker data
    cron::job { 'g_docker-auto-prune':
      require => File[$prune_script],
      command => $prune_script,
      user    => 'root',
      *       => $auto_prune_options
    }
  }
}
