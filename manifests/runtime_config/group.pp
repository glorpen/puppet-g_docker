define g_docker::runtime_config::group(
  String $container,
  String $group_name = $name,
  Hash[String, Hash] $configs = {},
  Optional[String] $source = undef,
  Boolean $source_reload = false
){

  assert_private()

  $sanitised_name = ::docker::sanitised_name($container)
  $container_path = "${::g_docker::runtime_config_path}/${sanitised_name}"
  $group_path = "${container_path}/${group_name}"

  file { $group_path:
    ensure       => directory,
    source       => $source,
    recurse      => true,
    backup       => false,
    force        => true,
    purge        => true,
    recurselimit => 1
  }

  if $source_reload {
    File[$group_path]
    ~>Exec["g_docker runtime config ${container}"]
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
