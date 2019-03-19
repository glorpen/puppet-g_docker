class g_docker(
  Enum['noop','native','script'] $firewall_mode = 'noop',
  String $data_path = '/mnt/docker',
  String $basesize,
  String $vg_name,
  String $thinpool_name = 'docker-thin',
  String $thinpool_size,
  String $thinpool_metadata_size,
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
){
  
  include ::stdlib
  
  if $::facts["g_docker"]["installed"] {
    $_ver = $::facts["g_docker"]["version"]
    # remove leading zeros from version and split engine type 
    $_version_parts = split(regsubst($_ver, /\.0+([0-9])/, '.\1', 'G'), /-/)
    $version = SemVer($_version_parts[0])
    $version_symbol = $_version_parts[1]?{
      undef => 'ce',
      default => $_version_parts[1]
    }
  } else {
    $version = undef
    $version_symbol = undef
  }
  
  $firewall_base = "::g_docker::firewall::${firewall_mode}"
  contain $firewall_base

  $puppetizer_conf_path = '/etc/docker/puppetizer.conf.d'
  $_vol_name = regsubst($thinpool_name, '-', '--', 'G')
  $_vg_name = regsubst($vg_name, '-', '--', 'G')

  file { $data_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true,
    recurselimit => 2 # /mnt/docker/<container name>/<bind name>
  }
  
  file { $puppetizer_conf_path:
    ensure => directory,
    backup => false,
    force => true,
    purge => true,
    recurse => true,
    require => Class[::docker]
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
    'Centos' : {
      $_repo_location = "https://download.docker.com/linux/centos/${::operatingsystemmajrelease}/\$basearch/stable"
      $_repo_key = "https://download.docker.com/linux/centos/gpg"
    }
    'Fedora' : {
      $_repo_location = "https://download.docker.com/linux/fedora/${::operatingsystemmajrelease}/\$basearch/stable"
      $_repo_key = "https://download.docker.com/linux/fedora/gpg"
    }
  }
  
  # /var/lib/docker -> mostly for volumes data
  g_server::volumes::thinpool { $thinpool_name:
    vg_name => $vg_name,
    size => $thinpool_size,
    metadata_size => $thinpool_metadata_size
  }->
  class { ::docker:
    docker_ce_source_location => $_repo_location,
    docker_ce_key_source => $_repo_key,
    log_driver => 'syslog',
    storage_driver => 'devicemapper',
    dm_basesize => $basesize,
    storage_vg => $vg_name,
    dm_thinpooldev => "/dev/mapper/${_vg_name}-${_vol_name}",
    dm_blkdiscard => true,
    
    extra_parameters => $_docker_params,
    ip_forward => true,
    * => getvar("${firewall_base}::docker_config")
  }
  
  create_resources(::g_docker::run, $instances)
  create_resources(::docker::registry, $registries)
  create_resources(::g_docker::network, $networks)
  
  $prune_script = '/usr/local/bin/g-docker-prune'

  file { $prune_script:
    ensure => $auto_prune?{
      undef => 'absent',
      default => 'file'
    },
    content => epp('g_docker/prune.sh.epp', {
      'interval' => $auto_prune
    }),
    mode => 'u=rwx,go=rx'
  }
  
  if $auto_prune != undef {
    # prune unused docker data
    cron { 'g_docker-auto-prune':
      require => File[$prune_script],
      command => $prune_script,
      user    => 'root',
      * => $auto_prune_options
    }
  }
  

}
