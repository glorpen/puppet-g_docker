function g_docker::mount_options(
  Optional[Enum['bind','volume','tmpfs']] $type,
  String $source,
  String $destination,
  Optional[Boolean] $readonly = undef,
  Optional[Enum['shared','slave','private','rshared','rslave','rprivate']] $propagation = undef
) >> String {
  $_readonly = $readonly?{
    true => ',readonly',
    default => ''
  }
  
  $_propagation = $propagation?{
    undef => '',
    'rprivate' => '',
    default => ",bind-propagation=${propagation}"
  }
  
  $_type = $type?{
    undef => 'bind',
    default => $type
  }
  
  "type=${_type},source=${source},destination=${destination}${_readonly}${_propagation}"
}
