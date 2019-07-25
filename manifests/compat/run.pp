define g_docker::compat::run(
  Enum['present', 'absent'] $ensure,
  String $image,
  Boolean $remove_container_on_stop = true,
  Boolean $remove_container_on_start = true,
  Variant[String,Array,Undef] $ports = [],
  Variant[String,Array[String],Undef] $extra_parameters = undef,
  Variant[String,Array] $net = 'bridge',
  Variant[String,Array,Undef] $env = [],
  Optional[String] $command = undef,
  Optional[Integer] $stop_wait_time = 0,
  String $after_create = '',
  Array[String] $depends = [],
  Boolean $remove_volume_on_start = false,
  Boolean $remove_volume_on_stop = false,
  Hash[String, String] $labels = {},
){
  $docker_command = $::docker::docker_command
  $sanitised_name = ::docker::sanitised_name($name)

  case $::facts['os']['family'] {
    'Gentoo': {
      $flags = docker_run_flags({
        env                   => any2array($env),
        extra_params          => any2array($extra_parameters),
        net                   => $net,
        ports                 => any2array($ports),
        labels                => $labels.map |$k, $v| { "${k}=${v}" }
      })
      $_depends = join(
        $depends.map|$i|{
          $sanitised_i = ::docker::sanitised_name($i)
          "${::g_docker::service_prefix}${sanitised_i}"
        },
        ' '
      )
      $conf_d_content = epp('g_docker/service/gentoo.conf.d.epp', {
        'before_start'                   => '',
        'remove_container_on_start'      => $remove_container_on_start,
        'remove_container_start_options' => $remove_volume_on_start?{ true => '-v', default => ''},
        'pull_on_start'                  => false,
        'image' => $image,
        'flags' => $flags,
        'docker_command' => $::g_docker::docker_command,
        'after_create' => $after_create,
        'stop_wait_time' => $stop_wait_time,
        'remove_container_on_stop' => $remove_container_on_stop,
        'remove_container_stop_options' => $remove_volume_on_stop?{ true => '-v', default => ''},
        'before_stop' => '',
        'command' => $command,
        'deps' => $_depends
      })
      file { "/etc/init.d/${::g_docker::service_prefix}${sanitised_name}":
        ensure => link,
        target => '/etc/init.d/docker-service',
        notify => Service["${::g_docker::service_prefix}${sanitised_name}"]
      }
      file { "/etc/conf.d/${::g_docker::service_prefix}${sanitised_name}":
        ensure  => $ensure,
        content => $conf_d_content,
        notify  => Service["${::g_docker::service_prefix}${sanitised_name}"]
      }
      service { "${::g_docker::service_prefix}${sanitised_name}":
        ensure  => 'running',
        enable  => true,
        require => [Service['docker'], File['/etc/init.d/docker-service']]
      }
    }
    default: {
      docker::run { $name:
        ensure                    => $ensure,
        image                     => $image,
        remove_container_on_stop  => $remove_container_on_stop,
        remove_container_on_start => $remove_container_on_start,
        ports                     => $ports,
        extra_parameters          => $extra_parameters,
        net                       => $net,
        env                       => $env,
        command                   => $command,
        stop_wait_time            => $stop_wait_time,
        service_prefix            => $::g_docker::service_prefix,
        after_create              => $after_create,
        depends                   => $depends,
      }
    }
  }
}
