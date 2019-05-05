define g_docker::runtime_config::group(
  String $container,
  String $group_name = $name,
  Hash[String, Hash] $configs = {},
  Optional[String] $source = undef
){
  $sanitised_name = ::docker::sanitised_name($container)
  $group_relative_path = "${sanitised_name}/${group_name}"
  $group_path = "${::g_docker::runtime_config_path}/${group_relative_path}"

  file { $group_path:
    ensure => directory,
    source => $source
  }

  if ! $source {
    $configs.each |$config_name, $config| {
      g_docker::runtime_config::config { "${container}:${group_name}:${config_name}":
        require   => [Class['docker'], File[$group_path]],
        container => $container,
        group     => $group_name,
        filename  => $config_name,
        *         => $config
      }
    }
  }
}
