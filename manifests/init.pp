class g_docker(
  String $data_vg_name,
  String $data_path = '/mnt/docker',
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
  Hash[String, String] $runtime_configs = {},
  Boolean $puppetizer = false
){

  include stdlib

  if $::facts["g_docker"]["installed"] {
    $_ver = $::facts["g_docker"]["version"]
    # remove leading zeros from version and split engine type 
    $_version_parts = split(regsubst($_ver, /\.0+([0-9])/, '.\1', 'G'), /-/)
    $version = SemVer($_version_parts[0])
    $version_symbol = $_version_parts[1]?{
      undef   => 'ce',
      default => $_version_parts[1]
    }
  } else {
    $version = undef
    $version_symbol = undef
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

  $puppetizer_conf_path = '/etc/docker/puppetizer.conf.d'
  $runtime_conf_path = '/etc/docker/config.d'

  file { $data_path:
    ensure       => directory,
    backup       => false,
    force        => true,
    purge        => true,
    recurse      => true,
    recurselimit => 2 # /mnt/docker/<container name>/<bind name>
  }

  $_puppetizer_dir_ensure = $puppetizer?{
    true    => directory,
    default => absent
  }
  file { $puppetizer_conf_path:
    ensure  => $_puppetizer_dir_ensure,
    backup  => false,
    force   => true,
    purge   => true,
    recurse => true,
    require => Class['docker']
  }

  file { $runtime_conf_path:
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

  $_docker_params = concat(['--userland-proxy=false'], $_docker_ipv6_params, $_docker_insecure_reg_params)

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

  class { 'docker':
    docker_ce_source_location => $_repo_location,
    docker_ce_key_source      => $_repo_key,
    log_driver                => 'syslog',

    extra_parameters          => $_docker_params,
    ip_forward                => true,
    root_dir                  => $docker_data_path,
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
    # prune unused docker data
    cron { 'g_docker-auto-prune':
      require => File[$prune_script],
      command => $prune_script,
      user    => 'root',
      *       => $auto_prune_options
    }
  }

  $runtime_configs.each | $name, $source | {
    file { "${runtime_conf_path}/${name}":
      ensure => 'present',
      source => $source
    }
  }
}
