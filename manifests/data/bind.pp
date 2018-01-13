define g_docker::data::bind(
  Enum['present','absent'] $ensure = 'present',
  String $data_name,
  String $volume_name,
  String $bind_name = $title
){
  $lv_name = "${data_name}_${volume_name}"
  file { "${::g_docker::data_path}/${data_name}/${volume_name}/${bind_name}":
    ensure => $ensure?{
      'present' => directory,
      default => $ensure
    },
    backup => false,
    force => true,
    require => G_server::Volumes::Vol[$lv_name],
  }
}
