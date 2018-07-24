define g_docker::data::bind(
  Enum['present','absent'] $ensure = 'present',
  String $data_name,
  String $volume_name,
  String $bind_name = $title,
  Optional[Variant[String, Integer]] $user = undef,
  Optional[Variant[String, Integer]] $group = undef,
  Optional[String] $mode = undef
){
  $lv_name = "${data_name}_${volume_name}"
  $bind_path = "${::g_docker::data_path}/${data_name}/${volume_name}/${bind_name}"

  if $ensure == 'present' {
    file { $bind_path:
      ensure => $ensure?{
        'present' => directory,
        default => $ensure
      },
      backup => false,
      force => true,
      recurse => false,
      owner => $user,
      group => $group,
      mode => $mode
    }

    G_server::Volumes::Vol[$lv_name]
    ->File[$bind_path]
  }

  # when ensure=absent, volume would be already removed
  # so no Files need to be deleted
}
